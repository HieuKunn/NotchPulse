//
//  DragDetector.swift
//  NotchPulse
//
//  Created by Alexander on 2025-11-20.
//

import Cocoa
import Defaults
import UniformTypeIdentifiers

@MainActor
final class DragDetector {

    // MARK: - Callbacks

    typealias VoidCallback = () -> Void
    typealias PositionCallback = (_ globalPoint: CGPoint) -> Void

    var onDragEnded: VoidCallback?
    var onDragMove: PositionCallback?
    var onGlobalDragStateChanged: ((Bool) -> Void)?
    var onGlobalHoverStateChanged: ((Bool) -> Void)?
    var onShakeDetected: VoidCallback?

    private var pollTimer: Timer?
    private var mouseMonitor: Any?
    private var localMouseMonitor: Any?

    private static var globalLastConsumedPasteboardCount: Int = -1
    private var lastKnownIdlePasteboardCount: Int = -1
    private var mouseDownPasteboardCount: Int?
    private var dragStartLocation: CGPoint?
    private var isContentDragging: Bool = false {
        didSet {
            if isContentDragging != oldValue {
                onGlobalDragStateChanged?(isContentDragging)
            }
        }
    }
    private var isHoveringFromRadar: Bool = false

    private var unpressedTicks: Int = 0

    // MARK: - Shake Detection State
    private struct MouseSample {
        let x: CGFloat
        let y: CGFloat
        let time: TimeInterval
    }
    private var recentSamples: [MouseSample] = []
    private var lastShakeTriggerTime: TimeInterval = 0

    private let regionProvider: () -> CGRect
    private let screenFrameProvider: (() -> CGRect?)?
    private let dragPasteboard = NSPasteboard(name: .drag)

    init(regionProvider: @escaping () -> CGRect, screenFrameProvider: (() -> CGRect?)? = nil) {
        self.regionProvider = regionProvider
        self.screenFrameProvider = screenFrameProvider
        if Self.globalLastConsumedPasteboardCount < 0 {
            Self.globalLastConsumedPasteboardCount = dragPasteboard.changeCount
        }
    }

    // MARK: - Private Helpers

    /// Checks if the physical left mouse or trackpad button is currently held down
    private var isLeftButtonPressed: Bool {
        return (NSEvent.pressedMouseButtons & 1) != 0 ||
               CGEventSource.buttonState(.combinedSessionState, button: .left) ||
               CGEventSource.buttonState(.hidSystemState, button: .left)
    }

    /// Determines if a drag-and-drop session is active and fresh (not stale leftover pasteboard content from an earlier operation).
    private func isPasteboardSessionActive() -> Bool {
        let currentPbCount = dragPasteboard.changeCount
        let isFresh = (Self.globalLastConsumedPasteboardCount < 0) ||
                      (currentPbCount != Self.globalLastConsumedPasteboardCount) ||
                      (mouseDownPasteboardCount != nil && currentPbCount != mouseDownPasteboardCount)
        return isFresh
    }

    /// Checks if the drag pasteboard contains actual file, folder, image, or droppable items (strictly excluding tabs and app windows).
    private func hasValidDragContent() -> Bool {
        guard let types = dragPasteboard.types, !types.isEmpty else {
            return false
        }

        // 1. Blacklist browser tabs, window dragging, and app UI elements
        let tabAndWindowKeywords = [
            "window-drag",
            "windowdrag",
            ".tab",
            "tab-drag"
        ]
        let tabAndWindowTypes: Set<String> = [
            "org.chromium.drag-type.tab",
            "com.google.chrome.tab",
            "company.thebrowser.arc.tab",
            "com.apple.safari.tab",
            "com.apple.safari.tab-drag",
            "application/x-moz-tabbrowser-tab",
            "com.apple.tab-drag",
            "com.apple.window-drag",
            "com.apple.nswindow.drag",
            "com.apple.dock.windowdrag"
        ]
        for type in types {
            let raw = type.rawValue.lowercased()
            if tabAndWindowTypes.contains(raw) || tabAndWindowKeywords.contains(where: { raw.contains($0) }) {
                return false
            }
        }

        // 2. High-priority check: Can the pasteboard provide actual file:// URLs?
        if dragPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) {
            return true
        }
        if dragPasteboard.canReadObject(forClasses: [NSURL.self], options: nil) {
            return true
        }

