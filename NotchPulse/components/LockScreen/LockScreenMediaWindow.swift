//
//  LockScreenMediaWindow.swift
//  NotchPulse
//
//  Created for NotchPulse v2.0 - Lock Screen Media Window Controller
//

import Cocoa
import Defaults
import SkyLightWindow
import SwiftUI

@MainActor
final class LockScreenMediaWindow: NSPanel {
    static let shared = LockScreenMediaWindow()
    
    private var isSkyLightAttached = false
    
    private init() {
        let initialRect = NSRect(x: 0, y: 0, width: 720, height: 250)
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
        
        contentView = NSHostingView(rootView: LockScreenMediaView())
    }
    
    func show() {
        guard let screen = NSScreen.main else { return }
        
        let showLyrics = Defaults[.lockScreenPlayerShowLyrics]
        let width: CGFloat = showLyrics ? 720 : 460
        let height: CGFloat = 250
        
        // Position gracefully in the lower third / center of the screen
        let x = (screen.frame.width - width) / 2 + screen.frame.origin.x
        let y = screen.frame.origin.y + (screen.frame.height * 0.16)
        
        setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        
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
            if self.isSkyLightAttached {
                SkyLightOperator.shared.undelegateWindow(self)
                self.isSkyLightAttached = false
            }
        })
    }
    
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
