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
    @Published var isLightMode: Bool = !LockScreenMediaWindow.detectIsDark()
    
    private var isSkyLightAttached = false
    private var lyricsCancellables = Set<AnyCancellable>()
    private var hideGeneration: Int = 0
    
    static func detectIsDark() -> Bool {
        if let style = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") {
            return style.caseInsensitiveCompare("Dark") == .orderedSame
        }
        return NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
    
    func syncTheme() {
        let isDark = Self.detectIsDark()
        let newIsLight = !isDark
        if self.isLightMode != newIsLight {
            self.isLightMode = newIsLight
        }
        let targetAppearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        if self.appearance != targetAppearance {
            self.appearance = targetAppearance
        }
    }
    
    static let compactCardWidth: CGFloat = 420
    static let compactWindowPadding: CGFloat = 0
    
    private init() {
        let initialWidth = Self.compactCardWidth
        let initialHeight: CGFloat = 190
        let initialRect = NSRect(x: 0, y: 0, width: initialWidth, height: initialHeight)
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
        hidesOnDeactivate = false
        canHide = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 3)
        acceptsMouseMovedEvents = true
        ignoresMouseEvents = false
        
        collectionBehavior = [
            .fullScreenAuxiliary,
            .stationary,
            .canJoinAllSpaces,
            .ignoresCycle
        ]
        
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.syncTheme()
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.syncTheme()
            }
        }
        
        syncTheme()
    }
    
    private func getTargetScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        if let cursorScreen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) {
            return cursorScreen
        }
        if Defaults[.showOnAllDisplays] {
            return NSScreen.main
                ?? NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 || $0.auxiliaryTopLeftArea != nil })
                ?? NSScreen.screens.first
        }
        if let prefUUID = NotchPulseViewCoordinator.shared.preferredScreenUUID,
           let screen = NSScreen.screen(withUUID: prefUUID) {
            return screen
        }
        return NSScreen.screen(withUUID: NotchPulseViewCoordinator.shared.selectedScreenUUID)
            ?? NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 || $0.auxiliaryTopLeftArea != nil })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }
    
    func targetCompactFrame(for screen: NSScreen) -> NSRect {
        let hasLyrics = (!MusicManager.shared.syncedLyrics.isEmpty || !MusicManager.shared.currentLyrics.isEmpty) && Defaults[.lockScreenPlayerShowLyrics]
        let cardHeight: CGFloat = hasLyrics ? 228 : 190
        let totalWidth = Self.compactCardWidth
        let totalHeight = cardHeight
        let x = (screen.frame.width - totalWidth) / 2 + screen.frame.origin.x
        let y = screen.frame.origin.y + (screen.frame.height * 0.20)
        return NSRect(x: x, y: y, width: totalWidth, height: totalHeight)
    }
    
    func targetFrame(for screen: NSScreen) -> NSRect {
        if isFullScreen {
            return screen.frame
        } else {
            return targetCompactFrame(for: screen)
        }
    }
    
    func setFullScreen(_ fullScreen: Bool) {
        guard let screen = getTargetScreen() else { return }
        self.isFullScreen = fullScreen
        
        let targetRect = targetFrame(for: screen)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.animator().setFrame(targetRect, display: true)
        }
    }
    
    func show() {
        hideGeneration += 1
        
        guard let screen = getTargetScreen() else { return }
        
        // Sync system appearance (Dark Mode vs Light Mode)
        syncTheme()
        
        if contentView == nil {
            let hostingView = FirstMouseHostingView(rootView: LockScreenMediaView(windowController: self))
            hostingView.wantsLayer = true
            hostingView.layer?.backgroundColor = NSColor.clear.cgColor
            contentView = hostingView
        }
        
        let targetRect = targetFrame(for: screen)
        setFrame(targetRect, display: true)
        
        if !isSkyLightAttached {
            SkyLightOperator.shared.delegateWindow(self)
            isSkyLightAttached = true
        }
        
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 3)
        self.alphaValue = 1.0
        orderFrontRegardless()
        isWindowVisible = true
        MusicManager.shared.isUIActive = true
        MusicManager.shared.ensureLyricsLoaded()
    }
    
    func hide() {
        guard isVisible || isWindowVisible else { return }
        hideGeneration += 1
        let currentGen = hideGeneration
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            guard let self = self, self.hideGeneration == currentGen else { return }
            self.orderOut(nil)
            self.contentView = nil
            self.isFullScreen = false
            self.isWindowVisible = false
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