        // 3. File promise receivers (used by Dock stacks, Mail attachments, and Photos exports)
        let promiseTypes: Set<String> = Set(NSFilePromiseReceiver.readableDraggedTypes.map { String($0) }).union([
            "com.apple.NSFilePromiseItemMetaData",
            "dyn.ah62d4rv4gu8yc6durvwwa3xmrvw1gkdusm1044pxqyuha2pxsvw0e55bsmwca7d3sbwu",
            "com.apple.pasteboard.promised-file-content-type",
            "com.apple.pasteboard.promised-file-url",
            "Apple promised file pasteboard type"
        ])
        if types.contains(where: { promiseTypes.contains($0.rawValue) }) {
            return true
        }
        if dragPasteboard.canReadObject(forClasses: [NSFilePromiseReceiver.self], options: nil) {
            return true
        }

        // 4. Exact recognized types for files, folders, and Dock stacks
        let recognizedTypes: Set<String> = [
            NSPasteboard.PasteboardType.fileURL.rawValue,   // file://… URLs ("public.file-url")
            "public.file-url",
            "com.apple.finder.node",                       // Finder items (files, folders)
            "com.apple.cocoa.pasteboard.findernode",
            "NSFilenamesPboardType",                       // legacy Finder drag and Dock stacks
            "com.apple.dock.item",                         // macOS Dock stack items (Downloads, etc.)
            "com.apple.dock.drag-item",
            "com.apple.dock.stack",
            "com.apple.mac.install-source-container",      // .pkg, .dmg installer drags
            "public.folder",
            "public.directory",
            "public.item",
            "public.data",
            "public.content",
            "public.image",                                // Any image dragged from browser/photos
            "public.png",
            "public.jpeg",
            "public.tiff"
        ]

        for type in types {
            let raw = type.rawValue
            if recognizedTypes.contains(raw) { return true }
            let lower = raw.lowercased()
            if lower.contains("file") || lower.contains("finder") || lower.contains("dock") || lower.contains("image") {
                return true
            }
        }

        // 5. UTType conformance check
        for type in types {
            if let ut = UTType(type.rawValue) {
                if ut.conforms(to: .fileURL) || ut.conforms(to: .folder) || ut.conforms(to: .directory) || ut.conforms(to: .image) || ut.conforms(to: .archive) {
                    return true
                }
            }
        }

