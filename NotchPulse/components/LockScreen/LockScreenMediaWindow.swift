//
//  LockScreenMediaWindow.swift
//  NotchPulse
//
//  Created for NotchPulse v2.0 - Lock Screen Media Window Controller
//

import Cocoa
import Combine
import Defaults
import SkyLightWindow
import SwiftUI

@MainActor
final class LockScreenMediaWindow: NSPanel, ObservableObject {
    static let shared = LockScreenMediaWindow()
    
    @Published var isFullScreen: Bool = false
    private var isSkyLightAttached = false
    
    private init() {
        let initialRect = NSRect(x: 0, y: 0, width: 410, height: 180)
        super.init(
            contentRect: initialRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        configureWindow()
    }
    
    private func configureWindow() {
        isFloatingPanel = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        level = .screenSaver
        appearance = NSAppearance(named: .darkAqua)
        
        collectionBehavior = [
            .fullScreenAuxiliary,
            .stationary,
            .canJoinAllSpaces,
            .ignoresCycle
        ]
        
        contentView = NSHostingView(rootView: LockScreenMediaView(windowController: self))
    }
    
    func targetCompactFrame(for screen: NSScreen) -> NSRect {
        let width: CGFloat = 410
        let height: CGFloat = 180
        let x = (screen.frame.width - width) / 2 + screen.frame.origin.x
        let y = screen.frame.origin.y + (screen.frame.height * 0.12)
        return NSRect(x: x, y: y, width: width, height: height)
    }
    
    func setFullScreen(_ fullScreen: Bool) {
        guard let screen = NSScreen.main else { return }
        self.isFullScreen = fullScreen
        
        let targetRect = fullScreen ? screen.frame : targetCompactFrame(for: screen)
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.38
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.animator().setFrame(targetRect, display: true)
        }
    }
    
    func show() {
        guard let screen = NSScreen.main else { return }
        
        let targetRect = isFullScreen ? screen.frame : targetCompactFrame(for: screen)
        setFrame(targetRect, display: true)
        
        if !isSkyLightAttached {
            SkyLightOperator.shared.delegateWindow(self)
            isSkyLightAttached = true
        }
        
        alphaValue = 0
        orderFrontRegardless()
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1.0
        }
    }
    
    func hide() {
        guard isVisible else { return }
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().alphaValue = 0.0
        }, completionHandler: {
            self.orderOut(nil)
            self.isFullScreen = false
            if self.isSkyLightAttached {
                SkyLightOperator.shared.undelegateWindow(self)
                self.isSkyLightAttached = false
            }
        })
    }
    
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
