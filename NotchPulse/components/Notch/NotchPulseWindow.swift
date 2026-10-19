import Cocoa

class NotchPulseWindow: NSPanel {
    override init(
        contentRect: NSRect,
        styleMask: NSWindow.StyleMask,
        backing: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: styleMask,
            backing: backing,
            defer: flag
        )
        
        isFloatingPanel = true
        isOpaque = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        backgroundColor = .clear
        isMovable = false
        isMovableByWindowBackground = false
        
        collectionBehavior = [
            .fullScreenAuxiliary,
            .stationary,
            .canJoinAllSpaces,
            .ignoresCycle,
        ]
        
        isReleasedWhenClosed = false
        level = .mainMenu + 3
        hasShadow = false
    }
    
    // MARK: - Position Safety

    override func center() {
        guard let screen = self.screen ?? NSScreen.main else { return }
        super.setFrameOrigin(NSPoint(x: screen.frame.midX - frame.width / 2, y: screen.frame.maxY - frame.height))
    }

    override var canBecomeKey: Bool {
        false
    }
    
    override var canBecomeMain: Bool {
        false
    }
}