        // 6. Pasteboard items inspection
        if let items = dragPasteboard.pasteboardItems {
            for item in items {
                if item.string(forType: .fileURL) != nil {
                    return true
                }
                if item.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) != nil {
                    return true
                }
                if item.types.contains(where: {
                    let r = $0.rawValue.lowercased()
                    return r.contains("file") || r.contains("dock") || r.contains("finder")
                }) {
                    return true
                }
            }
        }
        // If we reached here, it's not explicitly blacklisted as a tab/window.
        // It could be a custom app drag (like Docker) or an unknown format.
        // Since the user performed a deliberate shake, and it has some valid drag types, allow it.
        return true
    }

    func startMonitoring() {
        stopMonitoring()
        lastKnownIdlePasteboardCount = dragPasteboard.changeCount
        mouseDownPasteboardCount = nil
        dragStartLocation = nil
        recentSamples.removeAll()

        // Global monitor for leftMouseDragged (for real-time response to drag and shake gestures across other apps/Finder)
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] _ in
            Task { @MainActor in
                self?.checkState()
            }
        }

        // Local monitor for leftMouseDragged (for events when mouse is within app windows)
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] event in
            Task { @MainActor in
                self?.checkState()
            }
            return event
        }

        // Polling timer running in .common mode so it continues firing at ~40Hz during active drag
        let timer = Timer(timeInterval: 0.025, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkState()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func checkShakeGesture(currentPoint: CGPoint, currentTime: TimeInterval) {
        // Rule: Shake must ONLY trigger on the display where the cursor actually is (in multi-display mode)!
        if let screenFrame = screenFrameProvider?() {
            guard screenFrame.insetBy(dx: -20, dy: -20).contains(currentPoint) else { return }
        }

        // Debounce: don't trigger again within 0.8s of last shake
        guard currentTime - lastShakeTriggerTime > 0.8 else { return }

        recentSamples.append(MouseSample(x: currentPoint.x, y: currentPoint.y, time: currentTime))

        // Keep samples from the last 0.75s (fast intentional shake only, prevents casual left-right browsing from triggering)
        let cutoff = currentTime - 0.75
        recentSamples.removeAll { $0.time < cutoff }

        guard recentSamples.count >= 5 else { return }

        // Require at least 16pt per swing to rule out slight jitter or minor curves
        let xs = recentSamples.map { $0.x }
        let minSwing: CGFloat = 16.0

        let revX = countAxisReversals(values: xs, minSwing: minSwing)

        // Require at least 3 horizontal direction reversals (4 fast continuous strokes: L⇄R⇄L⇄R)
        guard revX >= 3 else { return }

        // Velocity & duration check:
        // Ensure the reversals happened rapidly enough (minimum horizontal speed)
        guard let firstSample = recentSamples.first else { return }
        let elapsed = currentTime - firstSample.time
        guard elapsed >= 0.18 && elapsed <= 0.75 else { return }

        var totalXTravel: CGFloat = 0
        for i in 1..<recentSamples.count {
            totalXTravel += abs(recentSamples[i].x - recentSamples[i-1].x)
        }
        let horizontalSpeed = totalXTravel / CGFloat(elapsed)
        // User must shake at a brisk speed (>= 180 pt/s) to distinguish from casual mouse movement
        guard horizontalSpeed >= 180.0 else { return }

        // Check if this is an actual file/folder/droppable item drag!
        // Reject window dragging, browser tabs, text selection, and stale pasteboards.
        guard isPasteboardSessionActive() && hasValidDragContent() else {
            // Not a valid file/folder drag! Clear samples so it doesn't fire for non-files.
            recentSamples.removeAll()
            return
        }

        lastShakeTriggerTime = currentTime
        recentSamples.removeAll()
        isContentDragging = true

        // Disengage hover radar so radar doesn't fight shelf open
        if isHoveringFromRadar {
            isHoveringFromRadar = false
            onGlobalHoverStateChanged?(false)
        }

        onShakeDetected?()
    }

    private func countAxisReversals(values: [CGFloat], minSwing: CGFloat) -> Int {
        guard values.count >= 3 else { return 0 }
        var reversals = 0
        var currentDirection = 0 // -1 for decreasing, +1 for increasing
        var lastExtremum = values[0]

        for val in values {
            let delta = val - lastExtremum
            if currentDirection == 0 {
                if abs(delta) >= minSwing {
                    currentDirection = delta > 0 ? 1 : -1
                    lastExtremum = val
                }
            } else if currentDirection == 1 { // Was moving positive
                if delta < -minSwing { // Reversed
                    reversals += 1
                    currentDirection = -1
                    lastExtremum = val
                } else if val > lastExtremum {
                    lastExtremum = val
                }
            } else if currentDirection == -1 { // Was moving negative
                if delta > minSwing { // Reversed
                    reversals += 1
                    currentDirection = 1
                    lastExtremum = val
                } else if val < lastExtremum {
                    lastExtremum = val
                }
            }
        }
        return reversals
    }

    private func checkState() {
        let mousePressed = isLeftButtonPressed
        let currentPbCount = dragPasteboard.changeCount

        if !mousePressed {
            unpressedTicks += 1
            // If dragging, allow a ~75ms grace period (3 ticks @ 25ms) to bridge momentary event drops across screen borders
            if isContentDragging && unpressedTicks < 3 {
                return
            }

            recentSamples.removeAll()
            dragStartLocation = nil
            mouseDownPasteboardCount = nil

            // Reset when mouse button is confirmed released.
            if isContentDragging {
                isContentDragging = false
                // Mark this pasteboard session as consumed so old content on drag pasteboard doesn't trigger on text select
                Self.globalLastConsumedPasteboardCount = currentPbCount
                onDragEnded?()
            }

            // Hover radar: Runs whenever open-on-hover or extended hover area is enabled
            let shouldRunHoverRadar = Defaults[.openNotchOnHover] || Defaults[.extendHoverArea]
            if shouldRunHoverRadar {
                let mouseLocation = NSEvent.mouseLocation
                let hoverRegion = regionProvider()
                let containsMouseHover = hoverRegion.contains(mouseLocation)

                if containsMouseHover && !isHoveringFromRadar {
                    isHoveringFromRadar = true
                    onGlobalHoverStateChanged?(true)
                } else if !containsMouseHover && isHoveringFromRadar {
                    isHoveringFromRadar = false
                    onGlobalHoverStateChanged?(false)
                }
            } else if isHoveringFromRadar {
                isHoveringFromRadar = false
                onGlobalHoverStateChanged?(false)
            }
            return
        }

        // --- Mouse IS Pressed ---
        unpressedTicks = 0
        let mouseLocation = NSEvent.mouseLocation
        let now = ProcessInfo.processInfo.systemUptime

        if dragStartLocation == nil {
            dragStartLocation = mouseLocation
            mouseDownPasteboardCount = currentPbCount
        }

        let dragDistance: CGFloat
        if let start = dragStartLocation {
            dragDistance = hypot(mouseLocation.x - start.x, mouseLocation.y - start.y)
        } else {
            dragDistance = 0
        }

        // 6 points is sufficient to distinguish an intentional drag from a static click
        let hasMovedSufficiently = dragDistance >= 6.0

        if hasMovedSufficiently {
            // Continuously collect shake samples while mouse is dragged!
            // When 4 strokes are detected, checkShakeGesture verifies whether this is an active file/folder drag.
            checkShakeGesture(currentPoint: mouseLocation, currentTime: now)
        }

        let isActivelyDraggingPayload = isPasteboardSessionActive() && hasValidDragContent() && hasMovedSufficiently

        if isContentDragging || isActivelyDraggingPayload {
            isContentDragging = true
            onDragMove?(mouseLocation)

            // While actively dragging files, disengage hover radar
            if isHoveringFromRadar {
                isHoveringFromRadar = false
                onGlobalHoverStateChanged?(false)
            }
        } else {
            // Mouse is pressed down (e.g. moving an app window, selecting text, or regular click):
            // NEVER trigger a new hover radar open while mouse button is held!
            // Only maintain hover radar if it was already active before mouse-down.
            if isHoveringFromRadar {
                let hoverRegion = regionProvider()
                let containsMouseHover = hoverRegion.contains(mouseLocation)
                if !containsMouseHover {
                    isHoveringFromRadar = false
                    onGlobalHoverStateChanged?(false)
                }
            }
        }
    }

    func stopMonitoring() {
        pollTimer?.invalidate()
        pollTimer = nil
        isHoveringFromRadar = false

        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
        }
        mouseMonitor = nil
        if let localMonitor = localMouseMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        localMouseMonitor = nil
        isContentDragging = false
        unpressedTicks = 0
        recentSamples.removeAll()
        dragStartLocation = nil
        mouseDownPasteboardCount = nil
        Self.globalLastConsumedPasteboardCount = dragPasteboard.changeCount
    }

    deinit {
        pollTimer?.invalidate()
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let localMonitor = localMouseMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
    }
}

