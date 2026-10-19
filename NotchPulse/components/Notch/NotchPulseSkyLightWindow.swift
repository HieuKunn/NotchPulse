import Cocoa
import SkyLightWindow
import Defaults
import Combine
import SwiftUI

extension SkyLightOperator {
    func undelegateWindow(_ window: NSWindow) {
        typealias F_SLSRemoveWindowsFromSpaces = @convention(c) (Int32, CFArray, CFArray) -> Int32
        
        let handler = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_NOW)
        guard let SLSRemoveWindowsFromSpaces = unsafeBitCast(
            dlsym(handler, "SLSRemoveWindowsFromSpaces"),
            to: F_SLSRemoveWindowsFromSpaces?.self
        ) else {
            return
        }
        
        // Remove the window from the SkyLight space
        _ = SLSRemoveWindowsFromSpaces(
            connection,
            [window.windowNumber] as CFArray,
            [space] as CFArray
        )
    }
}

final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
}

class NotchPulseSkyLightWindow: NSPanel {
    private var isSkyLightEnabled: Bool = false
    private var observers: Set<AnyCancellable> = []
    
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
        
        configureWindow()
        setupObservers()
    }
    
    private func configureWindow() {
        isFloatingPanel = true
        isOpaque = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        backgroundColor = .clear
        isMovable = false
        isMovableByWindowBackground = false
        level = .mainMenu + 3
        hasShadow = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        
        // Force dark appearance regardless of system setting
        appearance = NSAppearance(named: .darkAqua)
        
        collectionBehavior = [
            .fullScreenAuxiliary,
            .stationary,
            .canJoinAllSpaces,
            .ignoresCycle,
        ]
        
        // Apply initial sharing type setting
        updateSharingType()
    }
    
    private func setupObservers() {
        // Listen for changes to the hideFromScreenRecording setting
        Defaults.publisher(.hideFromScreenRecording)
            .sink { [weak self] _ in
                self?.updateSharingType()
            }
            .store(in: &observers)
    }
    
    private func updateSharingType() {
        if Defaults[.hideFromScreenRecording] {
            sharingType = .none
        } else {
            sharingType = .readWrite
        }
    }
    
    func enableSkyLight() {
        if !isSkyLightEnabled {
            SkyLightOperator.shared.delegateWindow(self)
            isSkyLightEnabled = true
            // Elevate above lock screen media window (CGShieldingWindowLevel + 2) so Face ID is always frontmost
            level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 4)
        }
    }
    
    func disableSkyLight() {
        if isSkyLightEnabled {
            SkyLightOperator.shared.undelegateWindow(self)
            isSkyLightEnabled = false
            level = .mainMenu + 3
        }
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
        FaceIDOverlayController.shared.phase == .onboarding
    }
    override var canBecomeMain: Bool {
        FaceIDOverlayController.shared.phase == .onboarding
    }
}

