import AppKit
import Combine
import CoreGraphics
import Defaults
import Foundation
import ImageIO

enum ClipboardType: String, Codable {
    case text
    case url
    case image
    case file
}

struct ClipboardItem: Identifiable, Codable, Equatable {
    let id: UUID
    var type: ClipboardType = .text
    let contentString: String?
    var urlString: String? = nil
    var thumbnailData: Data? = nil
    var diskFilePath: String? = nil
    let timestamp: Date

    var isImage: Bool {
        return type == .image || thumbnailData != nil || diskFilePath != nil
    }
    
    var displayString: String {
        if isImage {
            return "[Copied Image]"
        }
        if type == .file, let str = urlString ?? contentString {
            if let url = URL(string: str) {
                return url.lastPathComponent
            }
            return (str as NSString).lastPathComponent
        }
        if let text = contentString {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return "Image / Rich Data"
    }

    /// Dynamically loads full image data from disk cache file on demand; never hoarded in RAM.
    var imageData: Data? {
        if let path = diskFilePath, FileManager.default.fileExists(atPath: path) {
            return try? Data(contentsOf: URL(fileURLWithPath: path))
        }
        return thumbnailData
    }

    enum CodingKeys: String, CodingKey {
        case id, type, contentString, urlString, thumbnailData, diskFilePath, timestamp, imageData
    }

    init(
        id: UUID = UUID(),
        type: ClipboardType = .text,
        contentString: String?,
        urlString: String? = nil,
        thumbnailData: Data? = nil,
        diskFilePath: String? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.contentString = contentString
        self.urlString = urlString
        self.thumbnailData = thumbnailData
        self.diskFilePath = diskFilePath
        self.timestamp = timestamp
    }

    // Compatibility initializer
    init(
        id: UUID = UUID(),
        type: ClipboardType = .text,
        contentString: String?,
        urlString: String? = nil,
        imageData: Data?,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.contentString = contentString
        self.urlString = urlString
        self.thumbnailData = imageData
        self.diskFilePath = nil
        self.timestamp = timestamp
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        type = try container.decodeIfPresent(ClipboardType.self, forKey: .type) ?? .text
        contentString = try container.decodeIfPresent(String.self, forKey: .contentString)
        urlString = try container.decodeIfPresent(String.self, forKey: .urlString)
        thumbnailData = try container.decodeIfPresent(Data.self, forKey: .thumbnailData)
        diskFilePath = try container.decodeIfPresent(String.self, forKey: .diskFilePath)
        timestamp = try container.decode(Date.self, forKey: .timestamp)

        if thumbnailData == nil, let legacy = try container.decodeIfPresent(Data.self, forKey: .imageData) {
            thumbnailData = legacy
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(contentString, forKey: .contentString)
        try container.encodeIfPresent(urlString, forKey: .urlString)
        try container.encodeIfPresent(thumbnailData, forKey: .thumbnailData)
        try container.encodeIfPresent(diskFilePath, forKey: .diskFilePath)
        try container.encode(timestamp, forKey: .timestamp)
    }
}

final class ClipboardManager: ObservableObject {
    static let shared = ClipboardManager()

    @Published var history: [ClipboardItem] = []
    @Published var isEnabled: Bool = Defaults[.enableClipboardManager] {
        didSet {
            if Defaults[.enableClipboardManager] != isEnabled {
                Defaults[.enableClipboardManager] = isEnabled
            }
            if isEnabled {
                startMonitoring()
            } else {
                stopMonitoring()
            }
        }
    }
    @Published var maxItems: Int = Defaults[.clipboardMaxItems] {
        didSet {
            if Defaults[.clipboardMaxItems] != maxItems {
                Defaults[.clipboardMaxItems] = maxItems
            }
            trimHistory()
        }
    }

    private var pollTimer: Timer?
    private var copyKeyMonitor: Any?
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int = -1
    private let storageKey = "NotchPulse_SavedClipboardHistory"
    private var cancellables = Set<AnyCancellable>()

    private init() {
        loadHistory()
        cleanupOrphanedTempFiles()
        self.lastChangeCount = pasteboard.changeCount - 1
        if isEnabled {
            startMonitoring()
            if history.isEmpty {
                checkForChanges()
            }
        }
        
        // Listen to default changes
        Defaults.publisher(.enableClipboardManager)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] val in
                guard let self = self else { return }
                if self.isEnabled != val.newValue {
                    self.isEnabled = val.newValue
                }
            }
            .store(in: &cancellables)
            
        Defaults.publisher(.clipboardMaxItems)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] val in
                guard let self = self else { return }
                if self.maxItems != val.newValue {
                    self.maxItems = val.newValue
                }
            }
            .store(in: &cancellables)
    }

    func startMonitoring() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.stopMonitoring()

            // 1. Instant event-driven copy detector: Fires with multi-tick check on Cmd+C / Cmd+X / Screenshots
            if AXIsProcessTrusted() {
                self.copyKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                    if flags.contains(.command), let chars = event.charactersIgnoringModifiers?.lowercased() {
                        if chars == "c" || chars == "x" {
                            // Multiple staggered checks to capture fast AppKit apps, standard apps, and heavy Electron/browsers
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self?.checkForChanges() }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self?.checkForChanges() }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) { self?.checkForChanges() }
                        } else if chars == "3" || chars == "4" || chars == "5" {
                            // System screen capture takes 200-500ms to encode and write to pasteboard
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self?.checkForChanges() }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.50) { self?.checkForChanges() }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.80) { self?.checkForChanges() }
                        }
                    }
                }
            }

            // 2. High-speed, zero-CPU polling (0.15s / 150ms) for context menu copies, drag copies, and apps without key events
            // Checking pasteboard.changeCount is a single integer lookup (< 2 microseconds), taking 0.0% CPU.
            let timer = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in
                self?.checkForChanges()
            }
            timer.tolerance = 0.05
            RunLoop.main.add(timer, forMode: .common)
            self.pollTimer = timer

            // Check immediately on startup
            self.checkForChanges()
        }
    }

    func checkImmediately() {
        if Thread.isMainThread {
            self.checkForChanges()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.checkForChanges()
            }
        }
    }

    func stopMonitoring() {
        DispatchQueue.main.async { [weak self] in
            self?.pollTimer?.invalidate()
            self?.pollTimer = nil
            if let monitor = self?.copyKeyMonitor {
                NSEvent.removeMonitor(monitor)
                self?.copyKeyMonitor = nil
            }
        }
    }

    private static let supportedImageTypes: [NSPasteboard.PasteboardType] = [
        .png,
        .tiff,
        NSPasteboard.PasteboardType("public.png"),
        NSPasteboard.PasteboardType("public.jpeg"),
        NSPasteboard.PasteboardType("public.heic"),
        NSPasteboard.PasteboardType("public.webp"),
        NSPasteboard.PasteboardType("com.compuserve.gif"),
        NSPasteboard.PasteboardType("public.tiff"),
        NSPasteboard.PasteboardType("Apple PNG pasteboard type"),
        NSPasteboard.PasteboardType("Apple PICT pasteboard type")
    ]

    private func checkForChanges() {
        guard isEnabled else { return }
        let currentCount = pasteboard.changeCount
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        // 1. Check Raw Images FIRST (Prevents web browsers & Electron apps from having their images shadowed by fallback text URLs / HTML)
        let hasImageTypes = pasteboard.types?.contains(where: { Self.supportedImageTypes.contains($0) }) ?? false
        let canInitImage = NSImage.canInit(with: pasteboard)

        if hasImageTypes || canInitImage {
            let rawImageData: Data? = {
                for t in Self.supportedImageTypes {
                    if let d = pasteboard.data(forType: t), !d.isEmpty {
                        return d
                    }
                }
                if let image = NSImage(pasteboard: pasteboard) {
                    return Self.extractRawData(from: image)
                }
                return nil
            }()

            if let rawData = rawImageData, !rawData.isEmpty {
                // If there's an associated web URL for the image, capture it too
                let rawString = pasteboard.string(forType: .string)
                    ?? pasteboard.string(forType: NSPasteboard.PasteboardType("public.utf8-plain-text"))
                let associatedURL: String? = {
                    guard let s = rawString?.trimmingCharacters(in: .whitespacesAndNewlines),
                          let u = URL(string: s), ["http", "https"].contains(u.scheme?.lowercased()) else { return nil }
                    return s
                }()

                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    guard let self = self else { return }
                    autoreleasepool {
                        // Generate thumbnail (max 96x96 px)
                        guard let thumbData = Self.generateThumbnailData(from: rawData, maxDimension: 96) ?? rawData.prefix(60_000) as Data? else { return }

                        // Check duplicate with top history item
                        if let first = self.history.first, first.isImage, first.thumbnailData == thumbData {
                            return
                        }

                        // Save full image to disk temp file so RAM stays untouched
                        let itemId = UUID()
                        let tempFile = Self.clipboardTempDir.appendingPathComponent("\(itemId.uuidString).dat")
                        if let fullData = Self.generateOptimizedImageData(from: rawData, maxDimension: 1600) {
                            try? fullData.write(to: tempFile, options: .atomic)
                        } else {
                            try? rawData.write(to: tempFile, options: .atomic)
                        }

                        let item = ClipboardItem(
                            id: itemId,
                            type: .image,
                            contentString: nil,
                            urlString: associatedURL,
                            thumbnailData: thumbData,
                            diskFilePath: tempFile.path,
                            timestamp: Date()
                        )
                        self.insertItem(item)
                    }
                }
                return
            }
        }

        // 2. Check File URLs (including image files and multiple files selected in Finder)
        if let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !fileURLs.isEmpty {
            let imageExtensions = Set(["png", "jpg", "jpeg", "heic", "webp", "gif", "tiff", "bmp", "svg"])
            // Process copied files (up to 10 in reverse order so first copied appears at top)
            let urlsToProcess = Array(fileURLs.prefix(10).reversed())
            for fileURL in urlsToProcess {
                let path = fileURL.path
                let urlString = fileURL.absoluteString
                let ext = fileURL.pathExtension.lowercased()

                if imageExtensions.contains(ext),
                   FileManager.default.fileExists(atPath: path),
                   let fileData = try? Data(contentsOf: fileURL, options: .mappedIfSafe),
                   let thumbData = Self.generateThumbnailData(from: fileData, maxDimension: 96) {
                    let item = ClipboardItem(
                        id: UUID(),
                        type: .image,
                        contentString: fileURL.lastPathComponent,
                        urlString: urlString,
                        thumbnailData: thumbData,
                        diskFilePath: path,
                        timestamp: Date()
                    )
                    insertItem(item)
                } else {
                    let item = ClipboardItem(
                        id: UUID(),
                        type: .file,
                        contentString: path,
                        urlString: urlString,
                        imageData: nil,
                        timestamp: Date()
                    )
                    insertItem(item)
                }
            }
            return
        }

        // 3. Check Web / Network URLs
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let firstURL = urls.first, !firstURL.isFileURL {
            let urlString = firstURL.absoluteString
            if history.first?.urlString == urlString || history.first?.contentString == urlString {
                return
            }
            let newItem = ClipboardItem(
                id: UUID(),
                type: .url,
                contentString: urlString,
                urlString: urlString,
                imageData: nil,
                timestamp: Date()
            )
            insertItem(newItem)
            return
        }

        // 4. Check Text / String
        let rawString = pasteboard.string(forType: .string)
            ?? pasteboard.string(forType: NSPasteboard.PasteboardType("public.utf8-plain-text"))
            ?? pasteboard.string(forType: NSPasteboard.PasteboardType("NSStringPboardType"))

        if let string = rawString, !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if history.first?.contentString == string {
                return
            }

            var itemType: ClipboardType = .text
            var urlStr: String? = nil
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if let url = URL(string: trimmed), let scheme = url.scheme, ["http", "https", "ftp"].contains(scheme.lowercased()) {
                itemType = .url
                urlStr = trimmed
            } else if trimmed.hasPrefix("file://"), URL(string: trimmed) != nil {
                itemType = .file
                urlStr = trimmed
            }

            let newItem = ClipboardItem(
                id: UUID(),
                type: itemType,
                contentString: string,
                urlString: urlStr,
                imageData: nil,
                timestamp: Date()
            )
            insertItem(newItem)
            return
        }
    }

    private func insertItem(_ item: ClipboardItem) {
        if Thread.isMainThread {
            applyInsertion(item)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.applyInsertion(item)
            }
        }
    }

    private func applyInsertion(_ item: ClipboardItem) {
        // Remove any identical content string or duplicate image
        self.history.removeAll { existing in
            if existing.id == item.id {
                if let path = existing.diskFilePath, path != item.diskFilePath {
                    try? FileManager.default.removeItem(atPath: path)
                }
                return true
            }
            if let newContent = item.contentString, let existingContent = existing.contentString, !newContent.isEmpty {
                return newContent == existingContent
            }
            if item.isImage && existing.isImage {
                if let d1 = item.thumbnailData, let d2 = existing.thumbnailData, d1 == d2 {
                    if let path = existing.diskFilePath, path != item.diskFilePath {
                        try? FileManager.default.removeItem(atPath: path)
                    }
                    return true
                }
                if let p1 = item.diskFilePath, let p2 = existing.diskFilePath, p1 == p2 {
                    return true
                }
            }
            return false
        }
        self.history.insert(item, at: 0)
        self.trimHistory()
        self.saveHistory()
    }

    private func trimHistory() {
        let limit = max(5, maxItems)
        if history.count > limit {
            let removed = history.suffix(from: limit)
            for item in removed {
                if let path = item.diskFilePath {
                    try? FileManager.default.removeItem(atPath: path)
                }
            }
            history = Array(history.prefix(limit))
        }
    }

    private func saveHistory() {
        let itemsToSave = Array(history.prefix(30))
        if let data = try? JSONEncoder().encode(itemsToSave) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let items = try? JSONDecoder().decode([ClipboardItem].self, from: data) {
            // Sanitize history: ensure legacy items don't hoard large uncompressed images in thumbnailData
            var sanitized: [ClipboardItem] = []
            for var item in items {
                if item.isImage, let thumb = item.thumbnailData, thumb.count > 40_000 {
                    if let downscaled = Self.generateThumbnailData(from: thumb, maxDimension: 96) {
                        item.thumbnailData = downscaled
                    }
                }
                sanitized.append(item)
            }
            self.history = sanitized
        }
    }

    func copyToPasteboard(_ item: ClipboardItem) {
        pasteboard.clearContents()

        if item.isImage {
            // Autoreleasepool ensures full image representation is purged from RAM as soon as written to pasteboard
            autoreleasepool {
                let fullData: Data? = {
                    if let path = item.diskFilePath, FileManager.default.fileExists(atPath: path) {
                        return try? Data(contentsOf: URL(fileURLWithPath: path))
                    }
                    return item.thumbnailData
                }()

                if let data = fullData, let image = NSImage(data: data) {
                    pasteboard.writeObjects([image])
                    pasteboard.setData(data, forType: .png)
                    pasteboard.setData(data, forType: NSPasteboard.PasteboardType("public.png"))
                }
            }
        } else if item.type == .file || (item.urlString?.hasPrefix("file://") == true),
                  let fileStr = item.urlString ?? item.contentString,
                  let fileURL = URL(string: fileStr) {
            pasteboard.writeObjects([fileURL as NSURL, fileStr as NSString])
        } else if item.type == .url || (item.urlString?.hasPrefix("http") == true),
                  let urlStr = item.urlString ?? item.contentString,
                  let url = URL(string: urlStr) {
            pasteboard.writeObjects([url as NSURL, urlStr as NSString])
        } else if let text = item.contentString {
            if let url = URL(string: text), let scheme = url.scheme, ["http", "https", "ftp", "file"].contains(scheme.lowercased()) {
                pasteboard.writeObjects([url as NSURL, text as NSString])
            } else {
                pasteboard.setString(text, forType: .string)
            }
        }
        lastChangeCount = pasteboard.changeCount
    }

    func clearHistory() {
        for item in history {
            if let path = item.diskFilePath {
                try? FileManager.default.removeItem(atPath: path)
            }
        }
        history.removeAll()
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    // MARK: - Temp Cache & Zero-RAM-Spike Image Downscaling Helpers

    private static let clipboardTempDir: URL = {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("NotchPulseClipboard", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static func extractRawData(from image: NSImage) -> Data? {
        if let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
            return rep.representation(using: .png, properties: [:])
                ?? rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
                ?? tiff
        }
        var proposedRect = NSRect(origin: .zero, size: image.size)
        if let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) {
            let bitmap = NSBitmapImageRep(cgImage: cgImage)
            return bitmap.representation(using: .png, properties: [:])
                ?? bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
        }
        return image.tiffRepresentation
    }

    /// Generates lightweight thumbnail without ever loading the full-sized pixel buffer into RAM.
    /// Uses `kCGImageSourceShouldCache: false` to decode exclusively at thumbnail dimensions.
    private static func generateThumbnailData(from rawData: Data, maxDimension: CGFloat = 96) -> Data? {
        let sourceOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: false
        ]
        guard let source = CGImageSourceCreateWithData(rawData as CFData, sourceOptions as CFDictionary) else {
            return nil
        }
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            return nil
        }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        let alpha = cgImage.alphaInfo
        let hasAlpha = alpha == .first || alpha == .last || alpha == .premultipliedFirst || alpha == .premultipliedLast
        if hasAlpha {
            return bitmap.representation(using: .png, properties: [:])
        } else {
            return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.80])
        }
    }

    private static func generateThumbnailData(from image: NSImage, maxDimension: CGFloat = 96) -> Data? {
        var proposedRect = NSRect(origin: .zero, size: image.size)
        if let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) {
            let bitmap = NSBitmapImageRep(cgImage: cgImage)
            if let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.80]) {
                return generateThumbnailData(from: data, maxDimension: maxDimension)
            }
        }
        if let tiff = image.tiffRepresentation {
            return generateThumbnailData(from: tiff, maxDimension: maxDimension)
        }
        return nil
    }

    /// Resizes high-res images to a maximum dimension of 1600px and saves as optimized JPEG/PNG on disk,
    /// decoding on-demand with zero full-size uncompressed memory allocation.
    private static func generateOptimizedImageData(from rawData: Data, maxDimension: CGFloat = 1600) -> Data? {
        let sourceOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: false
        ]
        guard let source = CGImageSourceCreateWithData(rawData as CFData, sourceOptions as CFDictionary) else {
            return nil
        }
        let downscaleOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downscaleOptions as CFDictionary) else {
            return nil
        }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        let alpha = cgImage.alphaInfo
        let hasAlpha = alpha == .first || alpha == .last || alpha == .premultipliedFirst || alpha == .premultipliedLast
        if hasAlpha {
            return bitmap.representation(using: .png, properties: [:])
        } else {
            return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
        }
    }

    private func cleanupOrphanedTempFiles() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }
            let validPaths = Set(self.history.compactMap { $0.diskFilePath })
            if let files = try? FileManager.default.contentsOfDirectory(at: Self.clipboardTempDir, includingPropertiesForKeys: nil) {
                for file in files {
                    if !validPaths.contains(file.path) {
                        try? FileManager.default.removeItem(at: file)
                    }
                }
            }
        }
    }
}
