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

import AppKit
import AVFoundation
import Combine
import Defaults
import KeyboardShortcuts
import Sparkle
import SwiftUI

@available(macOS 14.0, *)
@main
struct DynamicNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Default(.menubarIcon) var showMenuBarIcon
    @Default(.appLanguage) var appLanguage
    @Default(.notchOpenWidth) var notchOpenWidth
    @Environment(\.openWindow) var openWindow

    let updaterController: SPUStandardUpdaterController

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: AppUpdaterDelegate.shared, userDriverDelegate: nil)

        // Initialize the settings window controller with the updater controller
        SettingsWindowController.shared.setUpdaterController(updaterController)
        
        // Pre-warm Face ID initial static frame cache for zero-delay rendering from frame 0
        ScanAnimationHostView.prewarm()
        FaceIDScanAnimationHostView.prewarm()
    }

    var body: some Scene {
        MenuBarExtra(isInserted: $showMenuBarIcon) {
            Button(loc("Settings")) {
                DispatchQueue.main.async {
                    SettingsWindowController.shared.showWindow()
                }
            }
            .keyboardShortcut(KeyEquivalent(","), modifiers: .command)
            
            Menu("\(loc("Notch Width")) (\(Int(notchOpenWidth))px)") {
                Button(loc("Compact (580px)")) { Defaults[.notchOpenWidth] = 580 }
                Button(loc("Standard (740px)")) { Defaults[.notchOpenWidth] = 740 }
                Button(loc("Wide (860px)")) { Defaults[.notchOpenWidth] = 860 }
                Button(loc("Extra Wide (940px)")) { Defaults[.notchOpenWidth] = 940 }
                Divider()
                Button(loc("Custom Dimensions...")) {
                    DispatchQueue.main.async {
                        SettingsWindowController.shared.showWindow()
                    }
                }
            }
            
            CheckForUpdatesView(updater: updaterController.updater)
            Divider()
            Button(loc("Restart NotchPulse")) {
                ApplicationRelauncher.restart()
            }
            Button(loc("Quit"), role: .destructive) {
                appDelegate.isUserInitiatedQuit = true
                appDelegate.quitApplication()
            }
            .keyboardShortcut(KeyEquivalent("q"), modifiers: .command)
        } label: {
            Image(systemName: "teddybear.fill")
        }
    }
}

