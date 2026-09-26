//
//  ShelfDropZoneWindow.swift
//  NotchPulse
//
//  Created by Alexander on 2026-09-26.
//

import Cocoa
import UniformTypeIdentifiers

final class ShelfDropZoneView: NSView {
    var onDragEntered: (() -> Void)?
    var onDragExited: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([
            .fileURL,
            .string,
            NSPasteboard.PasteboardType("Apple URL pasteboard type"),
            NSPasteboard.PasteboardType("NSFilenamesPboardType"),
            NSPasteboard.PasteboardType("com.apple.finder.node"),
            NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-url")
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        onDragEntered?()
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onDragExited?()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        return true
    }
}

final class ShelfDropZoneWindow: NSPanel {
    let dropZoneView = ShelfDropZoneView(frame: .zero)

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        isMovable = false
        ignoresMouseEvents = true
        level = .mainMenu + 2
        collectionBehavior = [.fullScreenAuxiliary, .stationary, .canJoinAllSpaces, .ignoresCycle]
        contentView = dropZoneView
    }
}
