//
//  NotchPulseApp.swift
//  NotchPulseApp
//
//  Created by Harsh Vardhan  Goswami  on 02/08/24.
//

import AVFoundation
import Combine
import Defaults
import KeyboardShortcuts
import Sparkle
import SwiftUI

@main
struct DynamicNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Default(.menubarIcon) var showMenuBarIcon
    @Environment(\.openWindow) var openWindow

    let updaterController: SPUStandardUpdaterController

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: AppUpdaterDelegate.shared, userDriverDelegate: nil)

        // Initialize the settings window controller with the updater controller
        SettingsWindowController.shared.setUpdaterController(updaterController)
    }

    var body: some Scene {
        MenuBarExtra("NotchPulse", systemImage: "sparkle", isInserted: $showMenuBarIcon) {
            Button("Settings") {
                DispatchQueue.main.async {
                    SettingsWindowController.shared.showWindow()
                }
            }
            .keyboardShortcut(KeyEquivalent(","), modifiers: .command)
            
            Menu("Notch Width (\(Int(Defaults[.notchOpenWidth]))px)") {
                Button("Compact (580px)") { Defaults[.notchOpenWidth] = 580 }
                Button("Standard (740px)") { Defaults[.notchOpenWidth] = 740 }
                Button("Wide (860px)") { Defaults[.notchOpenWidth] = 860 }
                Button("Extra Wide (940px)") { Defaults[.notchOpenWidth] = 940 }
                Divider()
                Button("Custom Dimensions...") {
                    DispatchQueue.main.async {
                        SettingsWindowController.shared.showWindow()
                    }
                }
            }
            
            CheckForUpdatesView(updater: updaterController.updater)
            Divider()
            Button("Restart NotchPulse") {
                ApplicationRelauncher.restart()
            }
            Button("Quit", role: .destructive) {
                appDelegate.quitApplication()
            }
            .keyboardShortcut(KeyEquivalent("q"), modifiers: .command)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var windows: [String: NSWindow] = [:] // UUID -> NSWindow
    var viewModels: [String: NotchPulseViewModel] = [:] // UUID -> NotchPulseViewModel
    var window: NSWindow?
    let vm: NotchPulseViewModel = .init()
    @ObservedObject var coordinator = NotchPulseViewCoordinator.shared
    var quickShareService = QuickShareService.shared
    var whatsNewWindow: NSWindow?
    var timer: Timer?
    var closeNotchTask: Task<Void, Never>?
    private var previousScreens: [NSScreen]?
    private var onboardingWindowController: NSWindowController?
    private var screenLockedObserver: Any?
    private var screenUnlockedObserver: Any?
    private var isScreenLocked: Bool = false
    private var windowScreenDidChangeObserver: Any?
    private var dragDetectors: [String: DragDetector] = [:] // UUID -> DragDetector
    private var dragExitDebounceTasks: [String: Task<Void, Never>] = [:]

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        quitApplication()
        return .terminateNow
    }

    @MainActor
    func quitApplication() {
        NSApplication.shared.windows.forEach { $0.orderOut(nil) }
        cleanupWindows()
        cleanupDragDetectors()
        FaceIDOverlayController.shared.disarm()
        LockScreenFaceIDWindow.shared.orderOut(nil)
        LockScreenMediaWindow.shared.orderOut(nil)
        MusicManager.shared.destroy()
        exit(0)
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
        if let observer = screenLockedObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            screenLockedObserver = nil
        }
        if let observer = screenUnlockedObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            screenUnlockedObserver = nil
        }
        cleanupDragDetectors()
        cleanupWindows()
        MusicManager.shared.destroy()
        XPCHelperClient.shared.stopMonitoringAccessibilityAuthorization()
        LockScreenWakeObserver.shared.cleanup()
        SystemAuthPromptObserver.shared.cleanup()
    }

    @MainActor
    func onScreenLocked(_ notification: Notification) {
        isScreenLocked = true
        let shouldKeepWindow = Defaults[.showOnLockScreen] || NotchPulseFaceIDSettings.shared.isFaceUnlockEnabled
        if !shouldKeepWindow {
            cleanupWindows()
        } else {
            enableSkyLightOnAllWindows()
        }
    }

    @MainActor
    func onScreenUnlocked(_ notification: Notification) {
        isScreenLocked = false
        let shouldKeepWindow = Defaults[.showOnLockScreen] || NotchPulseFaceIDSettings.shared.isFaceUnlockEnabled
        if !shouldKeepWindow {
            adjustWindowPosition(changeAlpha: true)
        } else {
            disableSkyLightOnAllWindows()
        }
    }
    
    @MainActor
    private func enableSkyLightOnAllWindows() {
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            await MainActor.run {
                if Defaults[.showOnAllDisplays] {
                    self.windows.values.forEach { window in
                        if let skyWindow = window as? NotchPulseSkyLightWindow {
                            skyWindow.enableSkyLight()
                        }
                    }
                } else {
                    if let skyWindow = self.window as? NotchPulseSkyLightWindow {
                        skyWindow.enableSkyLight()
                    }
                }
            }
        }
    }
    
    @MainActor
    private func disableSkyLightOnAllWindows() {
        // Delay disabling SkyLight to avoid flicker during unlock transition
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            await MainActor.run {
                if Defaults[.showOnAllDisplays] {
                    self.windows.values.forEach { window in
                        if let skyWindow = window as? NotchPulseSkyLightWindow {
                            skyWindow.disableSkyLight()
                        }
                    }
                } else {
                    if let skyWindow = self.window as? NotchPulseSkyLightWindow {
                        skyWindow.disableSkyLight()
                    }
                }
            }
        }
    }

    private func cleanupWindows(shouldInvert: Bool = false) {
        let shouldCleanupMulti = shouldInvert ? !Defaults[.showOnAllDisplays] : Defaults[.showOnAllDisplays]
        
        if shouldCleanupMulti {
            windows.values.forEach { window in
                window.close()
                NotchSpaceManager.shared.notchSpace.windows.remove(window)
            }
            windows.removeAll()
            viewModels.removeAll()
        } else if let window = window {
            window.close()
            NotchSpaceManager.shared.notchSpace.windows.remove(window)
            if let obs = windowScreenDidChangeObserver {
                NotificationCenter.default.removeObserver(obs)
                windowScreenDidChangeObserver = nil
            }
            self.window = nil
        }
    }

    private func cleanupDragDetectors() {
        dragExitDebounceTasks.values.forEach { $0.cancel() }
        dragExitDebounceTasks.removeAll()
        dragDetectors.values.forEach { detector in
            detector.stopMonitoring()
        }
        dragDetectors.removeAll()
    }

    private func setupDragDetectors() {
        cleanupDragDetectors()

        guard Defaults[.expandedDragDetection] else { return }

        if Defaults[.showOnAllDisplays] {
            for screen in NSScreen.screens {
                setupDragDetectorForScreen(screen)
            }
        } else {
            let preferredScreen: NSScreen? = (coordinator.preferredScreenUUID.flatMap({ NSScreen.screen(withUUID: $0) }))
                ?? NSScreen.screen(withUUID: coordinator.selectedScreenUUID)
                ?? window?.screen
                ?? NSScreen.main
                ?? NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })
                ?? NSScreen.screens.first

            if let screen = preferredScreen {
                setupDragDetectorForScreen(screen)
            }
        }
    }

    private func setupDragDetectorForScreen(_ screen: NSScreen) {
        guard let uuid = screen.displayUUID else { return }
        
        let detector = DragDetector { [weak self] in
            guard let self = self else { return .zero }
            let screenFrame = screen.frame
            let targetVM = (Defaults[.showOnAllDisplays] ? self.viewModels[uuid] : nil) ?? self.vm
            let padding = CGFloat(Defaults[.dragDetectionPadding])
            
            let isDynamicIsland = Defaults[.notchStyle] == .dynamicIsland
            let hasPhysicalNotch = screen.safeAreaInsets.top > 0 || screen.auxiliaryTopLeftArea != nil
            let topOffset = (isDynamicIsland && !hasPhysicalNotch) ? Defaults[.dynamicIslandTopOffset] : 0
            
            if targetVM.notchState == .open {
                // When open, the region covers the ENTIRE open shelf plus expansion padding
                let openWidth = max(targetVM.notchSize.width, max(openNotchSize.width, CGFloat(Defaults[.notchOpenWidth])))
                let openHeight = max(targetVM.notchSize.height, openNotchSize.height)
                return CGRect(
                    x: screenFrame.midX - (openWidth / 2 + padding),
                    y: screenFrame.maxY - (openHeight + padding + topOffset),
                    width: openWidth + (padding * 2),
                    height: openHeight + padding + topOffset + 30
                )
            } else {
                // When closed, the region radiates outwards and downwards from the closed notch by the user's padding
                let closedSize = targetVM.closedNotchSize
                let closedWidth = isDynamicIsland ? 210.0 : (closedSize.width > 0 ? closedSize.width : 185.0)
                let closedHeight = isDynamicIsland ? 32.0 : (closedSize.height > 0 ? closedSize.height : 36.0)
                return CGRect(
                    x: screenFrame.midX - (closedWidth / 2 + padding),
                    y: screenFrame.maxY - (closedHeight + padding + topOffset),
                    width: closedWidth + (padding * 2),
                    height: closedHeight + padding + topOffset + 30
                )
            }
        }
        
        detector.onDragEntersNotchRegion = { [weak self] in
            Task { @MainActor in
                self?.handleDragEntersNotchRegion(onScreen: screen)
            }
        }

        detector.onDragExitsNotchRegion = { [weak self] in
            Task { @MainActor in
                self?.handleDragExitsNotchRegion(onScreen: screen)
            }
        }

        detector.onDragEnded = { [weak self] in
            Task { @MainActor in
                self?.handleDragEnded(onScreen: screen)
            }
        }
        
        dragDetectors[uuid] = detector
        detector.startMonitoring()
    }

    private func handleDragEntersNotchRegion(onScreen screen: NSScreen) {
        guard let uuid = screen.displayUUID else { return }
        
        dragExitDebounceTasks[uuid]?.cancel()
        dragExitDebounceTasks[uuid] = nil
        
        SharingStateManager.shared.preventNotchClose = true
        
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            if Defaults[.showOnAllDisplays], let viewModel = viewModels[uuid] {
                viewModel.open()
            } else {
                vm.open()
            }
            coordinator.currentView = .shelf
        }
    }

    private func handleDragExitsNotchRegion(onScreen screen: NSScreen) {
        guard let uuid = screen.displayUUID else { return }
        
        dragExitDebounceTasks[uuid]?.cancel()
        dragExitDebounceTasks[uuid] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self = self else { return }
            
            let targetVM = (Defaults[.showOnAllDisplays] ? self.viewModels[uuid] : nil) ?? self.vm
            guard !targetVM.anyDropZoneTargeting && !targetVM.dropEvent else { return }
            
            SharingStateManager.shared.preventNotchClose = false
            if !ShelfStateViewModel.shared.isPinned && targetVM.notchState == .open {
                targetVM.close()
            }
        }
    }

    private func handleDragEnded(onScreen screen: NSScreen) {
        guard let uuid = screen.displayUUID else { return }
        
        dragExitDebounceTasks[uuid]?.cancel()
        dragExitDebounceTasks[uuid] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self = self else { return }
            
            let targetVM = (Defaults[.showOnAllDisplays] ? self.viewModels[uuid] : nil) ?? self.vm
            guard !targetVM.anyDropZoneTargeting && !targetVM.dropEvent else { return }
            
            SharingStateManager.shared.preventNotchClose = false
            if !ShelfStateViewModel.shared.isPinned && targetVM.notchState == .open {
                targetVM.close()
            }
        }
    }

    private func createNotchPulseWindow(for screen: NSScreen, with viewModel: NotchPulseViewModel) -> NSWindow {
        let rect = NSRect(x: 0, y: 0, width: windowSize.width, height: windowSize.height)
        let styleMask: NSWindow.StyleMask = [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow]
        
        let window = NotchPulseSkyLightWindow(contentRect: rect, styleMask: styleMask, backing: .buffered, defer: false)
        
        // Enable SkyLight only when screen is locked
        if isScreenLocked {
            window.enableSkyLight()
        } else {
            window.disableSkyLight()
        }

        window.contentView = NSHostingView(
            rootView: ContentView()
                .environmentObject(viewModel)
        )

        window.orderFrontRegardless()
        NotchSpaceManager.shared.notchSpace.windows.insert(window)

        // Observe when the window's screen changes so we can update drag detectors
        windowScreenDidChangeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeScreenNotification,
            object: window,
            queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.setupDragDetectors()
                }
        }
        return window
    }

    @MainActor
    private func positionWindow(_ window: NSWindow, on screen: NSScreen, changeAlpha: Bool = false) {
        if changeAlpha {
            window.alphaValue = 0
        }

        let screenFrame = screen.frame
        window.setFrameOrigin(
            NSPoint(
                x: screenFrame.origin.x + (screenFrame.width / 2) - window.frame.width / 2,
                y: screenFrame.origin.y + screenFrame.height - window.frame.height
            ))
        window.alphaValue = 1
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        FaceIDScanAnimationHostView.prewarm()

        // Configure main menu with native Quit item so Cmd+Q works system-wide
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu(title: "NotchPulse")
        appMenuItem.submenu = appMenu
        let quitMenuItem = NSMenuItem(
            title: "Quit NotchPulse",
            action: #selector(quitAction),
            keyEquivalent: "q"
        )
        appMenu.addItem(quitMenuItem)
        NSApplication.shared.mainMenu = mainMenu

        // Also intercept local Cmd+Q keyDown events directly
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers?.lowercased() == "q" {
                self?.quitApplication()
                return nil
            }
            return event
        }

        if let updater = SettingsWindowController.shared.updaterController {
            SettingsWindowController.shared.setUpdaterController(updater, viewModel: self.vm)
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenConfigurationDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            forName: Notification.Name.selectedScreenChanged, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.adjustWindowPosition(changeAlpha: true)
                self?.setupDragDetectors()
            }
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name.notchHeightChanged, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.adjustWindowPosition()
                self?.setupDragDetectors()
            }
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name.automaticallySwitchDisplayChanged, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.adjustWindowPosition(changeAlpha: true)
                self?.setupDragDetectors()
            }
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name.showOnAllDisplaysChanged, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.cleanupWindows(shouldInvert: true)
                self.adjustWindowPosition(changeAlpha: true)
                self.setupDragDetectors()
            }
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name.expandedDragDetectionChanged, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.setupDragDetectors()
            }
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name.previewNotchWidth, object: nil, queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            let width = (notification.object as? CGFloat) ?? Defaults[.notchOpenWidth]
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                self.vm.open()
                self.vm.notchSize = CGSize(width: width, height: openNotchSize.height)
                for (_, subVm) in self.viewModels {
                    subVm.open()
                    subVm.notchSize = CGSize(width: width, height: openNotchSize.height)
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name.closeNotchPreview, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            withAnimation(.spring(response: 0.45, dampingFraction: 1.0)) {
                self.vm.close()
                for (_, subVm) in self.viewModels {
                    subVm.close()
                }
            }
        }

        // Use closure-based observers for DistributedNotificationCenter and keep tokens for removal
        screenLockedObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(rawValue: "com.apple.screenIsLocked"),
            object: nil, queue: .main) { [weak self] notification in
                Task { @MainActor in
                    self?.onScreenLocked(notification)
                }
        }

        screenUnlockedObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(rawValue: "com.apple.screenIsUnlocked"),
            object: nil, queue: .main) { [weak self] notification in
                Task { @MainActor in
                    self?.onScreenUnlocked(notification)
                }
        }

        KeyboardShortcuts.onKeyDown(for: .toggleSneakPeek) { [weak self] in
            guard let self = self else { return }
            if Defaults[.sneakPeekStyles] == .inline {
                let newStatus = !self.coordinator.expandingView.show
                self.coordinator.toggleExpandingView(status: newStatus, type: .music)
            } else {
                self.coordinator.toggleSneakPeek(
                    status: !self.coordinator.sneakPeek.show,
                    type: .music,
                    duration: 3.0
                )
            }
        }

        KeyboardShortcuts.onKeyDown(for: .toggleNotchOpen) { [weak self] in
            Task { [weak self] in
                guard let self = self else { return }

                let mouseLocation = NSEvent.mouseLocation

                var viewModel = self.vm

                if Defaults[.showOnAllDisplays] {
                    for screen in NSScreen.screens {
                        if screen.frame.contains(mouseLocation) {
                            if let uuid = screen.displayUUID, let screenViewModel = self.viewModels[uuid] {
                                viewModel = screenViewModel
                                break
                            }
                        }
                    }
                }

                self.closeNotchTask?.cancel()
                self.closeNotchTask = nil

                switch viewModel.notchState {
                case .closed:
                    await MainActor.run {
                        viewModel.open()
                    }

                    let task = Task { [weak viewModel] in
                        do {
                            try await Task.sleep(for: .seconds(3))
                            await MainActor.run {
                                viewModel?.close()
                            }
                        } catch { }
                    }
                    self.closeNotchTask = task
                case .open:
                    await MainActor.run {
                        viewModel.close()
                    }
                }
            }
        }

        KeyboardShortcuts.onKeyDown(for: .faceIDQuickAuth) {
            NotchPulseSystemAuthCoordinator.shared.triggerQuickAuth()
        }

        if !Defaults[.showOnAllDisplays] {
            let preferredUUID = coordinator.preferredScreenUUID
            let initialScreen: NSScreen? = (preferredUUID.flatMap { NSScreen.screen(withUUID: $0) })
                ?? NSScreen.screen(withUUID: coordinator.selectedScreenUUID)
                ?? NSScreen.main
                ?? NSScreen.screens.first
            if let screen = initialScreen {
                let viewModel = self.vm
                let window = createNotchPulseWindow(
                    for: screen, with: viewModel)
                self.window = window
                adjustWindowPosition(changeAlpha: true)
            }
        } else {
            adjustWindowPosition(changeAlpha: true)
        }

        setupDragDetectors()

        if coordinator.firstLaunch {
            DispatchQueue.main.async {
                self.showOnboardingWindow()
            }
            playWelcomeSound()
        } else if MusicManager.shared.isNowPlayingDeprecated
            && Defaults[.mediaController] == .nowPlaying
        {
            DispatchQueue.main.async {
                self.showOnboardingWindow(step: .musicPermission)
            }
        }

        // NotchPulse 2.0: Initialize Face ID & Lock Screen Observer
        _ = LockScreenWakeObserver.shared
        _ = NotchPulseFaceUnlockCoordinator.shared
        _ = SystemAuthPromptObserver.shared

        previousScreens = NSScreen.screens
    }

    func playWelcomeSound() {
        let audioPlayer = AudioPlayer()
        audioPlayer.play(fileName: "notchpulse", fileExtension: "m4a")
    }

    func deviceHasNotch() -> Bool {
        if #available(macOS 12.0, *) {
            for screen in NSScreen.screens {
                if screen.safeAreaInsets.top > 0 {
                    return true
                }
            }
        }
        return false
    }

    @objc func screenConfigurationDidChange() {
        NSScreenUUIDCache.shared.rebuildCache()
        let currentScreens = NSScreen.screens

        let screensChanged =
            currentScreens.count != previousScreens?.count
            || Set(currentScreens.compactMap { $0.displayUUID })
                != Set(previousScreens?.compactMap { $0.displayUUID } ?? [])
            || Set(currentScreens.map { $0.frame }) != Set(previousScreens?.map { $0.frame } ?? [])

        previousScreens = currentScreens

        if screensChanged {
            DispatchQueue.main.async { [weak self] in
                self?.cleanupWindows()
                self?.adjustWindowPosition(changeAlpha: true)
                self?.setupDragDetectors()
            }
        }
    }

    @objc func adjustWindowPosition(changeAlpha: Bool = false) {
        if Defaults[.showOnAllDisplays] {
            let currentScreenUUIDs = Set(NSScreen.screens.compactMap { $0.displayUUID })

            // Remove windows for screens that no longer exist
            for uuid in windows.keys where !currentScreenUUIDs.contains(uuid) {
                if let window = windows[uuid] {
                    window.close()
                    NotchSpaceManager.shared.notchSpace.windows.remove(window)
                    windows.removeValue(forKey: uuid)
                    viewModels.removeValue(forKey: uuid)
                }
            }

            // Create or update windows for all screens
            for screen in NSScreen.screens {
                guard let uuid = screen.displayUUID else { continue }
                
                if windows[uuid] == nil {
                    let viewModel = NotchPulseViewModel(screenUUID: uuid)
                    let window = createNotchPulseWindow(for: screen, with: viewModel)

                    windows[uuid] = window
                    viewModels[uuid] = viewModel
                }

                if let window = windows[uuid], let viewModel = viewModels[uuid] {
                    positionWindow(window, on: screen, changeAlpha: changeAlpha)

                    if viewModel.notchState == .closed {
                        viewModel.close()
                    }
                }
            }
        } else {
            let targetScreen: NSScreen?

            // 0. Only dynamically route to the camera's physical display when Face ID is ACTIVELY scanning / showing
            let isFaceIDScanning = FaceIDOverlayController.shared.phase == .scanning
                || FaceIDOverlayController.shared.phase == .success
                || FaceIDOverlayController.shared.phase == .failure
                || FaceIDOverlayController.shared.phase == .onboarding
            if isFaceIDScanning,
               let cameraDevice = NotchPulseCameraDeviceCatalog.resolvedDevice(),
               let camScreen = NotchPulseCameraDeviceCatalog.targetScreen(for: cameraDevice) {
                targetScreen = camScreen
            }
            // 1. Prioritize explicitly preferred display chosen by user
            else if let preferredUUID = coordinator.preferredScreenUUID,
               let preferredScreen = NSScreen.screen(withUUID: preferredUUID) {
                coordinator.selectedScreenUUID = preferredUUID
                targetScreen = preferredScreen
            } else if let activeScreen = NSScreen.screen(withUUID: coordinator.selectedScreenUUID) {
                targetScreen = activeScreen
            } else {
                // The preferred display was disconnected or not found.
                // Fall back gracefully so the notch never disappears!
                let fallback = NSScreen.main
                    ?? NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })
                    ?? NSScreen.screens.first

                if let fallback, let fallbackUUID = fallback.displayUUID {
                    coordinator.selectedScreenUUID = fallbackUUID
                    targetScreen = fallback
                } else {
                    targetScreen = nil
                }
            }

            guard let selectedScreen = targetScreen else {
                if let window = window {
                    window.alphaValue = 0
                }
                return
            }

            vm.screenUUID = selectedScreen.displayUUID
            vm.notchSize = getClosedNotchSize(screenUUID: selectedScreen.displayUUID)
            vm.closedNotchSize = vm.notchSize

            if window == nil {
                window = createNotchPulseWindow(for: selectedScreen, with: vm)
            }

            if let window = window {
                positionWindow(window, on: selectedScreen, changeAlpha: changeAlpha)

                if vm.notchState == .closed {
                    vm.close()
                }
            }
        }
    }

    @objc func togglePopover(_ sender: Any?) {
        if window?.isVisible == true {
            window?.orderOut(nil)
        } else {
            window?.orderFrontRegardless()
        }
    }

    @objc func showMenu() {
        statusItem?.menu?.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    @objc func quitAction() {
        quitApplication()
    }

    private func showOnboardingWindow(step: OnboardingStep = .welcome) {
        if onboardingWindowController == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 600),
                styleMask: [.titled, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.center()
            window.title = "Onboarding"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.contentView = NSHostingView(
                rootView: OnboardingView(
                    step: step,
                    onFinish: {
                        window.orderOut(nil)
//                        NSApp.setActivationPolicy(.accessory)
                        window.close()
                        NSApp.deactivate()
                    },
                    onOpenSettings: {
                        window.close()
                        SettingsWindowController.shared.showWindow()
                    }
                ))
            window.isRestorable = false
            window.identifier = NSUserInterfaceItemIdentifier("OnboardingWindow")

            onboardingWindowController = NSWindowController(window: window)
        }

//        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindowController?.window?.makeKeyAndOrderFront(nil)
        onboardingWindowController?.window?.orderFrontRegardless()
    }
}

extension Notification.Name {
    static let selectedScreenChanged = Notification.Name("SelectedScreenChanged")
    static let notchHeightChanged = Notification.Name("NotchHeightChanged")
    static let showOnAllDisplaysChanged = Notification.Name("showOnAllDisplaysChanged")
    static let automaticallySwitchDisplayChanged = Notification.Name("automaticallySwitchDisplayChanged")
    static let expandedDragDetectionChanged = Notification.Name("expandedDragDetectionChanged")
}

extension CGRect: @retroactive Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(origin.x)
        hasher.combine(origin.y)
        hasher.combine(size.width)
        hasher.combine(size.height)
    }

    public static func == (lhs: CGRect, rhs: CGRect) -> Bool {
        return lhs.origin == rhs.origin && lhs.size == rhs.size
    }
}