@available(macOS 14.0, *)
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
    private var hoverDetectors: [String: NotchHoverDetector] = [:] // UUID -> NotchHoverDetector
    private var dragExitDebounceTasks: [String: Task<Void, Never>] = [:]
    var dragAutoCloseTasks: [String: Task<Void, Never>] = [:]
    var shakeAutoCloseTasks: [String: Task<Void, Never>] = [:]
    private var currentViewObserver: AnyCancellable?
    private var faceIDCameraWindow: NSWindow?
    private var faceIDCameraVM: NotchPulseViewModel?

    func resetAllDropAndDragTargeting() {
        for vm in viewModels.values {
            vm.dragDetectorTargeting = false
            vm.generalDropTargeting = false
            vm.dropZoneTargeting = false
            vm.shareDropTargeting = false
            vm.shelfDropTargeting = false
            vm.anyDropZoneTargeting = false
        }
        vm.dragDetectorTargeting = false
        vm.generalDropTargeting = false
        vm.dropZoneTargeting = false
        vm.shareDropTargeting = false
        vm.shelfDropTargeting = false
        vm.anyDropZoneTargeting = false
    }

    static weak var shared: AppDelegate?
    var isUserInitiatedQuit: Bool = false

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        cleanupForTermination()
        return .terminateNow
    }

    @MainActor
    func cleanupForTermination() {
        NSApplication.shared.windows.forEach { $0.orderOut(nil) }
        cleanupWindows()
        cleanupDragDetectors()
        cleanupHoverDetectors()
        FaceIDOverlayController.shared.disarm()
        LockScreenFaceIDWindow.shared.orderOut(nil)
        LockScreenMediaWindow.shared.orderOut(nil)
        MusicManager.shared.destroy()
    }

    @MainActor
    func quitApplication() {
        isUserInitiatedQuit = true
        cleanupForTermination()
        NSApplication.shared.terminate(nil)
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
        cleanupHoverDetectors()
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
        self.coordinator.toggleExpandingView(status: false, type: .music)
        self.coordinator.toggleSneakPeek(status: false, type: .music)
    }

    @MainActor
    func onScreenUnlocked(_ notification: Notification) {
        isScreenLocked = false
        setupDetectors() // Re-enable Ghost Windows, Radar and Hover Detectors after unlocking
        
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
        dragDetectors.values.forEach { detector in
            detector.stopMonitoring()
        }
        dragDetectors.removeAll()
    }

    private func cleanupHoverDetectors() {
        hoverDetectors.values.forEach { detector in
            detector.stopMonitoring()
        }
        hoverDetectors.removeAll()
    }

    func setupHoverDetectors() {
        cleanupHoverDetectors()

        if Defaults[.showOnAllDisplays] {
            for screen in NSScreen.screens {
                setupHoverDetectorForScreen(screen)
            }
        } else {
            let preferredScreen: NSScreen? = (coordinator.preferredScreenUUID.flatMap({ NSScreen.screen(withUUID: $0) }))
                ?? NSScreen.screen(withUUID: coordinator.selectedScreenUUID)
                ?? window?.screen
                ?? NSScreen.main
                ?? NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })
                ?? NSScreen.screens.first

            if let screen = preferredScreen {
                setupHoverDetectorForScreen(screen)
            }
        }
    }

    private func setupHoverDetectorForScreen(_ screen: NSScreen) {
        guard let uuid = screen.displayUUID else { return }

        let detector = NotchHoverDetector(
            closedRegionProvider: { [weak self] in
                guard let self = self else { return .zero }
                let screenFrame = screen.frame
                let targetVM = (Defaults[.showOnAllDisplays] ? self.viewModels[uuid] : nil) ?? self.vm
                let isDynamicIsland = Defaults[.notchStyle] == .dynamicIsland
                let topOffset = isDynamicIsland ? Defaults[.dynamicIslandTopOffset] : 0

                let closedSize = targetVM.closedNotchSize
                let closedWidth = isDynamicIsland ? 210.0 : (closedSize.width > 0 ? closedSize.width : 185.0)
                let closedHeight = isDynamicIsland ? 32.0 : (closedSize.height > 0 ? closedSize.height : 36.0)
                let padding = Defaults[.extendHoverArea] ? CGFloat(Defaults[.hoverAreaPadding]) : 12.0

                return CGRect(
                    x: screenFrame.midX - (closedWidth / 2 + padding),
                    y: screenFrame.maxY - (closedHeight + padding + topOffset),
                    width: closedWidth + (padding * 2),
                    height: closedHeight + padding + topOffset + 12
                )
            },
            openRegionProvider: { [weak self] in
                guard let self = self else { return .zero }
                let screenFrame = screen.frame
                let targetVM = (Defaults[.showOnAllDisplays] ? self.viewModels[uuid] : nil) ?? self.vm
                let isDynamicIsland = Defaults[.notchStyle] == .dynamicIsland
                let topOffset = isDynamicIsland ? Defaults[.dynamicIslandTopOffset] : 0

                let openWidth = max(targetVM.notchSize.width, max(openNotchSize.width, CGFloat(Defaults[.notchOpenWidth])))
                let openHeight = max(targetVM.notchSize.height, openNotchSize.height)
                let padding: CGFloat = 24.0

                return CGRect(
                    x: screenFrame.midX - (openWidth / 2 + padding),
                    y: screenFrame.maxY - (openHeight + padding + topOffset),
                    width: openWidth + (padding * 2),
                    height: openHeight + padding + topOffset + 24
                )
            },
            isNotchOpenProvider: { [weak self] in
                guard let self = self else { return false }
                let targetVM = (Defaults[.showOnAllDisplays] ? self.viewModels[uuid] : nil) ?? self.vm
                return targetVM.notchState == .open
            }
        )

        detector.onHoverEntersNotchRegion = { [weak self] in
            Task { @MainActor in
                guard let self = self else { return }
                guard !NotchPulseLockMonitor.isScreenActuallyLocked(),
                      !FeatureTourController.shared.isTourActive else { return }
                let targetVM = (Defaults[.showOnAllDisplays] ? self.viewModels[uuid] : nil) ?? self.vm
                if targetVM.notchState == .closed && Defaults[.openNotchOnHover] {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        targetVM.open()
                    }
                }
            }
        }

        detector.onHoverExitsNotchRegion = { [weak self] in
            Task { @MainActor in
                guard let self = self else { return }
                let targetVM = (Defaults[.showOnAllDisplays] ? self.viewModels[uuid] : nil) ?? self.vm
                guard targetVM.notchState == .open else { return }
                guard !ShelfStateViewModel.shared.isPinned,
                      !CalendarStateViewModel.shared.isPinned,
                      !SharingStateManager.shared.preventNotchClose,
                      !targetVM.isBatteryPopoverActive,
                      !FeatureTourController.shared.isTourActive,
                      !targetVM.anyDropZoneTargeting,
                      !targetVM.dropEvent else { return }

                withAnimation(.spring(response: 0.38, dampingFraction: 0.84)) {
                    targetVM.close()
                }
            }
        }

        hoverDetectors[uuid] = detector
        detector.startMonitoring()
    }

    func setupDetectors() {
        setupDragDetectors()
        setupHoverDetectors()
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
            let topOffset = isDynamicIsland ? Defaults[.dynamicIslandTopOffset] : 0
            
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
        dragAutoCloseTasks[uuid]?.cancel()
        
        SharingStateManager.shared.preventNotchClose = true
        
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            if Defaults[.showOnAllDisplays], let viewModel = viewModels[uuid] {
                viewModel.open()
            } else {
                vm.open()
            }
            coordinator.currentView = .shelf
        }
        
        // Auto-close if drag enters but is left idle without dropping within close delay
        let delaySeconds = max(2.0, Defaults[.shakeAutoCloseDelay])
        dragAutoCloseTasks[uuid] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delaySeconds))
            guard !Task.isCancelled, let self = self else { return }
            let targetVM = (Defaults[.showOnAllDisplays] ? self.viewModels[uuid] : nil) ?? self.vm
            if !targetVM.dropEvent && !ShelfStateViewModel.shared.isPinned && !CalendarStateViewModel.shared.isPinned && targetVM.notchState == .open {
                SharingStateManager.shared.preventNotchClose = false
                targetVM.close()
            }
        }
    }

    private func handleDragExitsNotchRegion(onScreen screen: NSScreen) {
        guard let uuid = screen.displayUUID else { return }
        
        dragExitDebounceTasks[uuid]?.cancel()
        dragAutoCloseTasks[uuid]?.cancel()
        dragExitDebounceTasks[uuid] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self = self else { return }
            
            let targetVM = (Defaults[.showOnAllDisplays] ? self.viewModels[uuid] : nil) ?? self.vm
            guard !targetVM.anyDropZoneTargeting && !targetVM.dropEvent else { return }
            
            SharingStateManager.shared.preventNotchClose = false
            if !ShelfStateViewModel.shared.isPinned && !CalendarStateViewModel.shared.isPinned && targetVM.notchState == .open {
                targetVM.close()
            }
        }
    }

    private func handleDragEnded(onScreen screen: NSScreen) {
        guard let uuid = screen.displayUUID else { return }
        
        dragExitDebounceTasks[uuid]?.cancel()
        dragAutoCloseTasks[uuid]?.cancel()
        
        // Immediately close when drag is dropped or cancelled, without waiting
        SharingStateManager.shared.preventNotchClose = false
        let targetVM = (Defaults[.showOnAllDisplays] ? self.viewModels[uuid] : nil) ?? self.vm
        targetVM.dropEvent = false
        targetVM.anyDropZoneTargeting = false
        targetVM.generalDropTargeting = false
        targetVM.shelfDropTargeting = false
        targetVM.dragDetectorTargeting = false
        targetVM.dropZoneTargeting = false
        targetVM.shareDropTargeting = false
        
        if !ShelfStateViewModel.shared.isPinned && !CalendarStateViewModel.shared.isPinned && targetVM.notchState == .open {
            targetVM.close()
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

        let hostingView = NSHostingView(
            rootView: ContentView()
                .environmentObject(viewModel)
        )
        window.contentView = hostingView

        window.orderFrontRegardless()
        NotchSpaceManager.shared.notchSpace.windows.insert(window)

        // Observe when the window's screen changes so we can update drag detectors
        windowScreenDidChangeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeScreenNotification,
            object: window,
            queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.setupDetectors()
                }
        }
        return window
    }

    @MainActor
    func updateFaceIDCameraWindow() {
        let isLockScreen = NotchPulseLockMonitor.isScreenActuallyLocked()
        let canRouteForLockScreen = !isLockScreen || FaceIDOverlayController.shared.isHoverTriggeredOnLockScreen
        let isFaceIDScanning = canRouteForLockScreen && (FaceIDOverlayController.shared.phase == .scanning
            || FaceIDOverlayController.shared.phase == .success
            || FaceIDOverlayController.shared.phase == .failure
            || FaceIDOverlayController.shared.phase == .onboarding
            || (FaceIDOverlayController.shared.isPresenting && FaceIDOverlayController.shared.phase != .closed && FaceIDOverlayController.shared.phase != .collapsing))

        if isLockScreen && isFaceIDScanning {
            if let skyWindow = self.window as? NotchPulseSkyLightWindow {
                skyWindow.enableSkyLight()
                skyWindow.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 4)
                skyWindow.alphaValue = 1.0
                skyWindow.orderFrontRegardless()
            }
            for skyWindow in self.windows.values.compactMap({ $0 as? NotchPulseSkyLightWindow }) {
                skyWindow.enableSkyLight()
                skyWindow.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 4)
                skyWindow.alphaValue = 1.0
                skyWindow.orderFrontRegardless()
            }
        }

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

        if let window = faceIDCameraWindow, faceIDCameraVM != nil {
            positionWindow(window, on: camScreen, changeAlpha: false)
            window.alphaValue = 1.0
            if isLockScreen {
                (window as? NotchPulseSkyLightWindow)?.enableSkyLight()
                window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 4)
            }
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
                self?.isUserInitiatedQuit = true
                self?.quitApplication()
                return nil
            }
            return event
        }

        if let updater = SettingsWindowController.shared.updaterController {
            SettingsWindowController.shared.setUpdaterController(updater, viewModel: self.vm)
        }

        // Start clipboard monitoring immediately at app launch
        _ = ClipboardManager.shared

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
                self?.setupDetectors()
            }
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name.notchHeightChanged, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.adjustWindowPosition()
                self?.setupDetectors()
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
                self?.setupDetectors()
            }
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name.showOnAllDisplaysChanged, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.cleanupWindows(shouldInvert: true)
                self.adjustWindowPosition(changeAlpha: true)
                self.setupDetectors()
            }
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name.expandedDragDetectionChanged, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.setupDetectors()
            }
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name.previewNotchWidth, object: nil, queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            let width = (notification.object as? CGFloat) ?? Defaults[.notchOpenWidth]
            // Rule: Only 1 notch active at a time! Only preview on the screen containing mouse cursor.
            let mouseLocation = NSEvent.mouseLocation
            let activeScreen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main
            let activeVM: NotchPulseViewModel
            if Defaults[.showOnAllDisplays], let uuid = activeScreen?.displayUUID, let sub = self.viewModels[uuid] {
                activeVM = sub
            } else {
                activeVM = self.vm
            }
            SharingStateManager.shared.preventNotchClose = true
            activeVM.notchSize = CGSize(width: width, height: openNotchSize.height)
            if activeVM.notchState != .open {
                activeVM.open()
            }
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name.closeNotchPreview, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            SharingStateManager.shared.preventNotchClose = false
            self.vm.close(force: true)
            for (_, subVm) in self.viewModels {
                subVm.close(force: true)
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

        setupDetectors()

        currentViewObserver = coordinator.$currentView
            .sink { [weak self] view in
                if view != .shelf {
                    self?.shakeAutoCloseTasks.values.forEach { $0.cancel() }
                    self?.shakeAutoCloseTasks.removeAll()
                }
            }

        let isFirstInstall = coordinator.firstLaunch

        if isFirstInstall {
            DispatchQueue.main.async {
                self.showOnboardingWindow()
            }
            playWelcomeSound()
        }

        // NotchPulse 2.0: Initialize Face ID & Lock Screen Observer
        _ = LockScreenWakeObserver.shared
        _ = NotchPulseFaceUnlockCoordinator.shared
        _ = SystemAuthPromptObserver.shared
        _ = BluetoothHeadphoneManager.shared
        if NotchPulseFaceIDSettings.shared.isFaceUnlockEnabled {
            ArcFaceEmbedder.warmUp()
        }

        previousScreens = NSScreen.screens

        // First-open UI warm-up: the FIRST time the notch opens after launch, SwiftUI
        // builds the entire open-state view tree (music, calendar, clipboard, shelf...)
        // and fetches first data in one 1.5-2s main-thread stall that runs DURING the
        // user's first open animation — measured hitches of ~1700ms at notch=open.
        // Opening+closing invisibly shortly after launch pays that cost once while the
        // user isn't watching, so every real open afterwards animates smoothly.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard let self, !self.isUserInitiatedQuit else { return }
            let vm = self.vm
            guard vm.notchState == .closed, !SharingStateManager.shared.preventNotchClose else { return }
            vm.open()
            try? await Task.sleep(for: .milliseconds(650))
            guard vm.notchState == .open, !SharingStateManager.shared.preventNotchClose else { return }
            withAnimation(NotchPulseViewModel.notchCloseSpring) {
                vm.close()
            }
        }
    }

    func playWelcomeSound() {
        let audioPlayer = AudioPlayer()
        audioPlayer.play(fileName: "notchpulse", fileExtension: "m4a")
    }

    func deviceHasNotch() -> Bool {
        for screen in NSScreen.screens {
            if screen.safeAreaInsets.top > 0 {
                return true
            }
        }
        return false
    }

    @MainActor func screenConfigurationDidChange() {
        NSScreenUUIDCache.shared.rebuildCache()
        NotchPulseCameraDeviceCatalog.invalidateTargetScreenCache()
        let currentScreens = NSScreen.screens

        let screensChanged =
            currentScreens.count != previousScreens?.count
            || Set(currentScreens.compactMap { $0.displayUUID })
                != Set(previousScreens?.compactMap { $0.displayUUID } ?? [])
            || currentScreens.map { $0.frame } != (previousScreens?.map { $0.frame } ?? [])

        previousScreens = currentScreens

        if screensChanged {
            DispatchQueue.main.async { [weak self] in
                self?.cleanupWindows()
                self?.adjustWindowPosition(changeAlpha: true)
                self?.setupDetectors()
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

    @available(macOS 14.0, *)
    @objc @MainActor func togglePopover(_ sender: Any?) {
        if window?.isVisible == true {
            window?.orderOut(nil)
        } else {
            window?.orderFrontRegardless()
        }
    }

    @available(macOS 14.0, *)
    @objc @MainActor func showMenu() {
        statusItem?.menu?.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    @available(macOS 14.0, *)
    @objc @MainActor func quitAction() {
        isUserInitiatedQuit = true
        quitApplication()
    }

    /// Re-opens the standard permission-flow onboarding window on demand (Settings →
    /// "Review setup"). Purely a window presentation — never touches notch state or
    /// settings, so it cannot regress notch interactions the way the old tour did.
    ///
    /// NotchPulse runs as an .accessory (menu bar) app and .accessory apps cannot
    /// receive key focus while another app (System Settings, Finder…) is active —
    /// `makeKeyAndOrderFront` silently does nothing there. Temporarily switching to
    /// .regular (like SettingsWindowController does) lets the window actually come
    /// to the front; the policy reverts when the window closes via the standard
    /// accessory-policy restore in the onboarding teardown path.
    func showOnboardingReview() {
        FeatureTourController.shared.startTour()
    }

    func showFeatureTour() {
        FeatureTourController.shared.startTour()
    }

    /// Runs the actual window-ordering work on the next main-queue tick so callers
    /// inside SwiftUI button actions (which run mid-update) are safe.
    ///
    /// NotchPulse runs as an .accessory (menu bar) app, and .accessory apps cannot
    /// become active while another app is frontmost — `makeKeyAndOrderFront` from an
    /// inactive accessory app is silently ignored by macOS, which is why the Review
    /// setup button appeared to do nothing. Temporarily switching to .regular (the
    /// same approach SettingsWindowController uses) lets the window actually take
    /// focus; the policy is restored to .accessory when the onboarding window
    /// closes, via the teardown paths inside showOnboardingWindow.
    private func presentOnboardingWindowToFront() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.onboardingWindowController?.window else { return }
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }

    private func showOnboardingWindow(step: OnboardingStep = .welcome) {
        if onboardingWindowController == nil || onboardingWindowController?.window == nil {
            let window: NSWindow
            if step == .featureTour {
                let screen = NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
                window = NSWindow(
                    contentRect: screen.frame,
                    styleMask: [.borderless, .fullSizeContentView],
                    backing: .buffered,
                    defer: false
                )
                window.backgroundColor = .clear
                window.isOpaque = false
                window.hasShadow = false
                window.level = .mainMenu + 2
                window.ignoresMouseEvents = false
                window.setFrame(screen.frame, display: true)
            } else {
                window = NSWindow(
                    contentRect: NSRect(x: 0, y: 0, width: 400, height: 600),
                    styleMask: [.titled, .closable, .fullSizeContentView],
                    backing: .buffered,
                    defer: false
                )
                window.center()
                window.title = "Onboarding"
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
            }
            window.isRestorable = false
            window.isReleasedWhenClosed = false
            window.identifier = NSUserInterfaceItemIdentifier("OnboardingWindow")
            window.contentView = PassthroughTourHostingView(
                rootView: OnboardingView(
                    step: step,
                    onFinish: {
                        window.orderOut(nil)
                        self.onboardingWindowController = nil
                        NSApp.setActivationPolicy(.accessory)
                        self.coordinator.firstLaunch = false
                        self.coordinator.currentView = .home
                        self.vm.customOpenHeight = nil
                        self.vm.featureTourTarget = nil
                        self.vm.close()
                        for vm in self.viewModels.values {
                            vm.customOpenHeight = nil
                            vm.featureTourTarget = nil
                            vm.close()
                        }
                    },
                    onOpenSettings: {
                        window.orderOut(nil)
                        self.onboardingWindowController = nil
                        self.coordinator.firstLaunch = false
                        self.coordinator.currentView = .home
                        self.vm.customOpenHeight = nil
                        self.vm.featureTourTarget = nil
                        self.vm.close()
                        for vm in self.viewModels.values {
                            vm.customOpenHeight = nil
                            vm.featureTourTarget = nil
                            vm.close()
                        }
                        SettingsWindowController.shared.showWindow()
                    }
                )
                .environmentObject(self.coordinator)
                .environmentObject(self.vm)
            )

            // Ensure closing the onboarding window dismisses controller cleanly
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                guard let self = self else { return }
                self.onboardingWindowController = nil
                NSApp.setActivationPolicy(.accessory)
                self.coordinator.firstLaunch = false
                self.coordinator.currentView = .home
                self.vm.customOpenHeight = nil
                self.vm.featureTourTarget = nil
                self.vm.close()
                for vm in self.viewModels.values {
                    vm.customOpenHeight = nil
                    vm.featureTourTarget = nil
                    vm.close()
                }
            }

            onboardingWindowController = NSWindowController(window: window)
        }

        presentOnboardingWindowToFront()
    }
}
