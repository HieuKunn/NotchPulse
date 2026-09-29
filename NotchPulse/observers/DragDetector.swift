//
//  DragDetector.swift
//  NotchPulse
//
//  Created by Alexander on 2025-11-20.
//
//  Hybrid event-driven rewrite (CPU fix):
//  - The always-on 25ms polling timer (40Hz, ran for the app's whole lifetime,
//    reading the drag pasteboard via IPC on every tick) is GONE. idle CPU is
//    effectively zero; work only happens on real mouse events.
//  - While the left button is HELD, a short 25ms poll bridges event drops for
//    shake detection and drag-payload tracking (matches baseline behavior of
//    reacting to real drag events).
//  - The hover radar is event-driven: no polling while idle. It only runs when
//    openNotchOnHover && extendHoverArea are BOTH enabled; stopping the monitor
//    always emits `false` so vm.isHoveringFromRadar can never get stuck.
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
    /// Fired when a REAL file/folder/image drag (including Dock-stack promises) enters the
    /// notch proximity region — the deterministic "hover a file at the notch to open the
    /// shelf" path, independent of the shake gesture.
    var onFileDragNearNotch: VoidCallback?

    private var pollTimer: Timer?
    private var mouseDownMonitor: Any?
    private var localMouseMonitor: Any?
    private var mouseDraggedMonitor: Any?
    private var mouseUpMonitor: Any?
    private var mouseMovedMonitor: Any?

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

    /// Shelf-proximity state while a real file drag is in flight.
    private var isShelfProximityActive: Bool = false

    /// Memoization: validity is stable for the lifetime of one drag session
    /// (the drag pasteboard's changeCount doesn't change mid-drag), so the
    /// pasteboard IPC is paid once per drag instead of on every drag event.
    private var cachedValidityChangeCount: Int = -1
    private var cachedValidityResult: Bool = false

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

    /// Determines if a drag-and-drop session is active with available payload types.
    private func isPasteboardSessionActive() -> Bool {
        guard let types = dragPasteboard.types, !types.isEmpty else { return false }
        return true
    }

    /// Checks if the drag pasteboard contains actual file, folder, image, or droppable items.
    /// Strictly excludes tabs, window drags, text selections, and links — anything that is
    /// not recognizably a droppable payload returns FALSE (no catch-all). Memoized per
    /// drag session so drag events don't hammer the pasteboard server with IPC.
    private func hasValidDragContent() -> Bool {
        let changeCount = dragPasteboard.changeCount
        if cachedValidityChangeCount == changeCount {
            return cachedValidityResult
        }
        let result = evaluateDragContentValidity()
        cachedValidityChangeCount = changeCount
        cachedValidityResult = result
        return result
    }

    private func evaluateDragContentValidity() -> Bool {
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
        // (web links / generic URLs intentionally do NOT count — only file URLs)
        if dragPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) {
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
            "public.image",                                // Any image dragged from browser/photos
            "public.png",
            "public.jpeg",
            "public.tiff"
        ]
        // NOTE: broad base types (public.data / public.item / public.content) and substring
        // matching were REMOVED — they made every custom drag (text, links, window moves)
        // look like a file drag and spuriously opened the shelf.

        for type in types {
            if recognizedTypes.contains(type.rawValue) { return true }
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
            }
        }
        // Strictly fail closed: unknown/custom formats (text selections, links, window
        // moves, app-specific drags) are NOT treated as file drags. The shake gesture
        // and shelf proximity must only react to real droppable payloads.
        return false
    }

    // MARK: - Lifecycle

    func startMonitoring() {
        stopMonitoring()
        lastKnownIdlePasteboardCount = dragPasteboard.changeCount
        mouseDownPasteboardCount = nil
        dragStartLocation = nil
        recentSamples.removeAll()

        // Press: begin potential drag/shake tracking and seed the hover radar state.
        mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.handleMousePress()
            }
        }

        // Local monitor so presses inside the app's own windows still seed state
        // (global monitors don't fire for events consumed by our own app).
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            Task { @MainActor in
                self?.handleMousePress()
            }
            return event
        }

        // Drag: real-time response to dragging and shake gestures across other apps/Finder.
        mouseDraggedMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] _ in
            Task { @MainActor in
                self?.handleMouseDrag()
            }
        }

        // Release: finalize drag state and refresh the radar with a single check.
        mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            Task { @MainActor in
                self?.handleMouseRelease()
            }
        }

        // Hover radar (only when both hover settings are enabled): react to pure mouse
        // MOVEMENT without any button pressed. No polling — events drive everything.
        if shouldRunHoverRadar {
            mouseMovedMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
                Task { @MainActor in
                    self?.checkHoverRadar()
                }
            }
        }
    }

    /// While the button is held, a short poll bridges momentary event drops across
    /// screen borders and keeps shake sampling alive even when dragged events are
    /// coalesced. Created on press, invalidated on release — never runs while idle.
    private func startPressPolling() {
        guard pollTimer == nil else { return }
        let timer = Timer(timeInterval: 0.025, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.handleHeldTick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func stopPressPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func stopMonitoring() {
        stopPressPolling()

        if let monitor = mouseDownMonitor {
            NSEvent.removeMonitor(monitor)
        }
        mouseDownMonitor = nil
        if let monitor = localMouseMonitor {
            NSEvent.removeMonitor(monitor)
        }
        localMouseMonitor = nil
        if let monitor = mouseDraggedMonitor {
            NSEvent.removeMonitor(monitor)
        }
        mouseDraggedMonitor = nil
        if let monitor = mouseUpMonitor {
            NSEvent.removeMonitor(monitor)
        }
        mouseUpMonitor = nil
        if let monitor = mouseMovedMonitor {
            NSEvent.removeMonitor(monitor)
        }
        mouseMovedMonitor = nil

        // CRITICAL: always publish `false` so vm.isHoveringFromRadar never gets stuck
        // true after settings changes tore down this detector.
        setHoveringFromRadar(false)

        isContentDragging = false
        isShelfProximityActive = false
        cachedValidityChangeCount = -1
        cachedValidityResult = false
        unpressedTicks = 0
        recentSamples.removeAll()
        dragStartLocation = nil
        mouseDownPasteboardCount = nil
        Self.globalLastConsumedPasteboardCount = dragPasteboard.changeCount
    }

    deinit {
        // Detached cleanup only — NSEvent monitors must be removed on the main thread.
        let pollTimer = self.pollTimer
        let monitors = [mouseDownMonitor, localMouseMonitor, mouseDraggedMonitor, mouseUpMonitor, mouseMovedMonitor]
        Task { @MainActor in
            pollTimer?.invalidate()
            for monitor in monitors {
                if let monitor {
                    NSEvent.removeMonitor(monitor)
                }
            }
        }
    }

    // MARK: - Event Handlers

    private func handleMousePress() {
        unpressedTicks = 0
        dragStartLocation = NSEvent.mouseLocation
        mouseDownPasteboardCount = dragPasteboard.changeCount
        recentSamples.removeAll()
        startPressPolling()
        // A press over the region with radar active keeps the hover state; the radar
        // region check below re-validates on movement while held.
        if shouldRunHoverRadar {
            checkHoverRadar()
        }
    }

    private func handleMouseDrag() {
        // Mouse is pressed — feed shake sampling and drag tracking.
        handleHeldTick()
    }

    private func handleMouseRelease() {
        stopPressPolling()
        if isContentDragging {
            isContentDragging = false
            Self.globalLastConsumedPasteboardCount = dragPasteboard.changeCount
            onDragEnded?()
        }
        isShelfProximityActive = false
        recentSamples.removeAll()
        dragStartLocation = nil
        mouseDownPasteboardCount = nil
        unpressedTicks = 0
        // Re-evaluate the radar once on release so hover state matches reality.
        if shouldRunHoverRadar {
            checkHoverRadar()
        }
    }

    /// One unit of held-button work (25ms poll tick or a dragged event).
    private func handleHeldTick() {
        guard isLeftButtonPressed else {
            // Grace: up to 3 ticks (~75ms) to bridge momentary event drops.
            unpressedTicks += 1
            if unpressedTicks >= 3 {
                handleMouseRelease()
            }
            return
        }
        unpressedTicks = 0

        let mouseLocation = NSEvent.mouseLocation
        let now = ProcessInfo.processInfo.systemUptime

        if dragStartLocation == nil {
            dragStartLocation = mouseLocation
            mouseDownPasteboardCount = dragPasteboard.changeCount
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
            checkShakeGesture(currentPoint: mouseLocation, currentTime: now)
        }

        // A payload drag only counts when a NEW drag session started AFTER mouse-down.
        // Stale types left on the drag pasteboard by the previous session otherwise make
        // window moves / text selections look like file drags ("dragging anything opens
        // the shelf" bug).
        let isFreshDragSession: Bool = {
            guard let downCount = mouseDownPasteboardCount else { return false }
            return dragPasteboard.changeCount != downCount
        }()

        let isActivelyDraggingPayload = isFreshDragSession && isPasteboardSessionActive() && hasValidDragContent() && hasMovedSufficiently

        if isContentDragging || isActivelyDraggingPayload {
            isContentDragging = true
            onDragMove?(mouseLocation)

            // While actively dragging files, disengage hover radar
            setHoveringFromRadar(false)

            // Deterministic shelf open: real file drag + cursor near the notch.
            checkShelfProximity(at: mouseLocation)
        } else if shouldRunHoverRadar, isHoveringFromRadar {
            // Mouse pressed but not dragging payload: only maintain radar hover while
            // the cursor stays inside the region — never trigger a NEW hover while held.
            let hoverRegion = regionProvider()
            if !hoverRegion.contains(mouseLocation) {
                setHoveringFromRadar(false)
            }
        }
    }

    // MARK: - Hover Radar

    private var shouldRunHoverRadar: Bool {
        Defaults[.openNotchOnHover] && Defaults[.extendHoverArea]
    }

    private func setHoveringFromRadar(_ hovering: Bool) {
        guard isHoveringFromRadar != hovering else { return }
        isHoveringFromRadar = hovering
        onGlobalHoverStateChanged?(hovering)
    }

    /// Event-driven radar evaluation: reads the cursor once and reconciles state.
    private func checkHoverRadar() {
        guard shouldRunHoverRadar else {
            setHoveringFromRadar(false)
            return
        }
        // While a drag payload is active, the radar must not fight the shelf open.
        guard !isContentDragging, !isLeftButtonPressed else {
            if isHoveringFromRadar {
                setHoveringFromRadar(false)
            }
            return
        }

        let mouseLocation = NSEvent.mouseLocation
        let hoverRegion = regionProvider()
        setHoveringFromRadar(hoverRegion.contains(mouseLocation))
    }

    // MARK: - Shelf Proximity

    /// While a real file drag is in flight, entering the notch's proximity region opens
    /// the shelf WITHOUT the shake gesture. Covers Dock-stack drags (e.g. pulling a
    /// download out of the Dock) which never pass over SwiftUI drop targets while the
    /// notch is closed. Idempotent per drag session.
    private func checkShelfProximity(at point: CGPoint) {
        guard onFileDragNearNotch != nil, Defaults[.notchPulseShelf] else { return }
        guard hasValidDragContent() else { return }
        let baseRegion = regionProvider()
        // Zero region (notch hidden in fullscreen) must stay empty — inset would turn it
        // into a real 120x60 rect at the screen origin and open the shelf spuriously.
        guard baseRegion.width > 0, baseRegion.height > 0 else { return }
        let padX = CGFloat(Defaults[.shelfDragOpenPadding])
        guard padX > 0 else { return } // user disabled drag-proximity entirely
        // Vertical band is half the horizontal pad, capped so huge horizontal values
        // don't make the region swallow half the menu bar.
        let padY = min(30, padX / 2)
        let region = baseRegion.insetBy(dx: -padX, dy: -padY)
        let isInside = region.contains(point)
        // Edge-triggered on region entry: if the shelf auto-closed while the user kept
        // hovering (the auto-close delay elapsed), leaving and re-entering re-fires.
        if isInside && !isShelfProximityActive {
            isShelfProximityActive = true
            onFileDragNearNotch?()
        } else if !isInside && isShelfProximityActive {
            isShelfProximityActive = false
        }
    }

    // MARK: - Shake Detection

    private func checkShakeGesture(currentPoint: CGPoint, currentTime: TimeInterval) {
        // Rule: Shake must ONLY trigger on the display where the cursor actually is (in multi-display mode)!
        if let screenFrame = screenFrameProvider?() {
            guard screenFrame.insetBy(dx: -20, dy: -20).contains(currentPoint) else { return }
        }

        // Debounce: don't trigger again within 0.8s of last shake
        guard currentTime - lastShakeTriggerTime > 0.8 else { return }

        recentSamples.append(MouseSample(x: currentPoint.x, y: currentPoint.y, time: currentTime))

        // Keep samples from the last 0.85s
        let cutoff = currentTime - 0.85
        recentSamples.removeAll { $0.time < cutoff }

        guard recentSamples.count >= 4 else { return }

        // Require at least 12pt per swing to rule out minor jitter
        let xs = recentSamples.map { $0.x }
        let minSwing: CGFloat = 12.0

        let revX = countAxisReversals(values: xs, minSwing: minSwing)

        // Require at least 2 horizontal direction reversals (3 strokes: Left ➔ Right ➔ Left or Right ➔ Left ➔ Right)
        guard revX >= 2 else { return }

        // Velocity & duration check:
        // Ensure the reversals happened rapidly enough
        guard let firstSample = recentSamples.first else { return }
        let elapsed = currentTime - firstSample.time
        guard elapsed >= 0.12 && elapsed <= 0.85 else { return }

        var totalXTravel: CGFloat = 0
        for i in 1..<recentSamples.count {
            totalXTravel += abs(recentSamples[i].x - recentSamples[i-1].x)
        }
        let horizontalSpeed = totalXTravel / CGFloat(elapsed)
        // User must shake at an intentional speed (>= 120 pt/s) to distinguish from casual mouse movement
        guard horizontalSpeed >= 120.0 else { return }

        // Check if this is an actual file/folder/droppable item drag!
        // Reject window dragging, browser tabs, text selection.
        // Also require a fresh drag session (changeCount moved since mouse-down) so
        // stale pasteboard types from an older drag cannot fake a file shake.
        guard let downCount = mouseDownPasteboardCount,
              dragPasteboard.changeCount != downCount,
              hasValidDragContent() else {
            // Not a valid file/folder drag! Clear samples so it doesn't fire for non-files.
            recentSamples.removeAll()
            return
        }

        lastShakeTriggerTime = currentTime
        recentSamples.removeAll()
        isContentDragging = true

        // Disengage hover radar so radar doesn't fight shelf open
        setHoveringFromRadar(false)

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
}
