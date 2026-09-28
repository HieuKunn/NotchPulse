//
//  NotchPulseApp.swift
//  NotchPulseApp
//
//  Created by Harsh Vardhan  Goswami  on 02/08/24.
//
//  RELEASE CHECKLIST REMINDER FOR DEVELOPERS & AI AGENTS:
//  When releasing a new version, ALWAYS verify:
//  1. Bump MARKETING_VERSION (e.g. 4.8.7) & CURRENT_PROJECT_VERSION (build number, e.g. 149) in project.pbxproj.
//  2. Update RELEASE_NOTES.md with user-friendly release details.
//  3. Update appcast.xml (Sparkle feed).
//  4. Git tag & push: git push origin main --tags
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
        MenuBarExtra("NotchPulse", systemImage: "teddybear.fill", isInserted: $showMenuBarIcon) {
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

@objc
@MainActor
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
    private var screenLockedObservers: [Any] = []
    private var workspaceLockObservers: [NSObjectProtocol] = []
    private var isScreenLocked: Bool = false
    private var windowScreenDidChangeObserver: Any?
    private var dragDetectors: [String: DragDetector] = [:] // UUID -> DragDetector
    private var shakeAutoCloseTasks: [String: Task<Void, Never>] = [:]
    private var currentViewObserver: AnyCancellable?
    private var shelfWindows: [String: ShelfDropZoneWindow] = [:]
    private var faceIDCameraWindow: NSWindow?
    private var faceIDCameraVM: NotchPulseViewModel?

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
        for observer in screenLockedObservers {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        screenLockedObservers.removeAll()
        for observer in workspaceLockObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        workspaceLockObservers.removeAll()
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

        collapseAllNotches(force: true)

        shelfWindows.values.forEach { window in
            window.orderOut(nil)
        }
        shelfWindows.removeAll() // Tear down Ghost Windows to avoid interfering with lock screen, but keep Radar awake for Face ID
        
        let shouldKeepWindow = Defaults[.showOnLockScreen] || NotchPulseFaceIDSettings.shared.isFaceUnlockEnabled
        if !shouldKeepWindow {
            cleanupWindows()
        } else {
            enableSkyLightOnAllWindows()
        }
    }

    @MainActor
    func collapseAllNotches(force: Bool = true) {
        SharingStateManager.shared.preventNotchClose = false
        ShelfStateViewModel.shared.isPinned = false
        CalendarStateViewModel.shared.isPinned = false
        withAnimation(.spring(response: 0.45, dampingFraction: 1.0)) {
            self.vm.close(force: force)
            for (_, subVm) in self.viewModels {
                subVm.close(force: force)
            }
        }
        self.coordinator.toggleExpandingView(status: false)
        self.coordinator.toggleSneakPeek(status: false)
    }

    @MainActor
    func onScreenUnlocked(_ notification: Notification) {
        isScreenLocked = false
        setupDragDetectors() // Re-enable Ghost Windows and sync Radar after unlocking
        
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
                if let skyCam = self.faceIDCameraWindow as? NotchPulseSkyLightWindow {
                    skyCam.enableSkyLight()
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
                if let skyCam = self.faceIDCameraWindow as? NotchPulseSkyLightWindow {
                    skyCam.disableSkyLight()
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

        if let camWin = faceIDCameraWindow {
            camWin.close()
            NotchSpaceManager.shared.notchSpace.windows.remove(camWin)
            faceIDCameraWindow = nil
            faceIDCameraVM = nil
        }
    }

    private func cleanupDragDetectors() {
        dragExitDebounceTasks.values.forEach { $0.cancel() }
        dragExitDebounceTasks.removeAll()
        shakeAutoCloseTasks.values.forEach { $0.cancel() }
        shakeAutoCloseTasks.removeAll()
        shelfWindows.values.forEach { window in
            window.orderOut(nil)
        }
        shelfWindows.removeAll()
        dragDetectors.values.forEach { detector in
            detector.stopMonitoring()
        }
        dragDetectors.removeAll()
    }

    private func setupDragDetectors() {
        cleanupDragDetectors()

        // ALWAYS setup radar if Shelf, extendHoverArea, or openNotchOnHover is enabled!
        guard Defaults[.notchPulseShelf] || Defaults[.extendHoverArea] || Defaults[.openNotchOnHover] else { return }

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
        
        let targetVM = (Defaults[.showOnAllDisplays] ? self.viewModels[uuid] : nil) ?? self.vm

        // SETUP LIGHTWEIGHT RADAR FOR HOVER DETECTION
        // Uses pure coordinate monitoring (NSEvent.mouseLocation) with ZERO physical windows or overlays.
        // Clicks to underlying tabs, links, and buttons remain 100% unobstructed.
        let detector = DragDetector { [weak self] in
            guard let self = self else { return .zero }
            let currentTargetVM = (Defaults[.showOnAllDisplays] ? self.viewModels[uuid] : nil) ?? targetVM
            let currentScreen = NSScreen.screen(withUUID: uuid) ?? screen
            let currentFrame = currentScreen.frame
            
            let isDynamicIsland = Defaults[.notchStyle] == .dynamicIsland
            let hasPhysicalNotch = currentScreen.safeAreaInsets.top > 0 || currentScreen.auxiliaryTopLeftArea != nil
            let topOffset = (isDynamicIsland && !hasPhysicalNotch) ? Defaults[.dynamicIslandTopOffset] : 0

            let padding = Defaults[.extendHoverArea] ? CGFloat(Defaults[.hoverAreaPadding]) : 0.0
            if currentTargetVM.notchState == .open {
                let openWidth = max(currentTargetVM.notchSize.width, max(openNotchSize.width, CGFloat(Defaults[.notchOpenWidth])))
                let openHeight = max(currentTargetVM.customOpenHeight ?? currentTargetVM.notchSize.height, openNotchSize.height)
                return CGRect(
                    x: currentFrame.midX - (openWidth / 2 + padding),
                    y: currentFrame.maxY - (openHeight + padding + topOffset),
                    width: openWidth + (padding * 2),
                    height: openHeight + padding + topOffset + 15
                )
            } else {
                let closedSize = currentTargetVM.closedNotchSize
                let closedWidth = isDynamicIsland ? 210.0 : (closedSize.width > 0 ? closedSize.width : 185.0)
                let closedHeight = isDynamicIsland ? 32.0 : (closedSize.height > 0 ? closedSize.height : 36.0)
                // Confine closed notch hover bounds strictly to the physical notch / island.
                // Absolutely no lateral or downward bleeding to prevent false triggers over browser tabs.
                return CGRect(
                    x: currentFrame.midX - (closedWidth / 2),
                    y: currentFrame.maxY - (closedHeight + topOffset),
                    width: closedWidth,
                    height: closedHeight + topOffset
                )
            },
            screenFrameProvider: { [weak self] in
                guard let self = self else { return screen.frame }
                return (NSScreen.screen(withUUID: uuid) ?? screen).frame
            }
        )
        
        detector.onShakeDetected = { [weak self] in
            Task { @MainActor in
                guard let self = self else { return }
                let currentTargetVM = (Defaults[.showOnAllDisplays] ? self.viewModels[uuid] : nil) ?? targetVM
                currentTargetVM.customOpenHeight = nil
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    currentTargetVM.open()
                    self.coordinator.currentView = .shelf
                }
                if Defaults[.enableHaptics] {
                    NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                }

                // If user shakes to open the shelf but does not drop into the notch within the configured delay, auto-close (unless tour is active)
                self.shakeAutoCloseTasks[uuid]?.cancel()
                let waitDuration = Defaults[.shakeAutoCloseDelay]
                self.shakeAutoCloseTasks[uuid] = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(Int(waitDuration * 1000)))
                    guard !Task.isCancelled, let self = self else { return }
                    guard !SpotlightTourManager.shared.isActive else { return }
                    let vm = (Defaults[.showOnAllDisplays] ? self.viewModels[uuid] : nil) ?? targetVM
                    if !vm.dropZoneTargeting && !vm.generalDropTargeting && !ShelfStateViewModel.shared.isPinned && !CalendarStateViewModel.shared.isPinned && vm.notchState == .open {
                        vm.close()
                        if !self.coordinator.openLastTabByDefault && !ShelfStateViewModel.shared.isPinned {
                            self.coordinator.currentView = .home
                        }
                    }
                }
            }
        }

        detector.onDragEnded = { [weak self] in
            Task { @MainActor in
                self?.handleDragEnded(onScreen: screen)
            }
        }
        detector.onGlobalHoverStateChanged = { [weak self] hovering in
            Task { @MainActor in
                guard let self = self else { return }
                let currentTargetVM = (Defaults[.showOnAllDisplays] ? self.viewModels[uuid] : nil) ?? self.vm
                currentTargetVM.isHoveringFromRadar = hovering
            }
        }
        
        dragDetectors[uuid] = detector
        detector.startMonitoring()
    }

    @MainActor
    func resetAllDropAndDragTargeting() {
        vm.dragDetectorTargeting = false
        vm.dropZoneTargeting = false
        vm.generalDropTargeting = false
        vm.anyDropZoneTargeting = false
        vm.dropEvent = false
        for targetVM in viewModels.values {
            targetVM.dragDetectorTargeting = false
            targetVM.dropZoneTargeting = false
            targetVM.generalDropTargeting = false
            targetVM.anyDropZoneTargeting = false
            targetVM.dropEvent = false
        }
    }

    private func handleDragEnded(onScreen screen: NSScreen) {
        guard let uuid = screen.displayUUID else { return }
        
        shakeAutoCloseTasks[uuid]?.cancel()
        shakeAutoCloseTasks[uuid] = nil
        
        resetAllDropAndDragTargeting()
        guard !SpotlightTourManager.shared.isActive else { return }
        let targetVM = (Defaults[.showOnAllDisplays] ? self.viewModels[uuid] : nil) ?? self.vm
        
        // If the user is currently on the shelf tab (opened via shake-to-shelf gesture),
        // do NOT auto-close the notch. Let them interact with the shelf normally.
        // The notch will close when they hover away as usual.
        if coordinator.currentView == .shelf {
            return
        }
        
        // Check if mouse is still hovering over open notch window
        let mouseLocation = NSEvent.mouseLocation
        let screenFrame = screen.frame
        let isDynamicIsland = Defaults[.notchStyle] == .dynamicIsland
        let topOffset = (isDynamicIsland && screen.safeAreaInsets.top == 0) ? Defaults[.dynamicIslandTopOffset] : 0
        let openWidth = max(targetVM.notchSize.width, CGFloat(Defaults[.notchOpenWidth]))
        let openHeight = max(targetVM.customOpenHeight ?? targetVM.notchSize.height, 190.0)
        let openNotchRect = CGRect(
            x: screenFrame.midX - openWidth / 2,
            y: screenFrame.maxY - (openHeight + topOffset),
            width: openWidth,
            height: openHeight + topOffset
        )
        
        let isMouseOverOpenNotch = openNotchRect.contains(mouseLocation)
        
        if !isMouseOverOpenNotch && !ShelfStateViewModel.shared.isPinned && !CalendarStateViewModel.shared.isPinned && targetVM.notchState == .open {
            targetVM.close()
            if !self.coordinator.openLastTabByDefault && !ShelfStateViewModel.shared.isPinned {
                self.coordinator.currentView = .home
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
    private func updateFaceIDCameraWindow() {
        let isLockScreen = NotchPulseLockMonitor.isScreenActuallyLocked()
        let canRouteForLockScreen = !isLockScreen || FaceIDOverlayController.shared.isHoverTriggeredOnLockScreen
        let isFaceIDScanning = canRouteForLockScreen && (FaceIDOverlayController.shared.phase == .scanning
            || FaceIDOverlayController.shared.phase == .success
            || FaceIDOverlayController.shared.phase == .failure
            || FaceIDOverlayController.shared.phase == .onboarding
            || (FaceIDOverlayController.shared.isPresenting && FaceIDOverlayController.shared.phase != .closed && FaceIDOverlayController.shared.phase != .collapsing))

        guard isFaceIDScanning,
              !Defaults[.showOnAllDisplays],
              let cameraDevice = NotchPulseCameraDeviceCatalog.resolvedDevice(),
              let camScreen = NotchPulseCameraDeviceCatalog.targetScreen(for: cameraDevice),
              let camUUID = camScreen.displayUUID,
              camUUID != coordinator.selectedScreenUUID else {
            if let window = faceIDCameraWindow {
                window.close()
                NotchSpaceManager.shared.notchSpace.windows.remove(window)
                faceIDCameraWindow = nil
                faceIDCameraVM = nil
            }
            return
        }

        if faceIDCameraWindow == nil {
            let camVM = NotchPulseViewModel(screenUUID: camUUID)
            let window = createNotchPulseWindow(for: camScreen, with: camVM)
            faceIDCameraWindow = window
            faceIDCameraVM = camVM
        }

        if let window = faceIDCameraWindow, let viewModel = faceIDCameraVM {
            positionWindow(window, on: camScreen, changeAlpha: false)
            window.orderFrontRegardless()
        }
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

        // Also intercept local pure Cmd+Q keyDown events directly (strictly excluding Shift, etc.)
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags == .command && event.charactersIgnoringModifiers?.lowercased() == "q" {
                self?.quitApplication()
                return nil
            }
            return event
        }

        if let updater = SettingsWindowController.shared.updaterController {
            SettingsWindowController.shared.setUpdaterController(updater, viewModel: self.vm)
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.screenConfigurationDidChange()
            }
        }

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
            forName: Notification.Name.faceIDPhaseChanged, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateFaceIDCameraWindow()
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
                // Rule: Only 1 notch active at a time! Only preview on the screen containing mouse cursor.
                let mouseLocation = NSEvent.mouseLocation
                let activeScreen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main
                let activeVM: NotchPulseViewModel
                if Defaults[.showOnAllDisplays], let uuid = activeScreen?.displayUUID, let sub = self.viewModels[uuid] {
                    activeVM = sub
                } else {
                    activeVM = self.vm
                }
                activeVM.open()
                activeVM.notchSize = CGSize(width: width, height: openNotchSize.height)
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
        if let obs = screenLockedObserver {
            screenLockedObservers.append(obs)
        }

        let screensaverLockObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(rawValue: "com.apple.screensaver.didstart"),
            object: nil, queue: .main) { [weak self] notification in
                Task { @MainActor in
                    self?.onScreenLocked(notification)
                }
        }
        screenLockedObservers.append(screensaverLockObserver)

        let willSleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil, queue: .main) { [weak self] notification in
                Task { @MainActor in
                    self?.onScreenLocked(notification)
                }
        }
        workspaceLockObservers.append(willSleepObserver)

        let screensDidSleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil, queue: .main) { [weak self] notification in
                Task { @MainActor in
                    self?.onScreenLocked(notification)
                }
        }
        workspaceLockObservers.append(screensDidSleepObserver)

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

        currentViewObserver = coordinator.$currentView
            .sink { [weak self] view in
                if view != .shelf {
                    self?.shakeAutoCloseTasks.values.forEach { $0.cancel() }
                    self?.shakeAutoCloseTasks.removeAll()
                }
            }

        let isFirstInstall = coordinator.firstLaunch
        let isUpdate = isAppUpdated()

        if isFirstInstall {
            DispatchQueue.main.async {
                self.showOnboardingWindow()
            }
            playWelcomeSound()
        } else if isUpdate {
            // App was updated to a new version: automatically display Spotlight Tour
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                SpotlightTourManager.shared.showTour()
            }
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
        if NotchPulseFaceIDSettings.shared.isFaceUnlockEnabled {
            ArcFaceEmbedder.warmUp()
        }

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

    @MainActor func screenConfigurationDidChange() {
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

    func adjustWindowPosition(changeAlpha: Bool = false) {
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

            // 1. Prioritize explicitly preferred display chosen by user
            if let preferredUUID = coordinator.preferredScreenUUID,
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
                updateFaceIDCameraWindow()
                return
            }

            vm.screenUUID = selectedScreen.displayUUID
            if vm.notchState == .closed {
                vm.notchSize = getClosedNotchSize(screenUUID: selectedScreen.displayUUID)
                vm.closedNotchSize = vm.notchSize
            }

            if window == nil {
                window = createNotchPulseWindow(for: selectedScreen, with: vm)
            }

            if let window = window {
                positionWindow(window, on: selectedScreen, changeAlpha: changeAlpha)

                if vm.notchState == .closed {
                    vm.close()
                }
            }

            updateFaceIDCameraWindow()
        }
    }

    @objc @MainActor func togglePopover(_ sender: Any?) {
        if window?.isVisible == true {
            window?.orderOut(nil)
        } else {
            window?.orderFrontRegardless()
        }
    }

    @objc @MainActor func showMenu() {
        statusItem?.menu?.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    @objc @MainActor func quitAction() {
        quitApplication()
    }

    private func showOnboardingWindow(step: OnboardingStep = .welcome) {
        if onboardingWindowController == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 600),
                styleMask: [.titled, .closable, .fullSizeContentView],
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
                        window.close()
                        self.onboardingWindowController = nil
                        self.coordinator.firstLaunch = false
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            self.vm.open()
                        }
                    },
                    onOpenSettings: {
                        window.orderOut(nil)
                        window.close()
                        self.onboardingWindowController = nil
                        self.coordinator.firstLaunch = false
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            self.vm.open()
                        }
                        SettingsWindowController.shared.showWindow()
                    }
                ))
            window.isRestorable = false
            window.identifier = NSUserInterfaceItemIdentifier("OnboardingWindow")

            // Ensure closing the onboarding window keeps the app and notch open
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                guard let self = self else { return }
                self.onboardingWindowController = nil
                self.coordinator.firstLaunch = false
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    self.vm.open()
                }
            }

            onboardingWindowController = NSWindowController(window: window)
        }

//        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindowController?.window?.makeKeyAndOrderFront(nil)
        onboardingWindowController?.window?.orderFrontRegardless()
    }
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
