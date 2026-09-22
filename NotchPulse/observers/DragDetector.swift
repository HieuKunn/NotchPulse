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
    
    /// Returns true ONLY for genuine file-system drag sessions initiated in Finder or
    /// similar apps. This intentionally excludes text selections, web content, in-app
    /// image drags, and anything that would cause false-positive shelf openings.
    private func hasValidFileDragContent() -> Bool {
        guard let types = dragPasteboard.types, !types.isEmpty else { return false }
        
        // Exact-match allowlist for real file drags. Do NOT add broad types like
        // "public.text", "public.image", "public.data" — those match web/in-app drags.
        let fileOnlyTypes: Set<String> = [
            "public.file-url",                           // Standard macOS file drag
            NSPasteboard.PasteboardType.fileURL.rawValue, // Same via AppKit constant
            "NSFilenamesPboardType",                      // Legacy Finder drag
            "com.apple.finder.node",                      // Finder internal node drag
            "com.apple.pasteboard.promised-file-url",     // Promised files (e.g. Photos export)
        ]
        
        return types.contains { fileOnlyTypes.contains($0.rawValue) }
    }

    func startMonitoring() {
        stopMonitoring()

        // Record pasteboard state at the moment the mouse button goes down.
        mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            guard let self = self else { return }
            self.pasteboardChangeCount = self.dragPasteboard.changeCount
            self.isDragging = true
            self.isContentDragging = false
            self.hasEnteredNotchRegion = false
        }

        // Track drag movement — only activate when it is a genuine file drag.
        mouseDraggedMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] _ in
            guard let self = self else { return }
            guard self.isDragging else { return }

            // Promote to a content-drag only when:
            //   1. The drag pasteboard changed since mouseDown (macOS populates it at drag start), AND
            //   2. The pasteboard carries a real file type (not a web-page text selection, etc.)
            if !self.isContentDragging {
                let pasteboardChanged = self.dragPasteboard.changeCount != self.pasteboardChangeCount
                if pasteboardChanged && self.hasValidFileDragContent() {
                    self.isContentDragging = true
                }
            }

            // Only track notch entry when carrying a genuine file.
            if self.isContentDragging {
                let mouseLocation = NSEvent.mouseLocation
                self.onDragMove?(mouseLocation)
                
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
