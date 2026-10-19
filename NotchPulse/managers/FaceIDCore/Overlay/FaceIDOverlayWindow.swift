import AppKit

final class FaceIDOverlayWindow: NSPanel {
    /// Whether the panel may become key. Tracked separately from
    /// `ignoresMouseEvents`, which `FaceIDOverlayWindowController` flips on and off as
    /// the cursor moves over/away from the visible panel — tying key status to
    /// that would stop onboarding's text fields taking focus whenever the
    /// cursor happened to sit outside the panel.
    var acceptsKey = false

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 4)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        // Decorative by default — clicks pass through until a failed attempt is
        // waiting to be tapped for retry (see FaceIDOverlayWindowController.setInteractive).
        ignoresMouseEvents = true
    }

    // MARK: - Position Locking (Prevents overlay from ever dropping down / centering)

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
        // Face ID overlay MUST strictly stay flush against the top edge of screen, NEVER centered!
        guard let screen = self.screen ?? NSScreen.main else { return }
        let screenFrame = screen.frame
        let topY = screenFrame.origin.y + screenFrame.height - frame.height
        let centerX = screenFrame.origin.x + (screenFrame.width - frame.width) / 2
        super.setFrameOrigin(NSPoint(x: centerX, y: topY))
    }

    override func setFrameOrigin(_ newOrigin: NSPoint) {
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

    /// Must become key while interactive or the tap-to-retry gesture never receives
    /// the click; never becomes main, so it doesn't take over as the app's primary window.
    override var canBecomeKey: Bool { acceptsKey }
    override var canBecomeMain: Bool { false }
}
