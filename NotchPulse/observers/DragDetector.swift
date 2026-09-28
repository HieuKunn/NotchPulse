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
        self.lastKnownIdlePasteboardCount = dragPasteboard.changeCount
    }

    // MARK: - Private Helpers

    /// Checks if the physical left mouse or trackpad button is currently held down
    private var isLeftButtonPressed: Bool {
        return (NSEvent.pressedMouseButtons & 1) != 0 ||
               CGEventSource.buttonState(.combinedSessionState, button: .left) ||
               CGEventSource.buttonState(.hidSystemState, button: .left)
    }

    /// Checks if the drag pasteboard contains actual file, folder, image, or droppable items (strictly excluding tabs and app windows).
    private func hasValidDragContent() -> Bool {
        guard let types = dragPasteboard.types, !types.isEmpty else {
            return false
        }

        // 1. Blacklist browser tabs, window dragging, and app UI elements
        let tabAndWindowTypes: Set<String> = [
            "org.chromium.drag-type.tab",
            "com.google.Chrome.tab",
            "company.thebrowser.Arc.tab",
            "com.apple.Safari.tab",
            "com.apple.Safari.tab-drag",
            "application/x-moz-tabbrowser-tab",
            "com.apple.tab-drag",
            "com.apple.window-drag",
            "com.apple.NSWindow.drag"
        ]
        for type in types {
            let raw = type.rawValue
            if tabAndWindowTypes.contains(raw) || raw.contains(".tab") || raw.contains("tab-drag") || raw.contains("window-drag") {
                return false
            }
        }

        // 2. High-priority check: Can the pasteboard provide actual file:// URLs?
        if dragPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) {
            return true
        }

        // 3. File promise receivers (used by Dock stacks, Mail attachments, and Photos exports)
        if dragPasteboard.canReadObject(forClasses: [NSFilePromiseReceiver.self], options: nil) {
            return true
        }

        // 4. Exact recognized types for files, folders, and Dock stacks
        let recognizedTypes: Set<String> = [
            NSPasteboard.PasteboardType.fileURL.rawValue,   // file://… URLs ("public.file-url")
            "public.file-url",
            "com.apple.finder.node",                       // Finder items (files, folders)
            "NSFilenamesPboardType",                       // legacy Finder drag
            "com.apple.dock.item",                         // macOS Dock stack items (Downloads, etc.)
            "com.apple.dock.drag-item",
            "Apple promised file pasteboard type",         // Promised files from Dock or Mail
            "com.apple.pasteboard.promised-file-url",
            "com.apple.pasteboard.promised-file-content-type",
            "com.apple.mac.install-source-container",      // .pkg, .dmg installer drags
            "com.apple.cocoa.pasteboard.findernode",
            "public.image",                                // Any image dragged from browser/photos
            "public.png",
            "public.jpeg",
            "public.tiff"
        ]

        for type in types {
            let raw = type.rawValue
            if recognizedTypes.contains(raw) { return true }
            if raw.hasPrefix("dyn.") && (raw.contains("file") || raw.contains("finder") || raw.contains("dock") || raw.contains("image")) {
                return true
            }
        }

        return false
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
        // ONLY detect shake-to-shelf when ACTUALLY dragging droppable content!
        guard isContentDragging else { return }

        // Rule: Shake must ONLY trigger on the display where the cursor actually is (in multi-display mode)!
        if let screenFrame = screenFrameProvider?() {
            guard screenFrame.insetBy(dx: -20, dy: -20).contains(currentPoint) else { return }
        }

        // Debounce: don't trigger again within 0.8s of last shake
        guard currentTime - lastShakeTriggerTime > 0.8 else { return }

        recentSamples.append(MouseSample(x: currentPoint.x, y: currentPoint.y, time: currentTime))

        // Keep samples from the last 1.8s (natural fast continuous shake)
        let cutoff = currentTime - 1.8
        recentSamples.removeAll { $0.time < cutoff }

        guard recentSamples.count >= 4 else { return }

        // Require at least 12pt per swing
        let xs = recentSamples.map { $0.x }
        let ys = recentSamples.map { $0.y }
        let minSwing: CGFloat = 12.0

        let revX = countAxisReversals(values: xs, minSwing: minSwing)
        let revY = countAxisReversals(values: ys, minSwing: minSwing)
        let maxReversals = max(revX, revY)

        // Require 3 direction reversals (4 fast continuous strokes: L→R→L→R or R→L→R→L)
        if maxReversals >= 3 {
            lastShakeTriggerTime = currentTime
            recentSamples.removeAll()
            onShakeDetected?()
        }
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

            lastKnownIdlePasteboardCount = currentPbCount
            recentSamples.removeAll()
            dragStartLocation = nil
            mouseDownPasteboardCount = nil

            // Reset when mouse button is confirmed released.
            if isContentDragging {
                isContentDragging = false
                onDragEnded?()
            }

            // Hover radar: Only runs when extended hover area is explicitly enabled
            let shouldRunHoverRadar = Defaults[.extendHoverArea]
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

        // Detect if active drag session:
        // Pasteboard changeCount changed with valid drag content AND mouse moved >= 6pt
        let isPasteboardChanged = (lastKnownIdlePasteboardCount >= 0 && currentPbCount != lastKnownIdlePasteboardCount) ||
                                  (mouseDownPasteboardCount != nil && currentPbCount != mouseDownPasteboardCount)
        let isNewDragOperation = isPasteboardChanged && hasValidDragContent() && hasMovedSufficiently

        if isContentDragging || isNewDragOperation {
            isContentDragging = true
            onDragMove?(mouseLocation)

            // ONLY detect shake-to-shelf when ACTUALLY dragging a file or droppable content!
            // No proximity/hover drag tracking — shelf only opens on deliberate left-right shake!
            checkShakeGesture(currentPoint: mouseLocation, currentTime: now)

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
        lastKnownIdlePasteboardCount = dragPasteboard.changeCount
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

