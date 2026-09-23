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

    private var mouseDraggedMonitor: Any?
    private var mouseUpMonitor: Any?

    private var idlePasteboardChangeCount: Int = -1
    private var isContentDragging: Bool = false
    private var hasEnteredNotchRegion: Bool = false

    private let notchRegion: CGRect
    private let dragPasteboard = NSPasteboard(name: .drag)

    init(notchRegion: CGRect) {
        self.notchRegion = notchRegion
        self.idlePasteboardChangeCount = dragPasteboard.changeCount
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
        idlePasteboardChangeCount = dragPasteboard.changeCount

        // Track drag movement and notch region intersection
        mouseDraggedMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] _ in
            guard let self = self else { return }

            let currentChangeCount = self.dragPasteboard.changeCount
            let isNewDragOperation = (currentChangeCount != self.idlePasteboardChangeCount)

            // ONLY trigger drag expansion if a NEW drag pasteboard item was created (file, url, text).
            // If changeCount did NOT change, the user is dragging a window titlebar or selecting text!
            if isNewDragOperation && self.hasValidDragContent() {
                self.isContentDragging = true
                let mouseLocation = NSEvent.mouseLocation
                self.onDragMove?(mouseLocation)
                
                // Track entry into the expanded notch region
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
            self.idlePasteboardChangeCount = self.dragPasteboard.changeCount
            self.isContentDragging = false
            self.hasEnteredNotchRegion = false
        }
    }

    func stopMonitoring() {
        [mouseDraggedMonitor, mouseUpMonitor].forEach { monitor in
            if let monitor = monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
        mouseDraggedMonitor = nil
        mouseUpMonitor = nil
        isContentDragging = false
        hasEnteredNotchRegion = false
    }

    deinit {
        stopMonitoring()
    }
}
