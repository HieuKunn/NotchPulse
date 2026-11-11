import AppKit
import SwiftUI
import Defaults
import Sparkle

final class SettingsWindow: NSWindow {
    var trafficLightTopInset: CGFloat = 15.0
    var trafficLightLeftInset: CGFloat = 13.0

    override func layoutIfNeeded() {
        super.layoutIfNeeded()
        adjustTrafficLights()
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        adjustTrafficLights()
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool, animate animateFlag: Bool) {
        super.setFrame(frameRect, display: flag, animate: animateFlag)
        adjustTrafficLights()
    }

    override func makeKeyAndOrderFront(_ sender: Any?) {
        super.makeKeyAndOrderFront(sender)
        adjustTrafficLights()
        suppressScrollBars()
    }

    func suppressScrollBars() {
        guard let contentView = self.contentView else { return }
        Self.hideScrollers(in: contentView)
    }

    private static func hideScrollers(in view: NSView) {
        if let scrollView = view as? NSScrollView {
            if !scrollView.hasVerticalScroller { scrollView.hasVerticalScroller = true }
            if !scrollView.autohidesScrollers { scrollView.autohidesScrollers = true }
            if scrollView.scrollerStyle != .overlay { scrollView.scrollerStyle = .overlay }
            if let scroller = scrollView.verticalScroller, (!scroller.isHidden || scroller.alphaValue != 0) {
                scroller.alphaValue = 0
                scroller.isHidden = true
            }
        }
        for subview in view.subviews {
            hideScrollers(in: subview)
        }
    }

    func adjustTrafficLights() {
        let buttons: [(NSWindow.ButtonType, CGFloat)] = [
            (.closeButton, 0),
            (.miniaturizeButton, 23),
            (.zoomButton, 46)
        ]

        for (type, offset) in buttons {
            guard let button = standardWindowButton(type),
                  let superview = button.superview else { continue }
            var f = button.frame
            let newX = trafficLightLeftInset + offset
            let newY = superview.isFlipped ? trafficLightTopInset : (superview.bounds.height - f.height - trafficLightTopInset)
            if abs(f.origin.x - newX) > 0.5 || abs(f.origin.y - newY) > 0.5 {
                f.origin.x = newX
                f.origin.y = newY
                button.setFrameOrigin(f.origin)
            }
        }
    }
}

class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()
    var updaterController: SPUStandardUpdaterController?
    private var vm: NotchPulseViewModel?
    private var isPresented = false
    private var hasInstalledSettingsContent = false
    
    private init() {
        let window = SettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 740, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        super.init(window: window)
        
        configureWindowProperties()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func setUpdaterController(_ controller: SPUStandardUpdaterController, viewModel: NotchPulseViewModel? = nil) {
        self.updaterController = controller
        if let viewModel = viewModel {
            self.vm = viewModel
        }
        // If window is currently open, recreate the content view with the updated controller
        if window?.isVisible == true {
            let settingsView = SettingsView(updaterController: updaterController)
                .environmentObject(self.vm ?? NotchPulseViewModel())
            window?.contentView = NSHostingView(rootView: settingsView)
            hasInstalledSettingsContent = true
        }
    }
    
    private func configureWindowProperties() {
        guard let window = window else { return }
        
        window.title = "NotchPulse Settings"
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titleVisibility = .hidden
        window.toolbarStyle = .unified
        window.isMovableByWindowBackground = false
        
        // Make it behave like a regular app window with proper Spaces support
        window.collectionBehavior = [.managed, .participatesInCycle, .fullScreenAuxiliary]
        
        // Ensure proper window behavior
        window.hidesOnDeactivate = false
        window.isExcludedFromWindowsMenu = false
        
        // Configure window to be a standard document-style window
        window.isRestorable = true
        window.identifier = NSUserInterfaceItemIdentifier("NotchPulseSettingsWindow")
        
        // Handle window closing
        window.delegate = self
    }
    
    func showWindow() {
        guard let window else { return }

        // Reuse the existing hosting hierarchy. Rebuilding the complete
        // NavigationSplitView on every click causes a visible hitch.
        // AppKit creates an empty default content view for NSWindow. Checking
        // only for nil can therefore leave a visible window with traffic
        // lights but no SettingsView mounted inside it.
        if !hasInstalledSettingsContent {
            let settingsView = SettingsView(updaterController: updaterController)
                .environmentObject(vm ?? NotchPulseViewModel())
            window.contentView = NSHostingView(rootView: settingsView)
            hasInstalledSettingsContent = true
        }

        if !window.isVisible {
            window.center()
        }
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }

        // Switching from accessory to regular can complete on the following
        // run-loop turn. Present both immediately and once more afterwards so
        // clicks from a context menu or the notch gear cannot leave a window
        // marked visible but hidden behind another app.
        let activationPolicyChanged = NSApp.activationPolicy() != .regular
        if activationPolicyChanged {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)
        presentWindow(window)
        if activationPolicyChanged {
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window, self.isPresented else { return }
                NSApp.activate(ignoringOtherApps: true)
                self.presentWindow(window)
            }
        }
    }

    private func presentWindow(_ window: NSWindow) {
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        isPresented = true
        (window as? SettingsWindow)?.adjustTrafficLights()
    }
    
    private func relinquishFocus() {
        FaceIDOverlayController.shared.disarm()
        isPresented = false
        
        // Removed: Freeing contentView here causes a white screen bug in macOS when switching app policies.
        // window?.contentView = nil
        
        // Set app back to accessory mode immediately
        NSApp.setActivationPolicy(.accessory)
    }

}

extension SettingsWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        relinquishFocus()
    }
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        return true
    }
    
    func windowDidBecomeKey(_ notification: Notification) {
        // Ensure app is in regular mode when window becomes key
        NSApp.setActivationPolicy(.regular)
    }
    
    func windowDidResignKey(_ notification: Notification) {
    }
    
    func windowDidResize(_ notification: Notification) {
        (window as? SettingsWindow)?.adjustTrafficLights()
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        (window as? SettingsWindow)?.adjustTrafficLights()
    }
}
