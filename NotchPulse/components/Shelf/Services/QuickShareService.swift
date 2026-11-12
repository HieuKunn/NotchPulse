import AppKit
import Foundation
import UniformTypeIdentifiers

/// Dynamic representation of a sharing provider discovered at runtime
struct QuickShareProvider: Identifiable, Hashable, Sendable {
    var id: String
    var imageData: Data?
    var supportsRawText: Bool

    /// Returns a square-proportioned `NSImage` sized explicitly to `pointSize × pointSize`
    /// so SwiftUI `Picker`/menu rows render crisp icons without horizontal stretching.
    func iconImage(pointSize: CGFloat) -> NSImage? {
        guard let imageData, let image = NSImage(data: imageData) else { return nil }
        let targetSize = NSSize(width: pointSize, height: pointSize)
        image.size = targetSize
        for rep in image.representations {
            rep.size = targetSize
        }
        return image
    }
}

class QuickShareService: ObservableObject {
    static let shared = QuickShareService()
    
    @Published var availableProviders: [QuickShareProvider] = []
    @Published var isPickerOpen = false
    private var cachedServices: [String: NSSharingService] = [:]
    private var isDiscoveringProviders = false
    // Hold security-scoped URLs during sharing
    private var sharingAccessingURLs: [URL] = []
    private var lifecycleDelegate: SharingLifecycleDelegate?
   
    init() {
        Task {
            await discoverAvailableProviders()
        }
    }
    
    // MARK: - Provider Discovery
    
    @MainActor
    func discoverAvailableProviders() async {
        guard !isDiscoveringProviders else { return }
        isDiscoveringProviders = true
        defer { isDiscoveringProviders = false }
        let finder = ShareServiceFinder()

        // Use simple test items without creating actual temp files
        // This avoids issues with the Share Sheet retaining references to deleted files
        let testItems: [Any] = [
            URL(string:"http://example.com") ?? URL(fileURLWithPath: "/"),
            "Test Text" as NSString
        ]

        var providers: [QuickShareProvider] = []

        // Register native AirDrop as the primary sharing provider
        if let airDropService = NSSharingService(named: .sendViaAirDrop) {
            let imgData = Self.normalizedSquarePNGData(from: airDropService.image)
            let adProvider = QuickShareProvider(id: "AirDrop", imageData: imgData, supportsRawText: false)
            providers.append(adProvider)
            cachedServices["AirDrop"] = airDropService
            cachedServices[NSSharingService.Name.sendViaAirDrop.rawValue] = airDropService
        }

        let services = await finder.findApplicableServices(for: testItems)

        for svc in services {
            let title = svc.title
            if title == "AirDrop" { continue }
            let imgData = Self.resolveServiceIconData(for: svc)
            let supportsRawText = svc.canPerform(withItems: ["Test Text"])
            let provider = QuickShareProvider(id: title, imageData: imgData, supportsRawText: supportsRawText)
            if !providers.contains(provider) {
                providers.append(provider)
                cachedServices[title] = svc
            }
        }

        if !providers.contains(where: { $0.id == "System Share Menu" }) {
            providers.append(QuickShareProvider(id: "System Share Menu", imageData: nil, supportsRawText: true))
        }

        self.availableProviders = providers

    }

    // MARK: - Icon Resolution Helpers

    /// Extracts the service/extension identifier embedded in `NSSharingService.description`,
    /// e.g. `"com.apple.Notes.SharingExtension"` from `<NSSharingService: 0x...> [com.apple.Notes.SharingExtension] - enabled:YES`.
    static func extractServiceBundleID(from description: String) -> String? {
        guard let openBracket = description.firstIndex(of: "["),
              let closeBracket = description[openBracket...].firstIndex(of: "]"),
              openBracket < closeBracket else {
            return nil
        }
        let raw = description[description.index(after: openBracket)..<closeBracket]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? nil : raw
    }

