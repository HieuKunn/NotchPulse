import Cocoa
import Combine
import Defaults
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
    private var assignedScreenUUID: String?
    private var lockReassertionTask: Task<Void, Never>?
    private var hasInstalledPlayerView = false
    private var backdropWindows: [String: NSWindow] = [:]
    
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
            guard let self = self, self.isWindowVisible, !self.isFullScreen else { return }
            self.checkAndRepositionIfNeeded(animated: true)
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
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 5)
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
                self?.assignedScreenUUID = nil
                self?.syncTheme()
                self?.checkAndRepositionIfNeeded(animated: false)
                self?.updateBackdropWindowsIfNeeded()
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: Notification.Name.selectedScreenChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.assignedScreenUUID = nil
                self?.checkAndRepositionIfNeeded(animated: true)
                self?.updateBackdropWindowsIfNeeded()
            }
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name.showOnAllDisplaysChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.assignedScreenUUID = nil
                self?.checkAndRepositionIfNeeded(animated: true)
                self?.updateBackdropWindowsIfNeeded()
            }
        }
        
        syncTheme()
    }
    
    private func resolveInitialScreen() -> NSScreen? {
        // 1. Khi tuỳ chọn "Hiển thị trên mọi màn hình" được bật:
        // Luôn hiển thị theo Main Display của hệ thống macOS đã set
        if Defaults[.showOnAllDisplays] {
            return NSScreen.screens.first ?? NSScreen.main
        }
        
        // 2. Khi người dùng chọn một màn hình cụ thể trong Cài đặt (preferredScreenUUID / selectedScreenUUID):
        // Luôn hiển thị theo màn hình được chọn, bất kể trước đó chuột đang active ở màn hình nào
        if let prefUUID = NotchPulseViewCoordinator.shared.preferredScreenUUID,
           let screen = NSScreen.screen(withUUID: prefUUID) {
            return screen
        }
        let selectedUUID = NotchPulseViewCoordinator.shared.selectedScreenUUID
        if !selectedUUID.isEmpty, let screen = NSScreen.screen(withUUID: selectedUUID) {
            return screen
        }
        
        // 3. Fallback an toàn nếu màn hình được chọn bị rút cáp hoặc không khả dụng
        return NSScreen.screens.first ?? NSScreen.main
    }
    
    private func getTargetScreen() -> NSScreen? {
        // Luôn resolve theo đúng màn hình được chỉ định trong cài đặt hoặc main display
        let resolved = resolveInitialScreen()
        assignedScreenUUID = resolved?.displayUUID
        return resolved
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
    
    func checkAndRepositionIfNeeded(animated: Bool = true) {
        guard isWindowVisible, let targetScreen = getTargetScreen() else { return }
        
        let targetRect = targetFrame(for: targetScreen)
        
        let frameDiffX = abs(self.frame.origin.x - targetRect.origin.x)
        let frameDiffY = abs(self.frame.origin.y - targetRect.origin.y)
        let frameDiffW = abs(self.frame.width - targetRect.width)
        let frameDiffH = abs(self.frame.height - targetRect.height)
        
        let currentScreen = self.screen ?? NSScreen.screens.first(where: { $0.frame.intersects(self.frame) })
        let isDifferentScreen = (currentScreen != targetScreen)
        
        if isDifferentScreen || !animated || frameDiffX > 1 || frameDiffY > 1 || frameDiffW > 1 || frameDiffH > 1 {
            if isDifferentScreen || !animated {
                setFrame(targetRect, display: true)
            } else {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.25
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    self.animator().setFrame(targetRect, display: true)
                }
            }
        }
        if let skyLight = FaceIDOverlaySkyLight.shared {
            skyLight.delegate(self)
        }
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 5)
        alphaValue = 1.0
        orderFrontRegardless()
        
        updateBackdropWindowsIfNeeded()
    }
    
    // =========================================================================
    // MARK: - Multi-Display Fullscreen Ambient Backdrops
    // =========================================================================
    
    private func showBackdrops(targetScreen: NSScreen) {
        let otherScreens = NSScreen.screens.filter { $0.displayUUID != targetScreen.displayUUID }
        var activeUUIDs = Set<String>()
        
        for screen in otherScreens {
            guard let uuid = screen.displayUUID else { continue }
            activeUUIDs.insert(uuid)
            
            let backdrop: NSWindow
            if let existing = backdropWindows[uuid] {
                backdrop = existing
                if backdrop.frame != screen.frame {
                    backdrop.setFrame(screen.frame, display: true)
                }
            } else {
                backdrop = NSWindow(
                    contentRect: screen.frame,
                    styleMask: [.borderless, .nonactivatingPanel],
                    backing: .buffered,
                    defer: false
                )
                backdrop.setFrame(screen.frame, display: true)
                backdrop.isOpaque = false
                backdrop.backgroundColor = .clear
                backdrop.hasShadow = false
                backdrop.ignoresMouseEvents = true
                backdrop.isMovable = false
                backdrop.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 4)
                backdrop.collectionBehavior = [
                    .fullScreenAuxiliary,
                    .stationary,
                    .canJoinAllSpaces,
                    .ignoresCycle
                ]
                let hostingView = FirstMouseHostingView(rootView: LockScreenMediaBackdropView())
                hostingView.wantsLayer = true
                hostingView.layer?.backgroundColor = NSColor.clear.cgColor
                backdrop.contentView = hostingView
                backdropWindows[uuid] = backdrop
            }
            
            if let skyLight = FaceIDOverlaySkyLight.shared {
                skyLight.delegate(backdrop)
            }
            
            backdrop.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 4)
            backdrop.orderFrontRegardless()
            
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.35
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                backdrop.animator().alphaValue = 1.0
            }
        }
        
        // Gỡ bỏ cửa sổ nền của các màn hình đã bị ngắt kết nối
        for (uuid, window) in backdropWindows where !activeUUIDs.contains(uuid) {
            FaceIDOverlaySkyLight.shared?.undelegate(window)
            window.orderOut(nil)
            backdropWindows.removeValue(forKey: uuid)
        }
    }
    
    private func hideBackdrops(immediately: Bool = false) {
        guard !backdropWindows.isEmpty else { return }
        let windowsToDismiss = backdropWindows
        backdropWindows.removeAll()
        
        if immediately {
            for (_, window) in windowsToDismiss {
                FaceIDOverlaySkyLight.shared?.undelegate(window)
                window.alphaValue = 0.0
                window.orderOut(nil)
            }
            return
        }
        
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            for (_, window) in windowsToDismiss {
                window.animator().alphaValue = 0.0
            }
        }, completionHandler: {
            for (_, window) in windowsToDismiss {
                FaceIDOverlaySkyLight.shared?.undelegate(window)
                window.orderOut(nil)
            }
        })
    }
    
    private func updateBackdropWindowsIfNeeded() {
        guard isWindowVisible, isFullScreen, let targetScreen = getTargetScreen() else {
            if !isFullScreen {
                hideBackdrops(immediately: true)
            }
            return
        }
        showBackdrops(targetScreen: targetScreen)
    }
    
    func setFullScreen(_ fullScreen: Bool) {
        guard let screen = getTargetScreen() else { return }
        self.isFullScreen = fullScreen
        if fullScreen {
            MusicManager.shared.ensureArtworkLoaded()
            showBackdrops(targetScreen: screen)
        } else {
            hideBackdrops()
        }
        
        let targetRect = targetFrame(for: screen)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.animator().setFrame(targetRect, display: true)
        }
    }
    
    func show() {
        guard let screen = getTargetScreen() else { return }
        
        // Sync system appearance (Dark Mode vs Light Mode)
        syncTheme()
        
        if !hasInstalledPlayerView {
            let hostingView = FirstMouseHostingView(rootView: LockScreenMediaView(windowController: self))
            hostingView.wantsLayer = true
            hostingView.layer?.backgroundColor = NSColor.clear.cgColor
            contentView = hostingView
            hasInstalledPlayerView = true
        }
        
        hideGeneration += 1
        let targetRect = targetFrame(for: screen)
        setFrame(targetRect, display: true)
        contentView?.layoutSubtreeIfNeeded()
        displayIfNeeded()
        
        if let skyLight = FaceIDOverlaySkyLight.shared {
            skyLight.delegate(self)
            isSkyLightAttached = true
        }
        
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 5)
        self.alphaValue = 1.0
        orderFrontRegardless()
        isWindowVisible = true
        
        MusicManager.shared.isUIActive = true
        MusicManager.shared.ensureLyricsLoaded()
        MusicManager.shared.ensureArtworkLoaded()
        
        lockReassertionTask?.cancel()
        lockReassertionTask = Task { @MainActor [weak self] in
            for delayMs in [150, 350, 650, 1000] {
                try? await Task.sleep(for: .milliseconds(delayMs))
                guard let self = self, !Task.isCancelled, self.isWindowVisible else { break }
                if let skyLight = FaceIDOverlaySkyLight.shared {
                    skyLight.delegate(self)
                    if self.isFullScreen {
                        for (_, backdrop) in self.backdropWindows {
                            skyLight.delegate(backdrop)
                        }
                    }
                }
                self.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 5)
                self.orderFrontRegardless()
                if self.isFullScreen {
                    for (_, backdrop) in self.backdropWindows {
                        backdrop.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 4)
                        backdrop.orderFrontRegardless()
                    }
                }
            }
        }
    }
    
    private func finalizeHide() {
        lockReassertionTask?.cancel()
        lockReassertionTask = nil
        hideBackdrops(immediately: true)
        self.orderOut(nil)
        self.isFullScreen = false
        self.isWindowVisible = false
        MusicManager.shared.isUIActive = false
        if let screen = NSScreen.main {
            self.setFrame(self.targetCompactFrame(for: screen), display: false)
        }
        if self.isSkyLightAttached {
            FaceIDOverlaySkyLight.shared?.undelegate(self)
            self.isSkyLightAttached = false
        }
    }

    func hide(immediately: Bool = false) {
        guard isVisible || isWindowVisible else { return }
        hideGeneration += 1
        let currentGen = hideGeneration
        assignedScreenUUID = nil
        
        if immediately {
            self.alphaValue = 0.0
            hideBackdrops(immediately: true)
            finalizeHide()
            return
        }
        
        self.isWindowVisible = false
        MusicManager.shared.isUIActive = false
        hideBackdrops(immediately: false)
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.hideGeneration == currentGen else { return }
                self.finalizeHide()
            }
        })
    }
    
    func hideImmediately() {
        hide(immediately: true)
    }
    
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
