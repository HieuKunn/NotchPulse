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
            Defaults[.enableClipboardManager] = isEnabled
            if isEnabled {
                startMonitoring()
            } else {
                stopMonitoring()
            }
        }
    }
    @Published var maxItems: Int = Defaults[.clipboardMaxItems] {
        didSet {
            Defaults[.clipboardMaxItems] = maxItems
            trimHistory()
        }
    }

    private var pollTimer: Timer?
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int = -1

    private init() {
        self.lastChangeCount = pasteboard.changeCount
        if isEnabled {
            startMonitoring()
        }
        
        // Listen to default changes
        Defaults.publisher(.enableClipboardManager)
            .sink { [weak self] val in
                self?.isEnabled = val.newValue
            }
            .store(in: &cancellables)
            
        Defaults.publisher(.clipboardMaxItems)
            .sink { [weak self] val in
                self?.maxItems = val.newValue
            }
            .store(in: &cancellables)
    }

    private var cancellables = Set<AnyCancellable>()

    func startMonitoring() {
        stopMonitoring()
        lastChangeCount = pasteboard.changeCount

        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            self?.checkForChanges()
        }
    }

    func stopMonitoring() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func checkForChanges() {
        guard isEnabled else { return }
        let currentCount = pasteboard.changeCount
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        // 1. Check Image FIRST (Check if pasteboard contains raw image types or NSImage)
        let imageTypes: [NSPasteboard.PasteboardType] = [
            .png,
            .tiff,
            NSPasteboard.PasteboardType("public.jpeg"),
            NSPasteboard.PasteboardType("public.png"),
            NSPasteboard.PasteboardType("public.tiff")
        ]
        
        let hasImageTypes = pasteboard.types?.contains(where: { imageTypes.contains($0) }) ?? false
        let canInitImage = NSImage.canInit(with: pasteboard)

        if hasImageTypes || (canInitImage && pasteboard.data(forType: .string) == nil) {
            if let image = NSImage(pasteboard: pasteboard),
               let tiff = image.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiff),
               let pngData = bitmap.representation(using: .png, properties: [:]) {

                // Avoid duplicate image if identical data
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

                DispatchQueue.main.async {
                    self.history.insert(newItem, at: 0)
                    self.trimHistory()
                }
                return
            }
        }

        // 2. Check File URL or Web URL
        if let url = NSURL(from: pasteboard) as URL?, let urlString = url.absoluteString, !urlString.isEmpty {
            let isFile = url.isFileURL
            let itemType: ClipboardType = isFile ? .file : .url

            // Avoid duplicate url at top
            if history.first?.urlString == urlString || history.first?.contentString == urlString {
                return
            }

            let newItem = ClipboardItem(
                id: UUID(),
                type: itemType,
                contentString: urlString,
                urlString: urlString,
                imageData: nil,
                timestamp: Date()
            )

            DispatchQueue.main.async {
                self.history.insert(newItem, at: 0)
                self.trimHistory()
            }
            return
        }

        // 3. Check Text / String
        if let string = pasteboard.string(forType: .string), !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            var itemType: ClipboardType = .text
            var urlStr: String? = nil
            if let url = URL(string: string), let scheme = url.scheme, ["http", "https", "ftp", "file"].contains(scheme.lowercased()) {
                itemType = url.isFileURL ? .file : .url
                urlStr = string
            }

            // Avoid duplicate text at top
            if history.first?.contentString == string {
                return
            }

            let newItem = ClipboardItem(
                id: UUID(),
                type: itemType,
                contentString: string,
                urlString: urlStr,
                imageData: nil,
                timestamp: Date()
            )

            DispatchQueue.main.async {
                self.history.insert(newItem, at: 0)
                self.trimHistory()
            }
            return
        }
    }

    private func trimHistory() {
        let limit = max(5, maxItems)
        if history.count > limit {
            history = Array(history.prefix(limit))
        }
    }

    func copyToPasteboard(_ item: ClipboardItem) {
        pasteboard.clearContents()
        
        if item.isImage, let data = item.imageData, let image = NSImage(data: data) {
            // Write NSImage object AND raw PNG data so all macOS apps (Slack, Word, Photoshop, Preview, Finder, Notes) can paste it
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
    }
}
