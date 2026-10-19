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
    
    // MARK: - Position Locking (Prevents notch from ever dropping down / centering)

    private func targetScreen(for point: NSPoint) -> NSScreen? {
        let centerPoint = NSPoint(x: point.x + frame.width / 2, y: point.y + frame.height / 2)
        if let direct = NSScreen.screens.first(where: { $0.frame.contains(centerPoint) }) {
            return direct
        }
        if let horizontal = NSScreen.screens.first(where: { point.x + frame.width / 2 >= $0.frame.minX && point.x + frame.width / 2 <= $0.frame.maxX }) {
            return horizontal
        }
        return self.screen ?? NSScreen.main
    }

    override func center() {
        // Notch window MUST strictly stay flush against the top edge of screen, NEVER centered!
        guard let screen = self.screen ?? NSScreen.main else { return }
        let screenFrame = screen.frame
        let topY = screenFrame.origin.y + screenFrame.height - frame.height
        let centerX = screenFrame.origin.x + (screenFrame.width - frame.width) / 2
        super.setFrameOrigin(NSPoint(x: centerX, y: topY))
    }

    override func setFrameOrigin(_ newOrigin: NSPoint) {
        // Enforce that the top edge (origin.y + frame.height) ALWAYS attaches flush to the screen's top bezel (screen.frame.maxY).
        // Prevents any mechanism, alert, or external window manager from ever dropping the notch down.
        guard let screen = targetScreen(for: newOrigin) else {
            super.setFrameOrigin(newOrigin)
            return
        }
        let topY = screen.frame.origin.y + screen.frame.height - frame.height
        super.setFrameOrigin(NSPoint(x: newOrigin.x, y: topY))
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        guard let screen = targetScreen(for: frameRect.origin) else {
            super.setFrame(frameRect, display: flag)
            return
        }
        var rect = frameRect
        rect.origin.y = screen.frame.origin.y + screen.frame.height - frameRect.height
        super.setFrame(rect, display: flag)
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool, animate: Bool) {
        guard let screen = targetScreen(for: frameRect.origin) else {
            super.setFrame(frameRect, display: flag, animate: animate)
            return
        }
        var rect = frameRect
        rect.origin.y = screen.frame.origin.y + screen.frame.height - frameRect.height
        super.setFrame(rect, display: flag, animate: animate)
    }

    override var canBecomeKey: Bool {
        false
    }
    
    override var canBecomeMain: Bool {
        false
    }
}
