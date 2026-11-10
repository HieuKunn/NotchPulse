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
    var isPinned: Bool = false
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
        case id, type, contentString, urlString, thumbnailData, diskFilePath, timestamp, imageData, isPinned
    }

    init(
        id: UUID = UUID(),
        type: ClipboardType = .text,
        contentString: String?,
        urlString: String? = nil,
        thumbnailData: Data? = nil,
        diskFilePath: String? = nil,
        isPinned: Bool = false,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.contentString = contentString
        self.urlString = urlString
        self.thumbnailData = thumbnailData
        self.diskFilePath = diskFilePath
        self.isPinned = isPinned
        self.timestamp = timestamp
    }

    // Compatibility initializer
    init(
        id: UUID = UUID(),
        type: ClipboardType = .text,
        contentString: String?,
        urlString: String? = nil,
        imageData: Data?,
        isPinned: Bool = false,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.contentString = contentString
        self.urlString = urlString
        self.thumbnailData = imageData
        self.diskFilePath = nil
        self.isPinned = isPinned
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
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
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
        try container.encode(isPinned, forKey: .isPinned)
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

    private let processingQueue = DispatchQueue(label: "com.notchpulse.clipboard.processing", qos: .userInitiated)
    private var pollTimer: Timer?
    private var isMonitoring = false
    private var lastPasteboardChangeAt = Date()
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
        if Thread.isMainThread {
            setupMonitoringOnMain()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.setupMonitoringOnMain()
            }
        }
    }

    func stopMonitoring() {
        if Thread.isMainThread {
            teardownMonitoringOnMain()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.teardownMonitoringOnMain()
            }
        }
    }

    private func teardownMonitoringOnMain() {
        isMonitoring = false
        pollTimer?.invalidate()
        pollTimer = nil
        if let monitor = copyKeyMonitor {
            NSEvent.removeMonitor(monitor)
            copyKeyMonitor = nil
        }
    }

    private func setupMonitoringOnMain() {
        teardownMonitoringOnMain()
        guard isEnabled else { return }
        isMonitoring = true
        lastPasteboardChangeAt = Date()

        // 1. Instant event-driven copy detector: Fires with multi-tick check on Cmd+C / Cmd+X / Screenshots
        if AXIsProcessTrusted() {
            copyKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                guard flags.contains(.command) else { return }

                let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
                let isCopyOrCut = event.keyCode == 8 || event.keyCode == 7 || chars == "c" || chars == "x"
                let isScreenshot = event.keyCode == 20 || event.keyCode == 21 || event.keyCode == 23 ||
                    chars == "3" || chars == "#" || chars == "4" || chars == "$" || chars == "5" || chars == "%"

                if isCopyOrCut {
                    // Staggered checks to capture fast AppKit apps, standard apps, and heavy Electron/browsers
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self?.checkForChanges() }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self?.checkForChanges() }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) { self?.checkForChanges() }
                } else if isScreenshot {
                    // System screen capture takes 150-600ms to encode and write to pasteboard
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self?.checkForChanges() }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { self?.checkForChanges() }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) { self?.checkForChanges() }
                }
            }
        }

        // Poll context menu and drag copies. Slow down after inactivity; the key
        // monitor above still checks common copy actions immediately.
        scheduleNextPoll()
        // Check immediately on startup
        self.checkForChanges()
    }

    private func scheduleNextPoll() {
        guard isMonitoring else { return }
        pollTimer?.invalidate()
        let interval: TimeInterval = Date().timeIntervalSince(lastPasteboardChangeAt) < 30 ? 1.5 : 3
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.checkForChanges()
            self.scheduleNextPoll()
        }
        timer.tolerance = interval * 0.25
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
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

    private static let sensitivePasteboardTypes: Set<String> = [
        "org.nspasteboard.ConcealedType",
        "org.nspasteboard.TransientType",
        "org.nspasteboard.AutoGeneratedType",
        "com.agilebits.onepassword"
    ]

    static func isSensitivePasteboard(_ types: [NSPasteboard.PasteboardType]?) -> Bool {
        guard let types else { return false }
        for t in types {
            if sensitivePasteboardTypes.contains(t.rawValue) {
                return true
            }
        }
        return false
    }

    private func checkForChanges() {
        guard isEnabled, isMonitoring else { return }
        let currentCount = pasteboard.changeCount
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount
        lastPasteboardChangeAt = Date()

        // Privacy safeguard: ignore passwords and concealed clips copied from password managers
        if Self.isSensitivePasteboard(pasteboard.types) {
            return
        }

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

                processingQueue.async { [weak self] in
                    guard let self = self else { return }
                    autoreleasepool {
                        // Generate crisp high-DPI thumbnail (128px) for Retina UI display
                        guard let thumbData = Self.generateThumbnailData(from: rawData, maxDimension: 128) else { return }

                        // Save 100% ORIGINAL unmodified raw image data to persistent storage
                        // NEVER downscale or compress rawData so pasteboard always recovers exact original pixels, resolution, and format.
                        let itemId = UUID()
                        let storageFile = Self.clipboardStorageDir.appendingPathComponent("\(itemId.uuidString).dat")
                        guard (try? rawData.write(to: storageFile, options: .atomic)) != nil else { return }

                        let item = ClipboardItem(
                            id: itemId,
                            type: .image,
                            contentString: nil,
                            urlString: associatedURL,
                            thumbnailData: thumbData,
                            diskFilePath: storageFile.path,
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
                   let thumbData = Self.generateThumbnailData(from: fileData, maxDimension: 128) {
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
        let (updated, evicted) = Self.processHistoryInsertion(
            currentHistory: self.history,
            newItem: item,
            unpinnedLimit: max(5, maxItems)
        )
        for path in evicted {
            Self.removeCachedImageFile(at: path)
        }
        self.history = updated
        self.saveHistory()
    }

    /// Pure production helper that calculates history after inserting an item, deduplicating matching content, preserving pinned status, and applying unpinned limit.
    static func processHistoryInsertion(
        currentHistory: [ClipboardItem],
        newItem: ClipboardItem,
        unpinnedLimit: Int
    ) -> (updatedHistory: [ClipboardItem], evictedImagePaths: [String]) {
        var evictedPaths: [String] = []
        var wasPinned = newItem.isPinned

        // 1. Remove duplicate items while checking if the prior item was pinned
        var filtered: [ClipboardItem] = []
        for existing in currentHistory {
            let isMatch: Bool = {
                if existing.id == newItem.id { return true }
                if let newContent = newItem.contentString, let existingContent = existing.contentString, !newContent.isEmpty {
                    return newContent == existingContent
                }
                if newItem.isImage && existing.isImage {
                    if let d1 = newItem.thumbnailData, let d2 = existing.thumbnailData, d1 == d2 {
                        return true
                    }
                    if let p1 = newItem.diskFilePath, let p2 = existing.diskFilePath, p1 == p2 {
                        return true
                    }
                }
                return false
            }()

            if isMatch {
                if existing.isPinned {
                    wasPinned = true
                }
                if let path = existing.diskFilePath, path != newItem.diskFilePath {
                    evictedPaths.append(path)
                }
            } else {
                filtered.append(existing)
            }
        }

        // 2. Insert item preserving pinned status
        var toInsert = newItem
        toInsert.isPinned = wasPinned

        var working = filtered
        if toInsert.isPinned {
            working.insert(toInsert, at: 0)
        } else {
            let firstUnpinnedIndex = working.firstIndex(where: { !$0.isPinned }) ?? working.count
            working.insert(toInsert, at: firstUnpinnedIndex)
        }

        // 3. Trim unpinned items beyond unpinnedLimit, preserving all pinned items
        let pinned = working.filter { $0.isPinned }
        let unpinned = working.filter { !$0.isPinned }
        let limit = max(1, unpinnedLimit)

        let trimmedUnpinned: [ClipboardItem]
        if unpinned.count > limit {
            let removed = unpinned.suffix(from: limit)
            for it in removed {
                if let p = it.diskFilePath {
                    evictedPaths.append(p)
                }
            }
            trimmedUnpinned = Array(unpinned.prefix(limit))
        } else {
            trimmedUnpinned = unpinned
        }

        return (pinned + trimmedUnpinned, evictedPaths)
    }

    /// Pure helper for filtering clipboard history by search query.
    /// Supports case-insensitive and diacritic-insensitive matching on text content, URLs, display text, and image file names.
    static func filterHistory(items: [ClipboardItem], query: String) -> [ClipboardItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items }
        let normalized = trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return items.filter { item in
            if let content = item.contentString {
                if content.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).contains(normalized) {
                    return true
                }
            }
            if let url = item.urlString {
                if url.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).contains(normalized) {
                    return true
                }
            }
            if item.displayString.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).contains(normalized) {
                return true
            }
            if let path = item.diskFilePath {
                let filename = (path as NSString).lastPathComponent
                if filename.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).contains(normalized) {
                    return true
                }
            }
            return false
        }
    }

    func togglePin(for item: ClipboardItem) {
        guard let index = history.firstIndex(where: { $0.id == item.id }) else { return }
        history[index].isPinned.toggle()
        reorderPinnedItems()
        saveHistory()
    }

    func deleteItem(_ item: ClipboardItem) {
        if let path = item.diskFilePath {
            Self.removeCachedImageFile(at: path)
        }
        history.removeAll { $0.id == item.id }
        saveHistory()
    }

    private func reorderPinnedItems() {
        let pinned = history.filter { $0.isPinned }
        let unpinned = history.filter { !$0.isPinned }
        history = pinned + unpinned
    }

    private func trimHistory() {
        let limit = max(5, maxItems)
        let pinned = history.filter { $0.isPinned }
        let unpinned = history.filter { !$0.isPinned }
        if unpinned.count > limit {
            let removed = unpinned.suffix(from: limit)
            for item in removed {
                if let path = item.diskFilePath {
                    Self.removeCachedImageFile(at: path)
                }
            }
            history = pinned + Array(unpinned.prefix(limit))
            saveHistory()
        }
    }

    private func saveHistory() {
        let limit = max(5, maxItems)
        let itemsToSave = Array(history.prefix(limit))
        if let data = try? JSONEncoder().encode(itemsToSave) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let items = try? JSONDecoder().decode([ClipboardItem].self, from: data) {
            // Sanitize history: ensure legacy items don't hoard large uncompressed images in thumbnailData
            var sanitized: [ClipboardItem] = []
            let limit = max(5, maxItems)
            for var item in items.prefix(limit) {
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

        if item.type == .image,
           let fileURL = item.urlString.flatMap(URL.init(string:)),
           fileURL.isFileURL,
           FileManager.default.fileExists(atPath: fileURL.path) {
            // Images copied as files in Finder must paste back as files, not as decoded pixels.
            pasteboard.writeObjects([fileURL as NSURL])
        } else if item.isImage {
            // Write exact original image representation to pasteboard with all native image types (PNG, TIFF, native format)
            autoreleasepool {
                let fullData: Data? = {
                    if let path = item.diskFilePath, FileManager.default.fileExists(atPath: path) {
                        return try? Data(contentsOf: URL(fileURLWithPath: path))
                    }
                    return item.thumbnailData
                }()

                guard let data = fullData, !data.isEmpty else { return }

                var declaredTypes: [NSPasteboard.PasteboardType] = []
                var rawPbType: NSPasteboard.PasteboardType? = nil

                if let source = CGImageSourceCreateWithData(data as CFData, nil),
                   let imageType = CGImageSourceGetType(source) {
                    let type = NSPasteboard.PasteboardType(imageType as String)
                    rawPbType = type
                    declaredTypes.append(type)
                }
                declaredTypes.append(.png)
                declaredTypes.append(NSPasteboard.PasteboardType("public.png"))
                declaredTypes.append(.tiff)

                pasteboard.declareTypes(declaredTypes, owner: nil)

                if let rawPbType = rawPbType {
                    pasteboard.setData(data, forType: rawPbType)
                }

                if let image = NSImage(data: data) {
                    if let tiff = image.tiffRepresentation {
                        pasteboard.setData(tiff, forType: .tiff)
                        if let rep = NSBitmapImageRep(data: tiff),
                           let png = rep.representation(using: .png, properties: [:]) {
                            pasteboard.setData(png, forType: .png)
                            pasteboard.setData(png, forType: NSPasteboard.PasteboardType("public.png"))
                        }
                    }
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
                Self.removeCachedImageFile(at: path)
            }
        }
        history.removeAll()
        UserDefaults.standard.removeObject(forKey: storageKey)

        // Wipe all files in persistent cache directory to guarantee zero disk waste
        if let files = try? FileManager.default.contentsOfDirectory(at: Self.clipboardStorageDir, includingPropertiesForKeys: nil) {
            for file in files {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    // MARK: - Persistent Storage & Zero-RAM-Spike Image Helpers

    /// Persistent storage directory in Application Support so user copied images are NEVER wiped by macOS reboot or /tmp cleansers.
    private static let clipboardStorageDir: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("NotchPulse/ClipboardImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Finder image entries point at the user's original file. Only files created in our persistent store are ours to delete.
    private static func removeCachedImageFile(at path: String) {
        let fileURL = URL(fileURLWithPath: path).standardizedFileURL
        guard (fileURL.deletingLastPathComponent() == clipboardStorageDir.standardizedFileURL ||
               fileURL.path.contains("NotchPulseClipboard")),
              fileURL.pathExtension == "dat",
              UUID(uuidString: fileURL.deletingPathExtension().lastPathComponent) != nil else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }

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
        let validPaths = Set(history.compactMap { $0.diskFilePath })
        DispatchQueue.global(qos: .background).async {
            // Clean persistent storage
            if let files = try? FileManager.default.contentsOfDirectory(at: Self.clipboardStorageDir, includingPropertiesForKeys: nil) {
                for file in files {
                    if !validPaths.contains(file.path) {
                        try? FileManager.default.removeItem(at: file)
                    }
                }
            }
            // Clean legacy /tmp folder if present
            let legacyTmp = FileManager.default.temporaryDirectory.appendingPathComponent("NotchPulseClipboard", isDirectory: true)
            if let legacyFiles = try? FileManager.default.contentsOfDirectory(at: legacyTmp, includingPropertiesForKeys: nil) {
                for file in legacyFiles {
                    if !validPaths.contains(file.path) {
                        try? FileManager.default.removeItem(at: file)
                    }
                }
            }
        }
    }
}
