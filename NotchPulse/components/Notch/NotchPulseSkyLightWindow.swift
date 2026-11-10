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
    required init(rootView: Content) {
        super.init(rootView: rootView)
        self.wantsLayer = true
    }

    @MainActor required dynamic init?(coder: NSCoder) {
        super.init(coder: coder)
        self.wantsLayer = true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
}

class NotchPulseSkyLightWindow: NSPanel {
    private var isSkyLightEnabled: Bool = false
    private var isFileDragElevated: Bool = false
    private var observers: Set<AnyCancellable> = []

    private var restingLevel: NSWindow.Level {
        // Notch sits below pop-up menus and system context menus (NSWindow.Level.statusBar + 1 = 26)
        NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
    }
    
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
        level = restingLevel
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

        // Lower window level below context menu during tracking to prevent obscuring popups
        MenuTrackingManager.shared.$isMenuTracking
            .sink { [weak self] isTracking in
                guard let self = self, !self.isFileDragElevated else { return }
                if isTracking {
                    self.level = NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue + 1)
                } else {
                    self.level = self.restingLevel
                }
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
            if !isFileDragElevated {
                level = restingLevel
            }
        }
    }
    
    func disableSkyLight() {
        if isSkyLightEnabled {
            SkyLightOperator.shared.undelegateWindow(self)
            isSkyLightEnabled = false
            if !isFileDragElevated {
                level = restingLevel
            }
        }
    }

    /// Keeps the drop destination above the source app and Desktop while an
    /// external file drag is active, elevated above popUpMenu so drag overlays and drop targets are topmost.
    func beginFileDragTargeting() {
        isFileDragElevated = true
        level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
        orderFrontRegardless()
    }

    func endFileDragTargeting() {
        guard isFileDragElevated else { return }
        isFileDragElevated = false
        level = restingLevel
        orderFrontRegardless()
    }
    
    // MARK: - Position Safety

    override func center() {
        guard let screen = self.screen ?? NSScreen.main else { return }
        super.setFrameOrigin(NSPoint(x: screen.frame.midX - frame.width / 2, y: screen.frame.maxY - frame.height))
    }

    override var canBecomeKey: Bool {
        FaceIDOverlayController.shared.phase == .onboarding
    }
    override var canBecomeMain: Bool {
        FaceIDOverlayController.shared.phase == .onboarding
    }
}