    /// Maps a sharing service or app-extension identifier to ordered candidate host app bundle IDs.
    static func candidateAppBundleIDs(forServiceID serviceID: String) -> [String] {
        let explicitMap: [String: [String]] = [
            "com.apple.share.Mail.compose": ["com.apple.mail"],
            "com.apple.share.Messages.window": ["com.apple.MobileSMS"],
            "com.apple.share.Messages.compose": ["com.apple.MobileSMS"],
            "com.apple.share.System.add-to-safari-reading-list": ["com.apple.Safari"],
            "com.apple.share.System.set-desktop-image": ["com.apple.Photos"],
            "com.apple.share.System.add-to-iphoto": ["com.apple.Photos"]
        ]

        var candidates = explicitMap[serviceID] ?? []
        let parts = serviceID.split(separator: ".")
        if parts.count >= 2 {
            for dropCount in 0..<(parts.count - 1) {
                let slice = parts.dropLast(dropCount)
                guard slice.count >= 2 else { break }
                let candidate = slice.joined(separator: ".")
                if !candidates.contains(candidate) {
                    candidates.append(candidate)
                }
            }
        }
        return candidates
    }

    /// Renders `image` aspect-fitted inside a square `pixelSize × pixelSize` Retina bitmap
    /// and returns PNG data, or `nil` if the image draws no visible pixels (such as a lazy placeholder).
    static func normalizedSquarePNGData(from image: NSImage, pixelSize: Int = 64) -> Data? {
        guard pixelSize > 0 else { return nil }
        let pointSize = CGFloat(pixelSize) / 2.0
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelSize,
            pixelsHigh: pixelSize,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }
        rep.size = NSSize(width: pointSize, height: pointSize)

        let sourceSize = image.size
        let drawRect: NSRect
        if sourceSize.width > 0, sourceSize.height > 0 {
            let scale = min(pointSize / sourceSize.width, pointSize / sourceSize.height)
            let w = sourceSize.width * scale
            let h = sourceSize.height * scale
            drawRect = NSRect(x: (pointSize - w) / 2.0, y: (pointSize - h) / 2.0, width: w, height: h)
        } else {
            drawRect = NSRect(x: 0, y: 0, width: pointSize, height: pointSize)
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: drawRect, from: .zero, operation: .copy, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()

        // Verify at least one non-transparent pixel was drawn before accepting the bitmap.
        guard let bitmapData = rep.bitmapData else { return nil }
        let byteCount = rep.bytesPerRow * pixelSize
        var hasVisiblePixel = false
        var offset = 3 // alpha byte in RGBA
        while offset < byteCount {
            if bitmapData[offset] > 0 {
                hasVisiblePixel = true
                break
            }
            offset += 4
        }
        guard hasVisiblePixel else { return nil }

        return rep.representation(using: .png, properties: [:])
    }

    private static func resolveServiceIconData(for service: NSSharingService) -> Data? {
        let serviceID = extractServiceBundleID(from: service.description)

        if serviceID == "com.apple.share.AirDrop.send" || service.title == "AirDrop",
           let airDropImage = NSSharingService(named: .sendViaAirDrop)?.image,
           let data = normalizedSquarePNGData(from: airDropImage) {
            return data
        }

        if let serviceID {
            for bundleID in candidateAppBundleIDs(forServiceID: serviceID) {
                if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                    let appIcon = NSWorkspace.shared.icon(forFile: appURL.path)
                    if let data = normalizedSquarePNGData(from: appIcon) {
                        return data
                    }
                }
            }

            if let namedImage = NSSharingService(named: .init(rawValue: serviceID))?.image,
               let data = normalizedSquarePNGData(from: namedImage) {
                return data
            }
        }

        if let serviceData = normalizedSquarePNGData(from: service.image) {
            return serviceData
        }

        // Last-resort lookup by app display name when an extension uses an unrelated bundle ID prefix.
        let searchDirectories = ["/Applications", "/System/Applications", "/System/Applications/Utilities"]
        for dir in searchDirectories {
            let candidateURL = URL(fileURLWithPath: dir).appendingPathComponent("\(service.title).app")
            if FileManager.default.fileExists(atPath: candidateURL.path) {
                let appIcon = NSWorkspace.shared.icon(forFile: candidateURL.path)
                if let data = normalizedSquarePNGData(from: appIcon) {
                    return data
                }
            }
        }

