import Cocoa
import UniformTypeIdentifiers

final class DragDetector {

    // MARK: - Callbacks

    typealias VoidCallback = () -> Void
    typealias PositionCallback = (_ globalPoint: CGPoint) -> Void

    var onDragEntersNotchRegion: VoidCallback?
    var onDragExitsNotchRegion: VoidCallback?
    var onDragEnded: VoidCallback?
    var onDragMove: PositionCallback?

    private var mouseDownMonitor: Any?
    private var mouseDraggedMonitor: Any?
    private var mouseUpMonitor: Any?
    private var localMouseDownMonitor: Any?
    private var localMouseDraggedMonitor: Any?
    private var localMouseUpMonitor: Any?

    private var mouseDownPasteboardCount: Int = -1
    private var lastKnownIdleCount: Int = -1
    private var isContentDragging: Bool = false
    private var hasEnteredNotchRegion: Bool = false
    private var lastCheckedDragCount: Int = -1
    private var cachedHasValidContent: Bool = false
    private var cachedRegion: CGRect = .zero
    private var lastRegionFetchTime: TimeInterval = 0

    private let regionProvider: () -> CGRect
    private let dragPasteboard = NSPasteboard(name: .drag)

    private func getActiveRegion() -> CGRect {
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastRegionFetchTime > 0.25 || cachedRegion.isEmpty {
            cachedRegion = regionProvider()
            lastRegionFetchTime = now
        }
        return cachedRegion
    }

    private static let validIdentifiers: Set<String> = [
        NSPasteboard.PasteboardType.fileURL.rawValue,
        "NSFilenamesPboardType",
        "Apple URL pasteboard type",
        "com.apple.pasteboard.promised-file-url",
        "com.apple.NSFilePromiseItemMetaData",
        "com.apple.pasteboard.promised-file-content-type",
        "Apple promised file pasteboard type",
        "com.apple.finder.node",
        UTType.url.identifier,
        UTType.fileURL.identifier,
        UTType.utf8PlainText.identifier,
        UTType.plainText.identifier,
        UTType.text.identifier,
        UTType.image.identifier,
        UTType.png.identifier,
        UTType.jpeg.identifier,
        UTType.tiff.identifier,
        NSPasteboard.PasteboardType.string.rawValue,
        NSPasteboard.PasteboardType.html.rawValue,
        NSPasteboard.PasteboardType.rtf.rawValue,
        "NSStringPboardType"
    ]

    init(regionProvider: @escaping () -> CGRect) {
        self.regionProvider = regionProvider
        self.lastKnownIdleCount = dragPasteboard.changeCount
    }

    // MARK: - Private Helpers
    
    /// Checks if the drag pasteboard contains valid content types that can be dropped on the shelf
    private func hasValidDragContent(forceRefresh: Bool = false) -> Bool {
        let currentCount = dragPasteboard.changeCount
        if !forceRefresh && currentCount == lastCheckedDragCount {
            return cachedHasValidContent
        }
        lastCheckedDragCount = currentCount

        guard let types = dragPasteboard.types, !types.isEmpty else {
            cachedHasValidContent = false
            return false
        }
        
        for type in types {
            if Self.validIdentifiers.contains(type.rawValue) {
                cachedHasValidContent = true
                return true
            }
            if let utType = UTType(type.rawValue),
               (utType.conforms(to: .fileURL) ||
                utType.conforms(to: .url) ||
                utType.conforms(to: .text) ||
                utType.conforms(to: .image)) {
                cachedHasValidContent = true
                return true
            }
        }
        cachedHasValidContent = false
        return false
    }

    func startMonitoring() {
        stopMonitoring()
        lastKnownIdleCount = dragPasteboard.changeCount

        mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            self?.beginPotentialDrag()
        }
        localMouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            self?.beginPotentialDrag()
            return event
        }

        // Track drag movement and notch region intersection
        mouseDraggedMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in
            self?.handleMouseDragged()
        }
        localMouseDraggedMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDragged) { [weak self] event in
            self?.handleMouseDragged()
            return event
        }

        mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            self?.finishDrag()
        }
        // A global monitor does not receive mouse-up events delivered to our own
        // window. Catch the local release so dropping onto Shelf always ends the
        // detector session and clears preventNotchClose.
        localMouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            self?.finishDrag()
            return event
        }
    }

    private func beginPotentialDrag() {
        mouseDownPasteboardCount = dragPasteboard.changeCount
        isContentDragging = false
        hasEnteredNotchRegion = false
        lastCheckedDragCount = -1
        cachedHasValidContent = false
        cachedRegion = .zero
    }

    private func handleMouseDragged() {
        let currentCount = dragPasteboard.changeCount
        let mouseLocation = NSEvent.mouseLocation
        let activeRegion = getActiveRegion()

        // `changeCount` is the fast path. The proximity payload check is a
        // fallback for Finder/apps that populate the drag pasteboard before our
        // mouse-down monitor runs, leaving the count unchanged for the session.
        let isNewDragOperation = (mouseDownPasteboardCount != -1 && currentCount != mouseDownPasteboardCount) ||
                                 currentCount != lastKnownIdleCount
        let isNearNotch = mouseLocation.y >= (activeRegion.minY - 120)
        guard isContentDragging || isNewDragOperation || isNearNotch else { return }
        let hasCurrentPayload = hasValidDragContent(forceRefresh: !isContentDragging)
        if !isContentDragging {
            guard hasCurrentPayload else { return }
            isContentDragging = true
        }

        if !hasEnteredNotchRegion && !isNearNotch { return }
        onDragMove?(mouseLocation)

        let containsMouse = activeRegion.contains(mouseLocation)
        if containsMouse && !hasEnteredNotchRegion {
            hasEnteredNotchRegion = true
            cachedRegion = .zero
            onDragEntersNotchRegion?()
        } else if !containsMouse && hasEnteredNotchRegion {
            hasEnteredNotchRegion = false
            cachedRegion = .zero
            onDragExitsNotchRegion?()
        }
    }

    private func finishDrag() {
        let wasDragging = isContentDragging || hasEnteredNotchRegion
        let wasInRegion = hasEnteredNotchRegion
        lastKnownIdleCount = dragPasteboard.changeCount
        mouseDownPasteboardCount = -1
        cachedRegion = .zero
        lastRegionFetchTime = 0
        lastCheckedDragCount = -1
        cachedHasValidContent = false
        hasEnteredNotchRegion = false
        isContentDragging = false
        if wasInRegion {
            onDragExitsNotchRegion?()
        }
        if wasDragging {
            onDragEnded?()
        }
    }

    func stopMonitoring() {
        [mouseDownMonitor, mouseDraggedMonitor, mouseUpMonitor, localMouseDownMonitor, localMouseDraggedMonitor, localMouseUpMonitor].forEach { monitor in
            if let monitor = monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
        mouseDownMonitor = nil
        mouseDraggedMonitor = nil
        mouseUpMonitor = nil
        localMouseDownMonitor = nil
        localMouseDraggedMonitor = nil
        localMouseUpMonitor = nil
        isContentDragging = false
        hasEnteredNotchRegion = false
        mouseDownPasteboardCount = -1
        lastCheckedDragCount = -1
        cachedHasValidContent = false
    }

    deinit {
        stopMonitoring()
    }
}
