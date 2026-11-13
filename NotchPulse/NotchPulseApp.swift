import AppKit
import AVFoundation
import Combine
import Defaults
import EventKit
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
    @Default(.enableLaunchpad) var enableLaunchpad
    @Environment(\.openWindow) var openWindow

    let updaterController: SPUStandardUpdaterController

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: AppUpdaterDelegate.shared, userDriverDelegate: AppUpdaterDelegate.shared)

        // Initialize the settings window controller with the updater controller
        SettingsWindowController.shared.setUpdaterController(updaterController)
        
        // Pre-warm Face ID initial static frame cache for zero-delay rendering from frame 0
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

            if enableLaunchpad {
                Button(loc("Open Launchpad")) {
                    DispatchQueue.main.async {
                        LaunchpadWindowController.shared.toggle()
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
    // Auto-close timers belong to the display that opened the notch. A single
    // shared task lets opening one display cancel the timer for another one.
    var closeNotchTasks: [String: Task<Void, Never>] = [:]
    private var previousScreens: [NSScreen]?
    private var onboardingWindowController: NSWindowController?
    private var screenLockedObserver: Any?
    private var screenUnlockedObserver: Any?
    private var screenLockedObservers: [Any] = []
    private var workspaceLockObservers: [NSObjectProtocol] = []
    private var isScreenLocked: Bool = false
    private var windowScreenDidChangeObservers: [Any] = []
    private var dragDetectors: [String: DragDetector] = [:] // UUID -> DragDetector
    private var dragExitDebounceTasks: [String: Task<Void, Never>] = [:]
    private var shelfDragAutoCloseTasks: [String: Task<Void, Never>] = [:]
    private var outsideClickMonitor: Any?
    private(set) var faceIDCameraWindow: NSWindow?
    private(set) var faceIDCameraVM: NotchPulseViewModel?

    func resetAllDropAndDragTargeting() {
        for vm in viewModels.values {
            vm.dragDetectorTargeting = false
            vm.dropZoneTargeting = false
            vm.shareDropTargeting = false
            vm.shelfDropTargeting = false
            vm.anyDropZoneTargeting = false
            vm.isCurrentlyDraggingGlobal = false
            vm.dropEvent = false
        }
        vm.dragDetectorTargeting = false
        vm.dropZoneTargeting = false
        vm.shareDropTargeting = false
        vm.shelfDropTargeting = false
        vm.anyDropZoneTargeting = false
        vm.isCurrentlyDraggingGlobal = false
        vm.dropEvent = false
    }

    /// Resolves one display's state for every display-aware event path.
    ///
    /// In all-displays mode the UUID is the source of truth. Falling back to
    /// the singleton VM in that mode makes a drag, shortcut, or preview on an
    /// external display mutate the hidden single-display state instead.
    private func viewModel(for screen: NSScreen?) -> NotchPulseViewModel? {
        guard let screen else { return Defaults[.showOnAllDisplays] ? nil : vm }
        guard Defaults[.showOnAllDisplays] else { return vm }
        guard let uuid = screen.displayUUID else { return nil }
        return viewModels[uuid]
    }

    private func notchWindow(for screen: NSScreen) -> NotchPulseSkyLightWindow? {
        if Defaults[.showOnAllDisplays] {
            guard let uuid = screen.displayUUID else { return nil }
            return windows[uuid] as? NotchPulseSkyLightWindow
        }
        return window as? NotchPulseSkyLightWindow
    }

    private func screenUnderPointer() -> NSScreen? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(location) }) ?? NSScreen.main
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
        closeNotchTasks.values.forEach { $0.cancel() }
        closeNotchTasks.removeAll()
        cleanupWindows()
        cleanupDragDetectors()
        LaunchpadSystemInterceptor.shared.restoreSystemTrackpadGestureIfNeeded()
        FaceIDOverlayController.shared.disarm()
        LockScreenMediaWindow.shared.orderOut(nil)
        DisplayShadeManager.shared.removeAllShades()
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
        LaunchpadSystemInterceptor.shared.teardown()
        DockPreviewManager.shared.teardown()
        cleanupDragDetectors()
        cleanupWindows()
        MusicManager.shared.destroy()
        FanHelperManager.shared.resetToAutoOnQuit()
        XPCHelperClient.shared.stopMonitoringAccessibilityAuthorization()
        LockScreenWakeObserver.shared.cleanup()
    }

    @MainActor
    func onScreenLocked(_ notification: Notification) {
        isScreenLocked = true
        LaunchpadWindowController.shared.dismiss(restorePreviousApp: false)

        self.vm.hideOnClosed = false
        for (_, subVm) in self.viewModels {
            subVm.hideOnClosed = false
        }

        collapseAllNotches(force: true)
        if Defaults[.enableClipboardManager] {
            ClipboardManager.shared.stopMonitoring()
        }
        SystemMonitorManager.shared.stopMonitoring()
        
        let shouldKeepWindow = Defaults[.showOnLockScreen]
        if !shouldKeepWindow {
            if NotchPulseFaceIDSettings.shared.isFaceUnlockEnabled {
                // Allow Face ID overlay to take over seamlessly before tearing down desktop windows
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(120))
                    guard let self, self.isScreenLocked else { return }
                    self.cleanupWindows()
                }
            } else {
                cleanupWindows()
            }
        } else {
            enableSkyLightOnAllWindows()
        }

        // On-demand Face ID ML warmup: Pre-warm ArcFace Neural Engine model only when screen is locked
        if NotchPulseFaceIDSettings.shared.isFaceUnlockEnabled {
            ArcFaceEmbedder.warmUp()
        }
    }

    @MainActor
    func collapseAllNotches(force: Bool = true) {
        SharingStateManager.shared.preventNotchClose = false
        for viewModel in viewModels.values {
            viewModel.isShelfPinned = false
            viewModel.isCalendarPinned = false
            viewModel.isCalendarFullMonthExpanded = false
        }
        vm.isShelfPinned = false
        vm.isCalendarPinned = false
        vm.isCalendarFullMonthExpanded = false
        withAnimation(.spring(response: 0.45, dampingFraction: 1.0)) {
            self.vm.close(force: force)
            for (_, subVm) in self.viewModels {
                subVm.close(force: force)
            }
        }
        self.coordinator.dismissExpandingView(animated: false)
        self.coordinator.toggleSneakPeek(status: false, type: .music)
        SystemMonitorManager.shared.stopMonitoring()
    }

    @MainActor
    func onScreenUnlocked(_ notification: Notification) {
        isScreenLocked = false
        LockScreenWakeObserver.shared.handleUnlockTransition()
        setupDetectors() // Re-enable Ghost Windows, Radar and Hover Detectors after unlocking
        if Defaults[.enableClipboardManager] {
            ClipboardManager.shared.startMonitoring()
        }
        FullscreenMediaDetector.shared.reevaluate()
        
        // Check for updates when unlocking if automatic checks are enabled
        if let updater = SettingsWindowController.shared.updaterController?.updater,
           updater.automaticallyChecksForUpdates {
            updater.checkForUpdatesInBackground()
        }
        
        let shouldKeepWindow = Defaults[.showOnLockScreen]
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
                
                // Keep Lock Screen media card visible in lock space synchronously with Notch
                LockScreenWakeObserver.shared.updateLockScreenMediaWindowVisibility()
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

    private func cleanupWindows() {
        // Always tear down both display modes. The setting can change while a
        // previous mode is still animating, so choosing one mode from the new
        // preference can leave an orphaned window or view model alive.
        closeNotchTasks.values.forEach { $0.cancel() }
        closeNotchTasks.removeAll()
        for viewModel in viewModels.values {
            viewModel.close(force: true)
        }
        vm.close(force: true)

        for displayWindow in Array(windows.values) {
            displayWindow.close()
            NotchSpaceManager.shared.notchSpace.windows.remove(displayWindow)
        }
        windows.removeAll()
        viewModels.removeAll()

        if let window {
            window.close()
            NotchSpaceManager.shared.notchSpace.windows.remove(window)
            self.window = nil
        }
        windowScreenDidChangeObservers.forEach { NotificationCenter.default.removeObserver($0) }
        windowScreenDidChangeObservers.removeAll()

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
        shelfDragAutoCloseTasks.values.forEach { $0.cancel() }
        shelfDragAutoCloseTasks.removeAll()
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
        windows.values.forEach { ($0 as? NotchPulseSkyLightWindow)?.endFileDragTargeting() }
        (window as? NotchPulseSkyLightWindow)?.endFileDragTargeting()
        dragDetectors.values.forEach { detector in
            detector.stopMonitoring()
        }
        dragDetectors.removeAll()
        resetAllDropAndDragTargeting()
    }

    func setupDetectors() {
        setupDragDetectors()
        setupOutsideClickMonitor()
    }

    private func setupOutsideClickMonitor() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleOutsideClick()
            }
        }
    }

    private func handleOutsideClick() {
        // If a context menu or modal/sharing session is active, let them handle dismissal
        guard !MenuTrackingManager.shared.isMenuTracking,
              !SharingStateManager.shared.preventNotchClose else {
            return
        }

        // If shelf selection is active, clear it when clicking outside
        if ShelfSelectionModel.shared.hasSelection {
            ShelfSelectionModel.shared.clear()
        }

        // Close any unpinned open notches
        let allVMs = Array(viewModels.values) + [vm]
        for targetVM in allVMs where targetVM.notchState == .open {
            if !targetVM.isShelfPinned && !targetVM.isCalendarPinned && !FeatureTourController.shared.isTourActive {
                targetVM.close()
            }
        }
    }

    private func setupDragDetectors() {
        cleanupDragDetectors()

        guard Defaults[.notchPulseShelf], Defaults[.shelfDragOpenPadding] > 0 else { return }

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
            guard let targetVM = self.viewModel(for: screen) else { return .zero }
            let padding = CGFloat(Defaults[.shelfDragOpenPadding])
            
            let isDynamicIsland = Defaults[.notchStyle] == .dynamicIsland
            let topOffset = isDynamicIsland
                ? effectiveDynamicIslandTopOffset(for: screen)
                : 0
            
            let targetSize: CGSize
            if targetVM.notchState == .open {
                targetSize = CGSize(
                    width: max(targetVM.notchSize.width, max(openNotchSize.width, CGFloat(Defaults[.notchOpenWidth]))),
                    height: max(targetVM.effectiveOpenHeight, openNotchSize.height)
                )
            } else {
                let closedSize = targetVM.closedNotchSize
                let closedWidth = isDynamicIsland
                    ? compactDynamicIslandWidth
                    : (closedSize.width > 0 ? closedSize.width : 175.0)
                let closedHeight = isDynamicIsland
                    ? compactDynamicIslandHeight
                    : (targetVM.effectiveClosedNotchHeight > 0 ? targetVM.effectiveClosedNotchHeight : 34.0)
                targetSize = CGSize(width: closedWidth, height: closedHeight)
            }
            return DragDetector.activationRegion(
                screenFrame: screenFrame,
                targetSize: targetSize,
                topOffset: topOffset,
                padding: padding
            )
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

    private func scheduleShelfDragAutoClose(for screen: NSScreen) {
        guard let uuid = screen.displayUUID else { return }
        shelfDragAutoCloseTasks[uuid]?.cancel()

        let delay = Defaults[.shakeAutoCloseDelay]
        guard delay > 0 else { return }

        shelfDragAutoCloseTasks[uuid] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(delay * 1000)))
            guard !Task.isCancelled, let self = self else { return }
            guard let targetVM = self.viewModel(for: screen) else { return }

            // If dropEvent was received, or shelf is pinned, leave it open
            if targetVM.dropEvent || targetVM.isShelfPinned || targetVM.isCalendarPinned {
                return
            }

            // While the user holds the file directly over the shelf drop area, don't close
            if targetVM.shelfDropTargeting || targetVM.shareDropTargeting || targetVM.dropZoneTargeting {
                return
            }

            targetVM.dragDetectorTargeting = false
            targetVM.isCurrentlyDraggingGlobal = false
            self.notchWindow(for: screen)?.endFileDragTargeting()
            if targetVM.notchState == .open {
                targetVM.close()
            }
        }
    }

    private func handleDragEntersNotchRegion(onScreen screen: NSScreen) {
        guard let uuid = screen.displayUUID else { return }
        
        dragExitDebounceTasks[uuid]?.cancel()
        dragExitDebounceTasks[uuid] = nil
        
        guard let targetVM = viewModel(for: screen) else { return }
        notchWindow(for: screen)?.beginFileDragTargeting()
        targetVM.isCurrentlyDraggingGlobal = true
        targetVM.dragDetectorTargeting = true
        
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            targetVM.open(targetView: .shelf)
        }

        scheduleShelfDragAutoClose(for: screen)
    }

    private func handleDragExitsNotchRegion(onScreen screen: NSScreen) {
        guard let uuid = screen.displayUUID else { return }
        
        dragExitDebounceTasks[uuid]?.cancel()
        shelfDragAutoCloseTasks[uuid]?.cancel()
        shelfDragAutoCloseTasks[uuid] = nil
        
        guard let targetVM = viewModel(for: screen) else { return }
        targetVM.dragDetectorTargeting = false
        
        dragExitDebounceTasks[uuid] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, let self = self else { return }
            
            guard let targetVM = self.viewModel(for: screen) else { return }
            guard !targetVM.anyDropZoneTargeting && !targetVM.dropEvent else { return }

            targetVM.isCurrentlyDraggingGlobal = false
            self.notchWindow(for: screen)?.endFileDragTargeting()
            if !targetVM.isShelfPinned && !targetVM.isCalendarPinned && targetVM.notchState == .open {
                targetVM.close()
            }
        }
    }

    private func handleDragEnded(onScreen screen: NSScreen) {
        guard let uuid = screen.displayUUID else { return }
        
        dragExitDebounceTasks[uuid]?.cancel()
        shelfDragAutoCloseTasks[uuid]?.cancel()
        shelfDragAutoCloseTasks[uuid] = nil
        
        guard let targetVM = viewModel(for: screen) else { return }
        targetVM.dragDetectorTargeting = false
        targetVM.isCurrentlyDraggingGlobal = false
        
        dragExitDebounceTasks[uuid] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self = self else { return }
            guard let targetVM = self.viewModel(for: screen) else { return }
            self.notchWindow(for: screen)?.endFileDragTargeting()
            
            // If dropEvent was received, leave shelf open so the user can see their added item
            if targetVM.dropEvent {
                return
            }
            if !targetVM.isShelfPinned && !targetVM.isCalendarPinned && !targetVM.anyDropZoneTargeting && targetVM.notchState == .open {
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

        let hostingView = FirstMouseHostingView(
            rootView: ContentView()
                .environmentObject(viewModel)
        )
        window.contentView = hostingView

        window.orderFrontRegardless()
        NotchSpaceManager.shared.notchSpace.windows.insert(window)

        // Observe when the window's screen changes so we can update drag detectors
        let obs = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeScreenNotification,
            object: window,
            queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.setupDetectors()
                }
        }
        windowScreenDidChangeObservers.append(obs)
        return window
    }

    @MainActor
    func updateFaceIDCameraWindow() {
        if let window = faceIDCameraWindow {
            window.close()
            NotchSpaceManager.shared.notchSpace.windows.remove(window)
            faceIDCameraWindow = nil
            faceIDCameraVM = nil
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
        window.orderFrontRegardless()
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

        // Start the Face ID model warm-up before optional media and clipboard work.
        if NotchPulseFaceIDSettings.shared.isFaceUnlockEnabled {
            ArcFaceEmbedder.warmUp()
        }

        // Initialize clipboard history only when the feature is enabled.
        if Defaults[.enableClipboardManager] {
            _ = ClipboardManager.shared
        }

        // Pre-warm MusicManager immediately at app launch
        _ = MusicManager.shared

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
                self.cleanupWindows()
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
            forName: Notification.Name.closeNotchPreview, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                SharingStateManager.shared.preventNotchClose = false
                withAnimation(.spring(response: 0.45, dampingFraction: 1.0)) {
                    self.vm.close(force: true)
                    for subVm in self.viewModels.values {
                        subVm.close(force: true)
                    }
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
            let targetVM = self.viewModel(for: self.screenUnderPointer()) ?? self.vm
            guard targetVM.notchState == .closed else { return }
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

                let viewModel = self.viewModel(for: self.screenUnderPointer()) ?? self.vm
                let displayKey = viewModel.screenUUID ?? "single-display"

                self.closeNotchTasks[displayKey]?.cancel()
                self.closeNotchTasks[displayKey] = nil

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
                    self.closeNotchTasks[displayKey] = task
                case .open:
                    await MainActor.run {
                        viewModel.close()
                    }
                }
            }
        }

        KeyboardShortcuts.onKeyDown(for: .toggleLaunchpad) {
            LaunchpadWindowController.shared.toggle()
        }

        LaunchpadWindowController.shared.configureHotCornerMonitor()
        LaunchpadWindowController.shared.configureSystemLaunchpadInterceptor()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            LaunchpadWindowController.shared.prewarmIfNeeded()
        }

        DockPreviewManager.shared.configure()

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

        let isFirstInstall = coordinator.firstLaunch
        let isUpdated = isAppUpdated()

        if isFirstInstall {
            DispatchQueue.main.async {
                self.showOnboardingWindow()
            }
            playWelcomeSound()
        }

        // ⛔️ CRITICAL RULE - DO NOT DELETE OR REMOVE THIS LOGIC (CẤM XOÁ)!
        // Automatically request/re-verify system permissions upfront on initial install or after app update.
        // This ensures users do not have to manually re-grant or hunt down Camera, Accessibility, Calendar,
        // and Reminders permissions in Settings after updating NotchPulse.
        if isFirstInstall || isUpdated {
            requestPermissionsUpfrontIfNeeded()
        }

        // NotchPulse 2.0: Initialize Face ID & Lock Screen Observer
        _ = LockScreenWakeObserver.shared
        _ = NotchPulseFaceUnlockCoordinator.shared
        ArcFaceEmbedder.warmUp()
        _ = BluetoothHeadphoneManager.shared

        // Proactively verify & pre-warm Keychain authorization off the main thread
        if NotchPulseVault.hasSessionKey() {
            NotchPulseVault.preflightKeychainAuthorization()
        }

        previousScreens = NSScreen.screens

        // Optional UI preloading is independent of the early Face ID model warm-up.
        // Keep it off by default to avoid constructing every expanded tab at launch.
        if Defaults[.preloadExpandedNotch] {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(6))
                guard let self, !self.isUserInitiatedQuit, !self.isScreenLocked,
                      Defaults[.preloadExpandedNotch] else { return }
                let vm = self.vm
                guard vm.notchState == .closed, !SharingStateManager.shared.preventNotchClose else { return }
                vm.open()
                try? await Task.sleep(for: .milliseconds(650))
                guard vm.notchState == .open, !self.isScreenLocked,
                      !SharingStateManager.shared.preventNotchClose else { return }
                withAnimation(NotchPulseViewModel.notchCloseSpring) {
                    vm.close()
                }
            }
        }

        // Automatically check for updates in background shortly after launch
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self = self, !self.isUserInitiatedQuit else { return }
            if let updater = SettingsWindowController.shared.updaterController?.updater,
               updater.automaticallyChecksForUpdates {
                updater.checkForUpdatesInBackground()
            }
        }
    }

    // ⛔️ CRITICAL RULE - DO NOT DELETE OR REMOVE THIS METHOD (CẤM XOÁ)!
    // Proactively requests & pre-warms required system permissions on launch after an install or update.
    // This eliminates the need for users to manually re-grant or turn on Accessibility, Camera,
    // Calendar, Reminders, and Bluetooth across app updates.
    @MainActor
    private func requestPermissionsUpfrontIfNeeded() {
        Task {
            // 1. Camera / Live Mirror / Face ID Permission
            let cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
            if cameraStatus == .notDetermined {
                _ = await AVCaptureDevice.requestAccess(for: .video)
            }

            // 2. Accessibility Permission (for Launchpad, Dock Preview, Lock screen auto-unlock & HUD)
            if !AXIsProcessTrusted() {
                try? await Task.sleep(for: .milliseconds(350))
                XPCHelperClient.shared.requestAccessibilityAuthorization()
            }

            // 3. Calendar & Reminders Permissions (for Notch Schedule & Reminders)
            try? await Task.sleep(for: .milliseconds(350))
            if EKEventStore.authorizationStatus(for: .event) == .notDetermined {
                await CalendarManager.shared.checkCalendarAuthorization()
            }
            if EKEventStore.authorizationStatus(for: .reminder) == .notDetermined {
                await CalendarManager.shared.checkReminderAuthorization()
            }

            // 4. Pre-warm secure vault session & authorize Keychain on desktop
            if NotchPulseFaceIDSettings.shared.isFaceUnlockEnabled || NotchPulseVault.hasStoredPassword() {
                NotchPulseVault.preflightKeychainAuthorization()
            }

            // 5. Refresh Bluetooth permissions & headphone discovery
            PermissionsManager.shared.refreshBluetooth()
        }
    }

    func playWelcomeSound() {
        let audioPlayer = AudioPlayer()
        audioPlayer.play(fileName: "notchpulse", fileExtension: "m4a")
    }

    func deviceHasNotch() -> Bool {
        DeviceHardwareInfo.deviceHasPhysicalNotch
    }

    @MainActor func screenConfigurationDidChange() {
        NSScreenUUIDCache.shared.rebuildCache()
        NotchPulseCameraDeviceCatalog.invalidateTargetScreenCache()
        previousScreens = NSScreen.screens

        adjustWindowPosition(changeAlpha: false)
        setupDetectors()
    }

    func adjustWindowPosition(changeAlpha: Bool = false) {
        if Defaults[.showOnAllDisplays] {
            let currentScreenUUIDs = Set(NSScreen.screens.compactMap { $0.displayUUID })

            // Remove windows for screens that no longer exist
            for uuid in Array(windows.keys) where !currentScreenUUIDs.contains(uuid) {
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
            }
            // 2. Fall back to main screen if active screen not resolved
            else {
                let fallback = NSScreen.main ?? NSScreen.screens.first
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