        return nil
    }
    
    // MARK: - File Picker
    @MainActor
    func showFilePicker(for provider: QuickShareProvider, from view: NSView?) async {
        guard !isPickerOpen else {
            print("⚠️ QuickShareService: File picker already open")
            return
        }

        isPickerOpen = true
        SharingStateManager.shared.beginInteraction()

        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.title = "Select Files for \(provider.id)"
        panel.message = "Choose files to share via \(provider.id)"

        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            defer {
                self?.isPickerOpen = false
                SharingStateManager.shared.endInteraction()
            }

            if response == .OK && !panel.urls.isEmpty {
                Task {
                    await self?.shareFilesOrText(panel.urls, using: provider, from: view)
                }
            }
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 10)
        let response = panel.runModal()
        if SettingsWindowController.shared.window?.isVisible != true {
            NSApp.setActivationPolicy(.accessory)
        }
        completion(response)
    }
    
    // MARK: - Sharing
    @MainActor
    func shareFilesOrText(_ items: [Any], using provider: QuickShareProvider, from view: NSView?) async {
        let fileURLs = items.compactMap { $0 as? URL }.filter { $0.isFileURL }
        // Stop any previous sharing access
        stopSharingAccessingURLs()
        // Start security-scoped access for all file URLs
        sharingAccessingURLs = fileURLs.filter { $0.startAccessingSecurityScopedResource() }

        // Setup lifecycle delegate to keep notch open during picker/service
        let delegate = SharingStateManager.shared.makeDelegate { [weak self] in
            self?.lifecycleDelegate = nil
            self?.stopSharingAccessingURLs()
        }
        lifecycleDelegate = delegate

        // If sharing via AirDrop, execute native AirDrop service directly
        if provider.id == "AirDrop" || provider.id == NSSharingService.Name.sendViaAirDrop.rawValue {
            if let airdropSvc = cachedServices["AirDrop"] ?? NSSharingService(named: .sendViaAirDrop) {
                delegate.markServiceBegan()
                airdropSvc.delegate = delegate
                airdropSvc.perform(withItems: items)
                return
            }
        }

        if let svc = cachedServices[provider.id], svc.canPerform(withItems: items) {
            // For direct service path, explicitly mark service interaction start
            delegate.markServiceBegan()
            svc.delegate = delegate
            svc.perform(withItems: items)
        } else {
            let picker = NSSharingServicePicker(items: items)
            picker.delegate = delegate
            delegate.markPickerBegan()
            if let view {
                picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
            }
        }
    }

    private func stopSharingAccessingURLs() {
        NSLog("Stopping sharing access to URLs")
        for url in sharingAccessingURLs {
            url.stopAccessingSecurityScopedResource()
        }
        sharingAccessingURLs.removeAll()
    }
// MARK: - SharingServiceDelegate

private class SharingServiceDelegate: NSObject {}
    
    @MainActor
    func shareDroppedFiles(_ providers: [NSItemProvider], using shareProvider: QuickShareProvider, from view: NSView?) async {
        var itemsToShare: [Any] = []
        var foundText: String?

        for provider in providers {
            if let webURL = await provider.extractURL() {
                itemsToShare.append(webURL)
            } else if foundText == nil, let text = await provider.extractText() {
                foundText = text
            } else if let itemFileURL = await provider.extractItem() {
                let resolvedURL = await resolveShelfItemBookmark(for: itemFileURL) ?? itemFileURL
                itemsToShare.append(resolvedURL)
            }
        }

        // If text was found, prioritize sharing it.
        if let text = foundText {
            if shareProvider.supportsRawText {
                await shareFilesOrText([text], using: shareProvider, from: view)
            } else {
                if let tempTextURL = await TemporaryFileStorageService.shared.createTempFile(for: .text(text)) {
                    await shareFilesOrText([tempTextURL], using: shareProvider, from: view)
                    TemporaryFileStorageService.shared.removeTemporaryFileIfNeeded(at: tempTextURL)
                } else {
                    await shareFilesOrText([text], using: shareProvider, from: view)
                }
            }
        } else if !itemsToShare.isEmpty {
            await shareFilesOrText(itemsToShare, using: shareProvider, from: view)
        }
    }

    private func resolveShelfItemBookmark(for fileURL: URL) async -> URL? {
        let items = await ShelfStateViewModel.shared.items

        for itm in items {
            if let resolved = await ShelfStateViewModel.shared.resolveAndUpdateBookmark(for: itm) {
                if resolved.standardizedFileURL.path == fileURL.standardizedFileURL.path {
                    return resolved
                }
            }
        }
        print("❌ Failed to resolve bookmark for shelf item")
        return nil
    }
}

// MARK: - App Storage Extension for Provider Selection

extension QuickShareProvider {
    static var defaultProvider: QuickShareProvider {
        let svc = QuickShareService.shared

        if let airdrop = svc.availableProviders.first(where: { $0.id == "AirDrop" }) {
            return airdrop
        }
        return svc.availableProviders.first ?? QuickShareProvider(id: "System Share Menu", imageData: nil, supportsRawText: true)
    }
}
