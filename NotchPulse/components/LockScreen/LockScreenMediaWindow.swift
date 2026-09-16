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
    @Published var isWindowVisible: Bool = false
    private var isSkyLightAttached = false
    private var lyricsCancellables = Set<AnyCancellable>()
    
    private init() {
        let initialRect = NSRect(x: 0, y: 0, width: 410, height: 180)
        super.init(
            contentRect: initialRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        configureWindow()
        setupLyricsObserver()
    }
    
    private func setupLyricsObserver() {
        Publishers.CombineLatest(MusicManager.shared.$syncedLyrics, MusicManager.shared.$currentLyrics)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in
                guard let self = self, self.isWindowVisible, !self.isFullScreen, let screen = self.getTargetScreen() else { return }
                let newFrame = self.targetCompactFrame(for: screen)
                if abs(self.frame.height - newFrame.height) > 1 {
                    NSAnimationContext.runAnimationGroup { ctx in
                        ctx.duration = 0.25
                        ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                        self.animator().setFrame(newFrame, display: true)
                    }
                }
            }
            .store(in: &lyricsCancellables)
    }
    
    private func configureWindow() {
        isFloatingPanel = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 2)
        acceptsMouseMovedEvents = true
        ignoresMouseEvents = false
        
        collectionBehavior = [
            .fullScreenAuxiliary,
            .stationary,
            .canJoinAllSpaces,
            .ignoresCycle
        ]
        
        // contentView is loaded on-demand in show() and released in hide() to keep idle RAM at 0MB
    }
    
    private func getTargetScreen() -> NSScreen? {
        return NSScreen.screen(withUUID: NotchPulseViewCoordinator.shared.selectedScreenUUID)
            ?? NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }
    
    func targetCompactFrame(for screen: NSScreen) -> NSRect {
        let width: CGFloat = 410
        let hasLyrics = !MusicManager.shared.syncedLyrics.isEmpty || !MusicManager.shared.currentLyrics.isEmpty
        let height: CGFloat = hasLyrics ? 205 : 180
        let x = (screen.frame.width - width) / 2 + screen.frame.origin.x
        let y = screen.frame.origin.y + (screen.frame.height * 0.22)
        return NSRect(x: x, y: y, width: width, height: height)
    }
    
    func setFullScreen(_ fullScreen: Bool) {
        guard let screen = getTargetScreen() else { return }
        self.isFullScreen = fullScreen
        
        let targetRect = fullScreen ? screen.frame : targetCompactFrame(for: screen)
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.38
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.animator().setFrame(targetRect, display: true)
        }
    }
    
    func show() {
        guard let screen = getTargetScreen() else { return }
        
        let targetRect = isFullScreen ? screen.frame : targetCompactFrame(for: screen)
        setFrame(targetRect, display: true)
        
        if contentView == nil {
            let hostingView = NSHostingView(rootView: LockScreenMediaView(windowController: self))
            hostingView.wantsLayer = true
            hostingView.layer?.backgroundColor = NSColor.clear.cgColor
            contentView = hostingView
        }
        
        if !isSkyLightAttached {
            SkyLightOperator.shared.delegateWindow(self)
            isSkyLightAttached = true
        }
        
        if !isVisible || alphaValue == 0 {
            alphaValue = 0
            orderFrontRegardless()
            
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.35
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.animator().alphaValue = 1.0
            }
        } else {
            orderFrontRegardless()
        }
        isWindowVisible = true
        MusicManager.shared.ensureLyricsLoaded()
    }
    
    func hide() {
        guard isVisible else { return }
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().alphaValue = 0.0
        }, completionHandler: {
            self.orderOut(nil)
            self.contentView = nil
            self.isFullScreen = false
            self.isWindowVisible = false
            if self.isSkyLightAttached {
                SkyLightOperator.shared.undelegateWindow(self)
                self.isSkyLightAttached = false
            }
        })
    }
    
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
