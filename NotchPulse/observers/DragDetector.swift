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

    private var pollTimer: Timer?
    private var mouseDraggedMonitor: Any?

    private var lastKnownIdlePasteboardCount: Int = -1
    private var isContentDragging: Bool = false {
        didSet {
            if isContentDragging != oldValue {
                onGlobalDragStateChanged?(isContentDragging)
            }
        }
    }
    private var hasEnteredNotchRegion: Bool = false
    private var isHoveringFromRadar: Bool = false

    private let regionProvider: (_ isDraggingContent: Bool) -> CGRect
    private let dragPasteboard = NSPasteboard(name: .drag)

    init(regionProvider: @escaping (_ isDraggingContent: Bool) -> CGRect) {
        self.regionProvider = regionProvider
        self.lastKnownIdlePasteboardCount = dragPasteboard.changeCount
    }

    // MARK: - Private Helpers

    /// Checks if the left mouse or trackpad button is currently held down
    private var isLeftButtonPressed: Bool {
        if (NSEvent.pressedMouseButtons & 1) != 0 {
            return true
        }
        if CGEventSource.buttonState(.combinedSessionState, button: .left) {
            return true
        }
        if CGEventSource.buttonState(.hidSystemState, button: .left) {
            return true
        }
        return false
    }

    /// Checks if the drag pasteboard contains valid content types
    private func hasValidDragContent() -> Bool {
        guard let types = dragPasteboard.types, !types.isEmpty else {
            return false
        }
        return true
    }

    func startMonitoring() {
        stopMonitoring()
        lastKnownIdlePasteboardCount = dragPasteboard.changeCount

        // Global monitor for leftMouseDragged (immediate response when events are delivered)
        mouseDraggedMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] _ in
            self?.checkState()
        }

        // High-frequency polling timer (25Hz / 40ms) running in .common mode so it continues
        // firing without pausing during active WindowServer NSDraggingSession.
        let timer = Timer(timeInterval: 0.04, repeats: true) { [weak self] _ in
            self?.checkState()
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func checkState() {
        let mouseLocation = NSEvent.mouseLocation
        let mousePressed = isLeftButtonPressed
        let currentPbCount = dragPasteboard.changeCount

        if !mousePressed {
            // Mouse is released -> IDLE STATE
            if isContentDragging || hasEnteredNotchRegion {
                let wasInRegion = hasEnteredNotchRegion
                isContentDragging = false
                hasEnteredNotchRegion = false
                if wasInRegion {
                    onDragExitsNotchRegion?()
                }
                onDragEnded?()
            }

            // Continuously keep baseline synchronized to idle pasteboard
            lastKnownIdlePasteboardCount = currentPbCount

            // Hover radar: ONLY runs during idle (when mouse is NOT pressed and NOT dragging)
            if Defaults[.extendHoverArea] {
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
        // While dragging, hover radar MUST NOT fire to prevent conflicting with drag expand
        if isHoveringFromRadar {
            isHoveringFromRadar = false
            onGlobalHoverStateChanged?(false)
        }

        // Detect if a drag operation is active:
        // Pasteboard changeCount changed from the idle baseline while button is down, with valid content
        let isNewDragOperation = (currentPbCount != lastKnownIdlePasteboardCount) && hasValidDragContent()

        if isContentDragging || isNewDragOperation {
            isContentDragging = true
            onDragMove?(mouseLocation)

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
        }
    }

    func stopMonitoring() {
        pollTimer?.invalidate()
        pollTimer = nil
        isHoveringFromRadar = false

        if let monitor = mouseDraggedMonitor {
            NSEvent.removeMonitor(monitor)
        }
        mouseDraggedMonitor = nil
        isContentDragging = false
        hasEnteredNotchRegion = false
        lastKnownIdlePasteboardCount = -1
    }

    deinit {
        stopMonitoring()
    }
}

