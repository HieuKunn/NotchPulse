//
//  SettingsWindowController.swift
//  NotchPulse
//
//  Created by Alexander on 2025-06-14.
//

import AppKit
import SwiftUI
import Defaults
import Sparkle

class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()
    var updaterController: SPUStandardUpdaterController?
    private var vm: NotchPulseViewModel?
    
    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 600),
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
        }
    }
    
    private func configureWindowProperties() {
        guard let window = window else { return }
        
        window.title = "NotchPulse Settings"
        window.titlebarAppearsTransparent = false
        window.titleVisibility = .visible
        window.toolbarStyle = .unified
        window.isMovableByWindowBackground = true
        
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
        // Set app to regular mode first
        NSApp.setActivationPolicy(.regular)
        
        // Lazy-load the SwiftUI view hierarchy only when opening Settings
        if window?.contentView == nil {
            let settingsView = SettingsView(updaterController: updaterController)
                .environmentObject(self.vm ?? NotchPulseViewModel())
            let hostingView = NSHostingView(rootView: settingsView)
            window?.contentView = hostingView
        }
        
        // If window is already visible, bring it to front properly
        if window?.isVisible == true {
            NSApp.activate(ignoringOtherApps: true)
            window?.orderFrontRegardless()
            window?.makeKeyAndOrderFront(nil)
            return
        }
        
        // Show the window with proper ordering
        window?.orderFrontRegardless()
        window?.makeKeyAndOrderFront(nil)
        window?.center()
        
        // Activate the app and ensure window gets focus
        NSApp.activate(ignoringOtherApps: true)
        
        // Force window to front after activation
        DispatchQueue.main.async { [weak self] in
            self?.window?.makeKeyAndOrderFront(nil)
        }
    }
    
    override func close() {
        NotificationCenter.default.post(name: .closeNotchPreview, object: nil)
        super.close()
        relinquishFocus()
    }
    
    private func relinquishFocus() {
        FaceIDManager.shared.cancelCurrentSession()
        window?.orderOut(nil)
        
        // Free entire SettingsView SwiftUI hierarchy and render buffers from RAM
        window?.contentView = nil
        
        // Set app back to accessory mode immediately
        NSApp.setActivationPolicy(.accessory)
    }
}

extension SettingsWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        NotificationCenter.default.post(name: .closeNotchPreview, object: nil)
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
    
}
