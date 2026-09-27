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

    var onDragEntersNotchRegion: VoidCallback?
    var onDragExitsNotchRegion: VoidCallback?
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
    private var hasEnteredNotchRegion: Bool = false
    private var isHoveringFromRadar: Bool = false

    // MARK: - Shake Detection State
    private struct MouseSample {
        let x: CGFloat
        let y: CGFloat
        let time: TimeInterval
    }
    private var recentSamples: [MouseSample] = []
    private var lastShakeTriggerTime: TimeInterval = 0

    private let regionProvider: (_ isDraggingContent: Bool) -> CGRect
    private let dragPasteboard = NSPasteboard(name: .drag)

    init(regionProvider: @escaping (_ isDraggingContent: Bool) -> CGRect) {
        self.regionProvider = regionProvider
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

        // High-frequency polling timer (33Hz / 30ms) running in .common mode so it continues
        // firing without pausing during active WindowServer NSDraggingSession.
        let timer = Timer(timeInterval: 0.03, repeats: true) { [weak self] _ in
            self?.checkState()
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func checkShakeGesture(currentPoint: CGPoint, currentTime: TimeInterval) {
        // ONLY detect shake-to-shelf when ACTUALLY dragging droppable content!
        guard isContentDragging else { return }

        // Debounce: don't trigger again within 0.8s of last shake
        guard currentTime - lastShakeTriggerTime > 0.8 else { return }

        recentSamples.append(MouseSample(x: currentPoint.x, y: currentPoint.y, time: currentTime))

        // Keep samples from the last 850ms (natural human gesture window)
        let cutoff = currentTime - 0.85
        recentSamples.removeAll { $0.time < cutoff }

        guard recentSamples.count >= 3 else { return }

        // Detect direction reversals (swings) with at least 10px travel (horizontal or vertical)
        var reversals = 0
        var currentDirection = 0 // -1 for left, +1 for right
        var lastExtremumX = recentSamples[0].x
        let minSwing: CGFloat = 10.0

        for sample in recentSamples {
            let dx = sample.x - lastExtremumX
            if currentDirection == 0 {
                if abs(dx) >= minSwing {
                    currentDirection = dx > 0 ? 1 : -1
                    lastExtremumX = sample.x
                }
            } else if currentDirection == 1 { // Was moving right
                if dx < -minSwing { // Reversed to moving left
                    reversals += 1
                    currentDirection = -1
                    lastExtremumX = sample.x
                } else if sample.x > lastExtremumX {
                    lastExtremumX = sample.x
                }
            } else if currentDirection == -1 { // Was moving left
                if dx > minSwing { // Reversed to moving right
                    reversals += 1
                    currentDirection = 1
                    lastExtremumX = sample.x
                } else if sample.x < lastExtremumX {
                    lastExtremumX = sample.x
                }
            }
        }

        // 2 or more reversals in 850ms signifies a deliberate rapid horizontal shake (Left -> Right -> Left or Right -> Left -> Right)
        if reversals >= 2 {
            lastShakeTriggerTime = currentTime
            recentSamples.removeAll()
            onShakeDetected?()
        }
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
            if isContentDragging || hasEnteredNotchRegion {
                let wasInRegion = hasEnteredNotchRegion
                isContentDragging = false
                hasEnteredNotchRegion = false
                if wasInRegion {
                    onDragExitsNotchRegion?()
                }
                onDragEnded?()
            }
            lastKnownIdlePasteboardCount = currentPbCount

            // Hover radar: Only runs when extended hover area is explicitly enabled
            let shouldRunHoverRadar = Defaults[.extendHoverArea]
            if shouldRunHoverRadar {
                let hoverRegion = regionProvider(false)
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

        // 8 points is sufficient to distinguish an intentional drag from a static click
        let hasMovedSufficiently = dragDistance >= 8.0

        // Detect if active drag session:
        // Pasteboard changeCount changed from idle baseline or mouse-down baseline, with valid drag content,
        // AND the user has moved the mouse sufficiently to distinguish from a stationary click.
        let isPasteboardChanged = (lastKnownIdlePasteboardCount >= 0 && currentPbCount != lastKnownIdlePasteboardCount) ||
                                  (mouseDownPasteboardCount != nil && currentPbCount != mouseDownPasteboardCount)
        let isNewDragOperation = isPasteboardChanged && hasValidDragContent() && hasMovedSufficiently

        if isContentDragging || isNewDragOperation {
            isContentDragging = true
            onDragMove?(mouseLocation)

            // ONLY detect shake-to-shelf when ACTUALLY dragging a file or droppable content!
            checkShakeGesture(currentPoint: mouseLocation, currentTime: now)

            // While actively dragging files, disengage hover radar
            if isHoveringFromRadar {
                isHoveringFromRadar = false
                onGlobalHoverStateChanged?(false)
            }

            // Check intersection with expanded drag detection region
            let activeDragRegion = regionProvider(true)
            let containsMouseDrag = activeDragRegion.contains(mouseLocation)

            if containsMouseDrag && !hasEnteredNotchRegion {
                hasEnteredNotchRegion = true
                onDragEntersNotchRegion?()
            } else if !containsMouseDrag && hasEnteredNotchRegion {
                hasEnteredNotchRegion = false
                onDragExitsNotchRegion?()
            }
        } else {
            // Mouse is pressed down (e.g. moving an app window, selecting text, or regular click):
            // NEVER trigger a new hover radar open while mouse button is held!
            // Only maintain hover radar if it was already active before mouse-down.
            if isHoveringFromRadar {
                let hoverRegion = regionProvider(false)
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
        hasEnteredNotchRegion = false
        recentSamples.removeAll()
        dragStartLocation = nil
        mouseDownPasteboardCount = nil
        lastKnownIdlePasteboardCount = dragPasteboard.changeCount
    }

    deinit {
        stopMonitoring()
    }
}

