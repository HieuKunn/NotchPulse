//
//  ClipboardManager.swift
//  NotchPulse
//
//  Created by Alexander on 2026-09-26.
//

import AppKit
import Combine
import Defaults
import Foundation

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
    let imageData: Data?
    let timestamp: Date

    var isImage: Bool {
        return type == .image || imageData != nil
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

    enum CodingKeys: String, CodingKey {
        case id, type, contentString, urlString, imageData, timestamp
    }

    init(id: UUID = UUID(), type: ClipboardType = .text, contentString: String?, urlString: String? = nil, imageData: Data?, timestamp: Date = Date()) {
        self.id = id
        self.type = type
        self.contentString = contentString
        self.urlString = urlString
        self.imageData = imageData
        self.timestamp = timestamp
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        type = try container.decodeIfPresent(ClipboardType.self, forKey: .type) ?? .text
        contentString = try container.decodeIfPresent(String.self, forKey: .contentString)
        urlString = try container.decodeIfPresent(String.self, forKey: .urlString)
        imageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
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
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int = -1
    private let storageKey = "NotchPulse_SavedClipboardHistory"
    private var cancellables = Set<AnyCancellable>()

    private init() {
        loadHistory()
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

            // Run timer in .common mode at 0.2s interval so it catches copies with zero perceived delay
            let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
                self?.checkForChanges()
            }
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
        }
    }

    private func checkForChanges() {
        guard isEnabled else { return }
        let currentCount = pasteboard.changeCount
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        // 1. Check File URLs first
        if let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           let firstURL = fileURLs.first {
            let urlString = firstURL.absoluteString
            if history.first?.urlString == urlString || history.first?.contentString == firstURL.path {
                return
            }
            let newItem = ClipboardItem(
                id: UUID(),
                type: .file,
                contentString: firstURL.path,
                urlString: urlString,
                imageData: nil,
                timestamp: Date()
            )
            insertItem(newItem)
            return
        }

        // 2. Check Web / Network URLs
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

        // 3. Check Text / String
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
            } else if trimmed.hasPrefix("file://"), let fileURL = URL(string: trimmed) {
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

        // 4. Check Raw Image
        let imageTypes: [NSPasteboard.PasteboardType] = [
            .png,
            .tiff,
            NSPasteboard.PasteboardType("public.jpeg"),
            NSPasteboard.PasteboardType("public.png"),
            NSPasteboard.PasteboardType("public.tiff")
        ]
        let hasImageTypes = pasteboard.types?.contains(where: { imageTypes.contains($0) }) ?? false
        let canInitImage = NSImage.canInit(with: pasteboard)

        if hasImageTypes || canInitImage {
            if let image = NSImage(pasteboard: pasteboard),
               let tiff = image.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiff),
               let pngData = bitmap.representation(using: .png, properties: [:]) {

                if history.first?.imageData == pngData {
                    return
                }

                let newItem = ClipboardItem(
                    id: UUID(),
                    type: .image,
                    contentString: nil,
                    urlString: nil,
                    imageData: pngData,
                    timestamp: Date()
                )
                insertItem(newItem)
                return
            }
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
        // Remove any identical content string or duplicate ID
        self.history.removeAll { existing in
            if existing.id == item.id { return true }
            if let newContent = item.contentString, let existingContent = existing.contentString {
                return newContent == existingContent
            }
            if item.isImage && existing.isImage, let d1 = item.imageData, let d2 = existing.imageData {
                return d1 == d2
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
            history = Array(history.prefix(limit))
        }
    }

    private func saveHistory() {
        let itemsToSave = Array(history.prefix(30)).map { item in
            // Exclude huge images from UserDefaults (> 1MB)
            if let data = item.imageData, data.count > 1_000_000 {
                return ClipboardItem(id: item.id, type: item.type, contentString: item.contentString, urlString: item.urlString, imageData: nil, timestamp: item.timestamp)
            }
            return item
        }
        if let data = try? JSONEncoder().encode(itemsToSave) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let items = try? JSONDecoder().decode([ClipboardItem].self, from: data) {
            self.history = items
        }
    }

    func copyToPasteboard(_ item: ClipboardItem) {
        pasteboard.clearContents()
        
        if item.isImage, let data = item.imageData, let image = NSImage(data: data) {
            pasteboard.writeObjects([image])
            pasteboard.setData(data, forType: .png)
            pasteboard.setData(data, forType: NSPasteboard.PasteboardType("public.png"))
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
        history.removeAll()
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}
