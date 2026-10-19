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

    // MARK: - Position Safety

    override func center() {
        guard let screen = self.screen ?? NSScreen.main else { return }
        super.setFrameOrigin(NSPoint(x: screen.frame.midX - frame.width / 2, y: screen.frame.maxY - frame.height))
    }

    /// Must become key while interactive or the tap-to-retry gesture never receives
    /// the click; never becomes main, so it doesn't take over as the app's primary window.
    override var canBecomeKey: Bool { acceptsKey }
    override var canBecomeMain: Bool { false }
}
