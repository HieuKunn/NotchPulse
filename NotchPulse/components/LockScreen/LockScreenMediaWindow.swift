//
//  LockScreenMediaWindow.swift
//  NotchPulse
//
//  Created for NotchPulse v2.0 - Lock Screen & StandBy Window Controller
//

import Cocoa
import Combine
import Defaults
import SkyLightWindow
import SwiftUI

enum LockScreenDisplayMode: Equatable {
    case standby
    case compactMedia
    case fullScreenLyrics
}

@MainActor
final class LockScreenMediaWindow: NSPanel, ObservableObject {
    static let shared = LockScreenMediaWindow()
    
    @Published var displayMode: LockScreenDisplayMode = .standby
    @Published var isFullScreen: Bool = false
    @Published var isWindowVisible: Bool = false
    @Published var isPreviewMode: Bool = false
    
    private var isSkyLightAttached = false
    private var lyricsCancellables = Set<AnyCancellable>()
    
    private init() {
        let initialRect = NSRect(x: 0, y: 0, width: 780, height: 440)
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
        Publishers.CombineLatest3(
            MusicManager.shared.$syncedLyrics,
            MusicManager.shared.$currentLyrics,
            Defaults.publisher(.lockScreenPlayerShowLyrics).map { _ in () }
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _, _, _ in
            guard let self = self, self.isWindowVisible, self.displayMode == .compactMedia, let screen = self.getTargetScreen() else { return }
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
    }
    
    private func getTargetScreen() -> NSScreen? {
        if Defaults[.showOnAllDisplays] {
            return NSScreen.main
                ?? NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })
                ?? NSScreen.screens.first
        }
        if let prefUUID = NotchPulseViewCoordinator.shared.preferredScreenUUID,
           let screen = NSScreen.screen(withUUID: prefUUID) {
            return screen
        }
        return NSScreen.screen(withUUID: NotchPulseViewCoordinator.shared.selectedScreenUUID)
            ?? NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }
    
    func targetStandbyFrame(for screen: NSScreen) -> NSRect {
        let width: CGFloat = 780
        let height: CGFloat = 440
        let x = (screen.frame.width - width) / 2 + screen.frame.origin.x
        let y = screen.frame.origin.y + (screen.frame.height - height) / 2 + 25
        return NSRect(x: x, y: y, width: width, height: height)
    }
    
    func targetCompactFrame(for screen: NSScreen) -> NSRect {
        let width: CGFloat = 420
        let hasLyrics = (!MusicManager.shared.syncedLyrics.isEmpty || !MusicManager.shared.currentLyrics.isEmpty) && Defaults[.lockScreenPlayerShowLyrics]
        let height: CGFloat = hasLyrics ? 218 : 185
        let x = (screen.frame.width - width) / 2 + screen.frame.origin.x
        let y = screen.frame.origin.y + (screen.frame.height * 0.20)
        return NSRect(x: x, y: y, width: width, height: height)
    }
    
    func targetFrame(for screen: NSScreen) -> NSRect {
        switch displayMode {
        case .standby:
            return targetStandbyFrame(for: screen)
        case .compactMedia:
            return targetCompactFrame(for: screen)
        case .fullScreenLyrics:
            return screen.frame
        }
    }
    
    func switchToMode(_ mode: LockScreenDisplayMode) {
        guard let screen = getTargetScreen() else { return }
        self.displayMode = mode
        self.isFullScreen = (mode == .fullScreenLyrics)
        
        let targetRect = targetFrame(for: screen)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.animator().setFrame(targetRect, display: true)
        }
    }
    
    func setFullScreen(_ fullScreen: Bool) {
        switchToMode(fullScreen ? .fullScreenLyrics : (Defaults[.enableLockScreenStandBy] ? .standby : .compactMedia))
    }
    
    func togglePreview() {
        if isPreviewMode && isVisible {
            hide()
            isPreviewMode = false
        } else {
            isPreviewMode = true
            displayMode = .standby
            show()
        }
    }
    
    func show() {
        guard let screen = getTargetScreen() else { return }
        
        if isPreviewMode {
            displayMode = .standby
        } else if !isFullScreen {
            let hasActiveTrack = MusicManager.shared.isPlaying || !MusicManager.shared.songTitle.isEmpty
            if Defaults[.enableLockScreenStandBy] {
                displayMode = .standby
            } else if Defaults[.enableLockScreenPlayer] && hasActiveTrack {
                displayMode = .compactMedia
            }
        }
        
        let targetRect = targetFrame(for: screen)
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
        MusicManager.shared.isUIActive = true
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
            self.isPreviewMode = false
            MusicManager.shared.isUIActive = false
            if self.isSkyLightAttached {
                SkyLightOperator.shared.undelegateWindow(self)
                self.isSkyLightAttached = false
            }
        })
    }
    
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
