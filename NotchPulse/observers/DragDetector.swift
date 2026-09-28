//
//  DragDetector.swift
//  NotchPulse
//
//  Created by Alexander on 2025-11-20.
//

import Cocoa
import Defaults
import UniformTypeIdentifiers

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

    // MARK: - Shake Detection State
    private struct MouseSample {
        let x: CGFloat
        let y: CGFloat
        let time: TimeInterval
    }
    private var recentSamples: [MouseSample] = []
    private var lastShakeTriggerTime: TimeInterval = 0

    private let regionProvider: () -> CGRect
    private let screenFrameProvider: (() -> CGRect)?
    private let dragPasteboard = NSPasteboard(name: .drag)

    init(regionProvider: @escaping () -> CGRect, screenFrameProvider: (() -> CGRect)? = nil) {
        self.regionProvider = regionProvider
        self.screenFrameProvider = screenFrameProvider
        self.lastKnownIdlePasteboardCount = dragPasteboard.changeCount
    }

    // MARK: - Private Helpers

    /// Checks if the physical left mouse or trackpad button is currently held down
    private var isLeftButtonPressed: Bool {
        return (NSEvent.pressedMouseButtons & 1) != 0
    }

    /// Checks if the drag pasteboard contains actual file, folder, image, text snippet, or droppable content.
    private func hasValidDragContent() -> Bool {
        guard let types = dragPasteboard.types, !types.isEmpty else {
            return false
        }

        let recognizedTypes: Set<String> = [
            NSPasteboard.PasteboardType.fileURL.rawValue,   // file://… URLs ("public.file-url")
            "public.file-url",
            "com.apple.finder.node",                       // Finder items (files, folders)
            "NSFilenamesPboardType",                       // legacy Finder drag
            "com.apple.pasteboard.promised-file-url",      // promised file drags (e.g. Mail attachments)
            "com.apple.pasteboard.promised-file-content-type",
            "com.apple.mac.install-source-container",      // .pkg, .dmg installer drags
            "public.url",                                  // URLs, bookmarks
            "Apple URL pasteboard type",
            "public.image",                                // Any image dragged from browser/photos
            "public.png",
            "public.jpeg",
            "public.tiff",
            "public.utf8-plain-text",                      // Text snippets
            "public.plain-text",
            "NSStringPboardType",
            "public.data",
            "com.apple.cocoa.pasteboard.findernode"
        ]

        for type in types {
            let raw = type.rawValue
            if recognizedTypes.contains(raw) { return true }
            if raw.hasPrefix("dyn.") && (raw.contains("file") || raw.contains("finder") || raw.contains("url") || raw.contains("image") || raw.contains("data")) {
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

        // Global monitor for leftMouseDragged & mouseMoved (for real-time response to drag and shake gestures)
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged, .mouseMoved]) { [weak self] _ in
            self?.checkState()
        }

        // Polling timer running in .common mode so it continues firing during active drag
        let timer = Timer(timeInterval: 0.10, repeats: true) { [weak self] _ in
            self?.checkState()
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func checkShakeGesture(currentPoint: CGPoint, currentTime: TimeInterval) {
        // ONLY detect shake-to-shelf when ACTUALLY dragging droppable content!
        guard isContentDragging else { return }

        // Rule: Shake must ONLY trigger on the display where the cursor actually is!
        if let screenFrame = screenFrameProvider?() {
            guard screenFrame.contains(currentPoint) else { return }
        }

        // Debounce: don't trigger again within 0.8s of last shake
        guard currentTime - lastShakeTriggerTime > 0.8 else { return }

        recentSamples.append(MouseSample(x: currentPoint.x, y: currentPoint.y, time: currentTime))

        // Keep samples from the last 400ms — forces the shake to be genuinely fast
        let cutoff = currentTime - 0.40
        recentSamples.removeAll { $0.time < cutoff }

        guard recentSamples.count >= 4 else { return }

        // Require at least 28pt per swing (≈ 1cm travel) so slow lazy sweeps don't trigger.
        // Only the horizontal axis counts — left/right shake intent.
        let xs = recentSamples.map { $0.x }
        let minSwing: CGFloat = 28.0

        let revX = countAxisReversals(values: xs, minSwing: minSwing)

        // Need 3 reversals (left→right→left→right) within 400ms — unmistakably deliberate
        if revX >= 3 {
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
        let mouseLocation = NSEvent.mouseLocation
        let now = ProcessInfo.processInfo.systemUptime
        let mousePressed = isLeftButtonPressed
        let currentPbCount = dragPasteboard.changeCount

        if !mousePressed {
            recentSamples.removeAll()
            dragStartLocation = nil
            mouseDownPasteboardCount = nil

            // Instant reset when mouse button is released.
            // Under NO circumstance should a released mouse remain in a dragging state.
            if isContentDragging {
                isContentDragging = false
                onDragEnded?()
            }
            lastKnownIdlePasteboardCount = currentPbCount

            // Hover radar: Only runs when extended hover area is explicitly enabled
            let shouldRunHoverRadar = Defaults[.extendHoverArea]
            if shouldRunHoverRadar {
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
        // Pasteboard changeCount changed or pasteboard has valid drag content AND mouse moved >= 6pt
        let isPasteboardChanged = (lastKnownIdlePasteboardCount >= 0 && currentPbCount != lastKnownIdlePasteboardCount) ||
                                  (mouseDownPasteboardCount != nil && currentPbCount != mouseDownPasteboardCount)
        let isNewDragOperation = (isPasteboardChanged || currentPbCount > 0) && hasValidDragContent() && hasMovedSufficiently

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
        isContentDragging = false
        recentSamples.removeAll()
        dragStartLocation = nil
        mouseDownPasteboardCount = nil
        lastKnownIdlePasteboardCount = dragPasteboard.changeCount
    }

    deinit {
        stopMonitoring()
    }
}

