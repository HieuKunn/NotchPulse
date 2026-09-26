//
//  DragDetector.swift
//  NotchPulse
//
//  Created by Alexander on 2025-11-20.
//

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
    var onGlobalDragStateChanged: ((Bool) -> Void)?
    var onGlobalHoverStateChanged: ((Bool) -> Void)?

    private var mouseDownMonitor: Any?
    private var mouseDraggedMonitor: Any?
    private var mouseUpMonitor: Any?
    private var pollTimer: Timer?

    private var mouseDownPasteboardCount: Int = -1
    private var lastKnownIdleCount: Int = -1
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
        self.lastKnownIdleCount = dragPasteboard.changeCount
    }

    // MARK: - Private Helpers
    
    /// Checks if the drag pasteboard contains valid content types that can be dropped on the shelf
    private func hasValidDragContent() -> Bool {
        guard let types = dragPasteboard.types, !types.isEmpty else {
            return false
        }
        
        let validIdentifiers: Set<String> = [
            NSPasteboard.PasteboardType.fileURL.rawValue,
            "NSFilenamesPboardType",
            "Apple URL pasteboard type",
            "com.apple.pasteboard.promised-file-url",
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
        
        for type in types {
            if validIdentifiers.contains(type.rawValue) {
                return true
            }
            if let utType = UTType(type.rawValue),
               utType.conforms(to: .item) || utType.conforms(to: .content) || utType.conforms(to: .data) {
                return true
            }
        }
        return false
    }

    func startMonitoring() {
        stopMonitoring()
        lastKnownIdleCount = dragPasteboard.changeCount

        mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            guard let self = self else { return }
            self.mouseDownPasteboardCount = self.dragPasteboard.changeCount
            self.isContentDragging = false
            self.hasEnteredNotchRegion = false
        }

        // Track drag movement and notch region intersection
        mouseDraggedMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] _ in
            guard let self = self else { return }

            let isMousePressed = (NSEvent.pressedMouseButtons & 1) != 0
            if !isMousePressed {
                if self.isContentDragging || self.hasEnteredNotchRegion {
                    let wasInRegion = self.hasEnteredNotchRegion
                    self.isContentDragging = false
                    self.hasEnteredNotchRegion = false
                    self.mouseDownPasteboardCount = -1
                    self.lastKnownIdleCount = self.dragPasteboard.changeCount
                    if wasInRegion {
                        self.onDragExitsNotchRegion?()
                    }
                    self.onDragEnded?()
                }
                return
            }

            let mouseLocation = NSEvent.mouseLocation
            // Fast rejection: If mouse is not in the upper region of any screen and not already inside the notch region, skip all pasteboard IPC
            if !self.hasEnteredNotchRegion {
                let isNearTopEdge = NSScreen.screens.contains { screen in
                    mouseLocation.y >= screen.frame.maxY - 250
                }
                if !isNearTopEdge {
                    return
                }
            }

            let currentCount = self.dragPasteboard.changeCount
            
            // Detect if a file/URL drag operation started during this mouse gesture
            let isNewDragOperation = (self.mouseDownPasteboardCount != -1 && currentCount != self.mouseDownPasteboardCount) ||
                                     (self.mouseDownPasteboardCount == -1 && currentCount != self.lastKnownIdleCount)

            if (self.isContentDragging || isNewDragOperation) && self.hasValidDragContent() {
                self.isContentDragging = true
                let mouseLocation = NSEvent.mouseLocation
                self.onDragMove?(mouseLocation)
                
                // Track entry into the dynamic notch region (which expands when shelf is open)
                let activeRegion = self.regionProvider(true)
                let containsMouse = activeRegion.contains(mouseLocation)
                if containsMouse && !self.hasEnteredNotchRegion {
                    self.hasEnteredNotchRegion = true
                    self.onDragEntersNotchRegion?()
                } else if !containsMouse && self.hasEnteredNotchRegion {
                    self.hasEnteredNotchRegion = false
                    self.onDragExitsNotchRegion?()
                }
            }
        }

        mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            guard let self = self else { return }
            self.lastKnownIdleCount = self.dragPasteboard.changeCount
            self.mouseDownPasteboardCount = -1
            let wasInRegion = self.hasEnteredNotchRegion
            self.hasEnteredNotchRegion = false
            self.isContentDragging = false
            if wasInRegion {
                self.onDragExitsNotchRegion?()
            }
            self.onDragEnded?()
        }
        
        // Add a lightweight fallback polling timer to detect rapid drag starts
        // where macOS WindowServer suppresses global leftMouseDragged events.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            // Unconditional hover radar (works whether mouse is pressed or not, uses distinct hover boundaries)
            let mouseLocation = NSEvent.mouseLocation
            let hoverRegion = self.regionProvider(false)
            let containsMouseHover = hoverRegion.contains(mouseLocation)
            
            if containsMouseHover && !self.isHoveringFromRadar {
                self.isHoveringFromRadar = true
                self.onGlobalHoverStateChanged?(true)
            } else if !containsMouseHover && self.isHoveringFromRadar {
                self.isHoveringFromRadar = false
                self.onGlobalHoverStateChanged?(false)
            }

            let isMousePressed = (NSEvent.pressedMouseButtons & 1) != 0
            if !isMousePressed {
                if self.isContentDragging || self.hasEnteredNotchRegion {
                    let wasInRegion = self.hasEnteredNotchRegion
                    self.isContentDragging = false
                    self.hasEnteredNotchRegion = false
                    self.mouseDownPasteboardCount = -1
                    self.lastKnownIdleCount = self.dragPasteboard.changeCount
                    if wasInRegion {
                        self.onDragExitsNotchRegion?()
                    }
                    self.onDragEnded?()
                }
                return
            }
            let currentCount = self.dragPasteboard.changeCount
            let isNewDragOperation = (self.mouseDownPasteboardCount != -1 && currentCount != self.mouseDownPasteboardCount) ||
                                     (self.mouseDownPasteboardCount == -1 && currentCount != self.lastKnownIdleCount)
            
            if (self.isContentDragging || isNewDragOperation) && self.hasValidDragContent() {
                self.isContentDragging = true
                self.onDragMove?(mouseLocation)
                
                let activeDragRegion = self.regionProvider(true)
                let containsMouseDrag = activeDragRegion.contains(mouseLocation)
                if containsMouseDrag && !self.hasEnteredNotchRegion {
                    self.hasEnteredNotchRegion = true
                    self.onDragEntersNotchRegion?()
                } else if !containsMouseDrag && self.hasEnteredNotchRegion {
                    self.hasEnteredNotchRegion = false
                    self.onDragExitsNotchRegion?()
                }
            }
        }
    }

    func stopMonitoring() {
        pollTimer?.invalidate()
        pollTimer = nil
        self.isHoveringFromRadar = false
        
        [mouseDownMonitor, mouseDraggedMonitor, mouseUpMonitor].forEach { monitor in
            if let monitor = monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
        mouseDownMonitor = nil
        mouseDraggedMonitor = nil
        mouseUpMonitor = nil
        isContentDragging = false
        hasEnteredNotchRegion = false
        mouseDownPasteboardCount = -1
    }

    deinit {
        stopMonitoring()
    }
}
