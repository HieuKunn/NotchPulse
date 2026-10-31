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
    private var cachedHasAutoOpenContent: Bool = false
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

    /// Types that are strong evidence of a transferable object. Text, HTML and
    /// RTF are intentionally excluded: selecting text also emits mouse-drag
    /// events and must never auto-open Shelf.
    private static let autoOpenIdentifiers: Set<String> = [
        NSPasteboard.PasteboardType.fileURL.rawValue,
        "NSFilenamesPboardType",
        "Apple URL pasteboard type",
        "com.apple.pasteboard.promised-file-url",
        "com.apple.NSFilePromiseItemMetaData",
        "com.apple.pasteboard.promised-file-content-type",
        "Apple promised file pasteboard type",
        "Apple files promise pasteboard type",
        "com.apple.finder.node",
        UTType.url.identifier,
        UTType.fileURL.identifier,
        UTType.image.identifier,
        UTType.png.identifier,
        UTType.jpeg.identifier,
        UTType.tiff.identifier
    ]

    init(regionProvider: @escaping () -> CGRect) {
        self.regionProvider = regionProvider
        self.lastKnownIdleCount = dragPasteboard.changeCount
    }

    // MARK: - Private Helpers
    
    /// Checks whether this drag is safe to use for automatic Shelf activation.
    /// Shelf's own drop destinations still accept plain text once already open.
    private func hasAutoOpenDragContent(forceRefresh: Bool = false) -> Bool {
        let currentCount = dragPasteboard.changeCount
        if !forceRefresh && currentCount == lastCheckedDragCount {
            return cachedHasAutoOpenContent
        }
        lastCheckedDragCount = currentCount

        guard let types = dragPasteboard.types, !types.isEmpty else {
            cachedHasAutoOpenContent = false
            return false
        }
        
        for type in types {
            if Self.autoOpenIdentifiers.contains(type.rawValue) {
                cachedHasAutoOpenContent = true
                return true
            }
            if let utType = UTType(type.rawValue),
               (utType.conforms(to: .fileURL) ||
                utType.conforms(to: .url) ||
                utType.conforms(to: .image)) {
                cachedHasAutoOpenContent = true
                return true
            }
        }
        cachedHasAutoOpenContent = false
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
        cachedHasAutoOpenContent = false
        cachedRegion = .zero
    }

    private func handleMouseDragged() {
        let currentCount = dragPasteboard.changeCount
        let mouseLocation = NSEvent.mouseLocation
        let activeRegion = getActiveRegion()

        // A payload must be fresh for this mouse session. Reading a valid-looking
        // type merely because the pointer is near the notch reuses stale drag
        // pasteboard data and turns text selection into a false file drag.
        let isNewDragOperation: Bool
        if mouseDownPasteboardCount != -1 {
            // Prefer the baseline from this exact press. An older pasteboard
            // change must not leak into a new text-selection gesture.
            isNewDragOperation = currentCount != mouseDownPasteboardCount
        } else {
            // Covers the rare case where monitoring starts after the press but
            // while an external file drag is already in progress.
            isNewDragOperation = currentCount != lastKnownIdleCount
        }
        let isNearNotch = mouseLocation.y >= (activeRegion.minY - 120)
        guard isContentDragging || isNewDragOperation else { return }
        let hasCurrentPayload = hasAutoOpenDragContent(forceRefresh: !isContentDragging)
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
        cachedHasAutoOpenContent = false
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
        cachedHasAutoOpenContent = false
    }

    deinit {
        stopMonitoring()
    }
}
