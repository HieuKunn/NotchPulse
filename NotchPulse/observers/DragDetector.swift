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
    var onDragMove: PositionCallback?

    private var mouseDownMonitor: Any?
    private var mouseDraggedMonitor: Any?
    private var mouseUpMonitor: Any?

    private var pasteboardChangeCount: Int = -1
    private var isDragging: Bool = false
    private var isContentDragging: Bool = false
    private var hasEnteredNotchRegion: Bool = false

    private let notchRegion: CGRect
    private let dragPasteboard = NSPasteboard(name: .drag)

    init(notchRegion: CGRect) {
        self.notchRegion = notchRegion
    }

    // MARK: - Private Helpers
    
    /// Checks if the drag pasteboard contains valid content types that can be dropped on the shelf
    private func hasValidDragContent() -> Bool {
        guard let types = dragPasteboard.types, !types.isEmpty else { return false }
        
        let validIdentifiers: Set<String> = [
            NSPasteboard.PasteboardType.fileURL.rawValue,
            NSPasteboard.PasteboardType.string.rawValue,
            NSPasteboard.PasteboardType.tiff.rawValue,
            NSPasteboard.PasteboardType.png.rawValue,
            NSPasteboard.PasteboardType.html.rawValue,
            NSPasteboard.PasteboardType.rtf.rawValue,
            "NSFilenamesPboardType",
            "com.apple.finder.node",
            "com.apple.pasteboard.promised-file-url",
            "com.apple.cocoa.pasteboard.item",
            "public.file-url",
            "public.url",
            "public.utf8-plain-text",
            "public.text",
            "public.image",
            "public.data"
        ]
        
        return types.contains { type in
            validIdentifiers.contains(type.rawValue) ||
            type.rawValue.contains("file") ||
            type.rawValue.contains("url") ||
            type.rawValue.contains("text") ||
            type.rawValue.contains("image")
        }
    }

    func startMonitoring() {
        stopMonitoring()

        // Track mouse down to prepare drag detection
        mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            guard let self = self else { return }
            self.pasteboardChangeCount = self.dragPasteboard.changeCount
            self.isDragging = true
            self.isContentDragging = false
            self.hasEnteredNotchRegion = false
        }

        // Track drag movement and notch region intersection
        mouseDraggedMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] _ in
            guard let self = self else { return }

            // If mouse button is pressed and dragging, detect drag state even if mouseDown was consumed by another app
            let isMousePressed = (NSEvent.pressedMouseButtons & 1) != 0
            guard self.isDragging || isMousePressed else { return }
            self.isDragging = true

            // Content is dragging if pasteboard has valid content or changeCount changed
            if !self.isContentDragging {
                if self.hasValidDragContent() || (self.dragPasteboard.changeCount != self.pasteboardChangeCount && self.pasteboardChangeCount != -1) {
                    self.isContentDragging = true
                }
            }

            // Only process position when content is being dragged
            if self.isContentDragging {
                let mouseLocation = NSEvent.mouseLocation
                self.onDragMove?(mouseLocation)
                
                // Track notch region entry/exit
                let containsMouse = self.notchRegion.contains(mouseLocation)
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
            self.isDragging = false
            self.isContentDragging = false
            self.hasEnteredNotchRegion = false
            self.pasteboardChangeCount = -1
        }
    }

    func stopMonitoring() {
        [mouseDownMonitor, mouseDraggedMonitor, mouseUpMonitor].forEach { monitor in
            if let monitor = monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
        mouseDownMonitor = nil
        mouseDraggedMonitor = nil
        mouseUpMonitor = nil
        isDragging = false
        isContentDragging = false
        hasEnteredNotchRegion = false
    }

    deinit {
        stopMonitoring()
    }
}
