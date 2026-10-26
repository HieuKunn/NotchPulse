import Combine
import Defaults
import SwiftUI

class NotchPulseViewModel: NSObject, ObservableObject {
    static let notchSpring = Animation.interactiveSpring(response: 0.38, dampingFraction: 0.8)
    static let notchCloseSpring = Animation.interactiveSpring(response: 0.38, dampingFraction: 0.8)

    @ObservedObject var coordinator = NotchPulseViewCoordinator.shared
    @ObservedObject var detector = FullscreenMediaDetector.shared

    let animationLibrary: NotchPulseAnimations = .init()
    let animation: Animation?

    @Published var contentType: ContentType = .normal
    @Published private(set) var notchState: NotchState = .closed

    @Published var dragDetectorTargeting: Bool = false
    @Published var generalDropTargeting: Bool = false
    @Published var dropZoneTargeting: Bool = false
    @Published var shareDropTargeting: Bool = false
    @Published var shelfDropTargeting: Bool = false
    @Published var dropEvent: Bool = false
    @Published var anyDropZoneTargeting: Bool = false
    @Published var isCurrentlyDraggingGlobal: Bool = false
    @Published var customOpenHeight: CGFloat? = nil
    var effectiveOpenHeight: CGFloat {
        if coordinator.currentView == .clipboard {
            return ClipboardNotchView.preferredHeight
        }
        return customOpenHeight ?? notchSize.height
    }
    var cancellables: Set<AnyCancellable> = []
    
    @Published var hideOnClosed: Bool = false
    @Published var isHoverRevealed: Bool = false

    @Published var isBatteryPopoverActive: Bool = false
    
    @Published var featureTourTarget: String? = nil

    @Published var screenUUID: String?

    @Published var notchSize: CGSize = getClosedNotchSize()
    @Published var closedNotchSize: CGSize = getClosedNotchSize()
    
    let webcamManager = WebcamManager.shared
    @Published var isCameraExpanded: Bool = false
    @Published var isRequestingAuthorization: Bool = false
    
    deinit {
        destroy()
    }

    func destroy() {
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
    }

    init(screenUUID: String? = nil) {
        animation = animationLibrary.animation

        super.init()
        
        self.screenUUID = screenUUID
        notchSize = getClosedNotchSize(screenUUID: screenUUID)
        closedNotchSize = notchSize

        // Only actual shelf drop-zones and the drag-detector trigger anyDropZoneTargeting.
        // generalDropTargeting (dragging app windows near the notch) is intentionally excluded
        // so that moving app windows close to the notch never opens the shelf.
        Publishers.MergeMany(
            $shareDropTargeting.map { _ in () },
            $shelfDropTargeting.map { _ in () },
            $dropZoneTargeting.map { _ in () },
            $dragDetectorTargeting.map { _ in () }
        )
        .map { [weak self] _ -> Bool in
            guard let self = self else { return false }
            return self.shareDropTargeting || self.shelfDropTargeting || self.dropZoneTargeting || self.dragDetectorTargeting
        }
        .assign(to: \.anyDropZoneTargeting, on: self)
        .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .notchDidOpen)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self = self else { return }
                guard !SharingStateManager.shared.preventNotchClose else { return }
                guard let activeVM = notification.object as? NotchPulseViewModel else { return }
                // Rule: Only 1 notch open at any time across all displays!
                // If another display's notch opened, this notch must close immediately and unpin.
                if self !== activeVM && self.notchState == .open && !FeatureTourController.shared.isTourActive {
                    ShelfStateViewModel.shared.isPinned = false
                    CalendarStateViewModel.shared.isPinned = false
                    SharingStateManager.shared.preventNotchClose = false
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        self.close(force: true)
                    }
                }
            }
            .store(in: &cancellables)
        
        setupDetectorObserver()
    }
    
    private func setupDetectorObserver() {
        // Publisher for the user’s fullscreen detection setting
        let enabledPublisher = Defaults
            .publisher(.hideNotchOption)
            .map(\.newValue)
            .map { $0 != .never }
            .removeDuplicates()

        // Publisher for the current screen UUID (non-nil, distinct)
        let screenPublisher = $screenUUID
            .compactMap { $0 }
            .removeDuplicates()

        // Publisher for fullscreen status dictionary
        let fullscreenStatusPublisher = detector.$fullscreenStatus
            .removeDuplicates()

        let lockScreenPublisher = LockScreenWakeObserver.shared.$isScreenLocked
            .removeDuplicates()

        // Combine all four: screen UUID, fullscreen status, enabled setting, and lock screen status
        Publishers.CombineLatest4(screenPublisher, fullscreenStatusPublisher, enabledPublisher, lockScreenPublisher)
            .map { screenUUID, fullscreenStatus, enabled, isLocked in
                let isFullscreen = fullscreenStatus[screenUUID] ?? false
                let actuallyLocked = isLocked || NotchPulseLockMonitor.isScreenActuallyLocked()
                if actuallyLocked {
                    return false
                }
                return enabled && isFullscreen
            }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] shouldHide in
                withAnimation(.smooth) {
                    self?.hideOnClosed = shouldHide
                    if shouldHide {
                        self?.isHoverRevealed = false
                        if self?.notchState == .open {
                            self?.close(force: true)
                        }
                    } else {
                        self?.isHoverRevealed = false
                    }
                }
            }
            .store(in: &cancellables)

        DistributedNotificationCenter.default().publisher(for: NSNotification.Name("com.apple.screenIsLocked"))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                withAnimation(.smooth) {
                    self?.hideOnClosed = false
                    self?.isHoverRevealed = false
                }
            }
            .store(in: &cancellables)

        DistributedNotificationCenter.default().publisher(for: NSNotification.Name("com.apple.screenIsUnlocked"))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                let isFullscreen = self.detector.fullscreenStatus[self.screenUUID ?? ""] ?? false
                let enabled = Defaults[.hideNotchOption] != .never
                withAnimation(.smooth) {
                    self.hideOnClosed = enabled && isFullscreen
                    self.isHoverRevealed = false
                }
            }
            .store(in: &cancellables)
    }

    // Computed property for effective notch height
    var effectiveClosedNotchHeight: CGFloat {
        return closedNotchSize.height
    }

    var chinHeight: CGFloat {
        if !Defaults[.hideTitleBar] || Defaults[.notchStyle] == .dynamicIsland {
            return 0
        }

        guard let currentScreen = screenUUID.flatMap({ NSScreen.screen(withUUID: $0) }) else {
            return 0
        }

        if notchState == .open { return 0 }

        let menuBarHeight = currentScreen.frame.maxY - currentScreen.visibleFrame.maxY
        let currentHeight = effectiveClosedNotchHeight

        if currentHeight == 0 { return 0 }

        return max(0, menuBarHeight - currentHeight)
    }

    func toggleCameraPreview() {
        if isRequestingAuthorization {
            return
        }

        switch webcamManager.authorizationStatus {
        case .authorized:
            if isCameraExpanded || webcamManager.isSessionRunning {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                    isCameraExpanded = false
                }
                webcamManager.stopSession()
            } else if webcamManager.cameraAvailable {
                if NotchPulseViewCoordinator.shared.currentView != .home {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                        NotchPulseViewCoordinator.shared.currentView = .home
                    }
                }
                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                    isCameraExpanded = true
                }
                webcamManager.startSession()
            }

        case .denied, .restricted:
            DispatchQueue.main.async {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)

                let alert = NSAlert()
                alert.messageText = "Camera Access Required"
                alert.informativeText = "Please allow camera access in System Settings."
                alert.addButton(withTitle: "Open Settings")
                alert.addButton(withTitle: "Cancel")

                if alert.runModal() == .alertFirstButtonReturn {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                        NSWorkspace.shared.open(url)
                    }
                }

                NSApp.setActivationPolicy(.accessory)
                NSApp.deactivate()
            }

        case .notDetermined:
            isRequestingAuthorization = true
            webcamManager.checkAndRequestVideoAuthorization()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.isRequestingAuthorization = false
            }

        default:
            break
        }
    }
    
    func isMouseHovering(position: NSPoint = NSEvent.mouseLocation) -> Bool {
        if hideOnClosed && !isHoverRevealed && !NotchPulseLockMonitor.isScreenActuallyLocked() && notchState == .closed { return false }
        guard let frame = getScreenFrame(screenUUID) else { return false }
        let screen = resolveScreen(screenUUID: screenUUID)
        let isDynamicIsland = Defaults[.notchStyle] == .dynamicIsland
        let topOffset = isDynamicIsland ? effectiveDynamicIslandTopOffset(for: screen) : 0
        let currentWidth = notchState == .open ? (isDynamicIsland ? notchSize.width : (notchSize.width + cornerRadiusInsets.opened.top * 2)) : (isDynamicIsland ? compactDynamicIslandWidth : closedNotchSize.width)
        let currentHeight = notchState == .open ? effectiveOpenHeight : (isDynamicIsland ? 32 : closedNotchSize.height)
        
        let extraPad: CGFloat = (notchState == .closed && Defaults[.extendHoverArea]) ? CGFloat(Defaults[.hoverAreaPadding]) : 0
        let baseY = frame.maxY - currentHeight - topOffset - extraPad
        let baseX = frame.midX - currentWidth / 2 - extraPad
        let totalW = currentWidth + (extraPad * 2)
        
        return position.y >= baseY && position.y <= frame.maxY && position.x >= baseX && position.x <= baseX + totalW
    }

    func open() {
        CalendarStateViewModel.shared.isFullMonthExpanded = false
        self.coordinator.dismissExpandingView(animated: false)
        self.coordinator.sneakPeek.show = false
        self.notchSize = openNotchSize
        self.notchState = .open
        if coordinator.currentView == .clipboard {
            self.customOpenHeight = ClipboardNotchView.preferredHeight
        }
        
        MusicManager.shared.isUIActive = true
        MusicManager.shared.forceUpdate()

        // Rule: Only 1 notch open at any time across all displays!
        NotificationCenter.default.post(name: .notchDidOpen, object: self)
    }

    func close(force: Bool = false) {
        // Keep notch open during feature tour unless forced (e.g. dismissing tour)
        if !force && FeatureTourController.shared.isTourActive {
            return
        }
        self.customOpenHeight = nil
        CalendarStateViewModel.shared.isPinned = false
        CalendarStateViewModel.shared.isFullMonthExpanded = false
        if force {
            ShelfStateViewModel.shared.isPinned = false
        }
        // Do not close while a share picker or sharing service is active unless forced (e.g. on lock screen)
        if !force && SharingStateManager.shared.preventNotchClose {
            return
        }
        guard force || notchState != .closed else { return }
        self.notchSize = getClosedNotchSize(screenUUID: self.screenUUID)
        self.closedNotchSize = self.notchSize
        self.notchState = .closed
        self.isBatteryPopoverActive = false
        self.coordinator.dismissExpandingView(animated: false)
        self.coordinator.sneakPeek.show = false

        self.dragDetectorTargeting = false
        self.dropZoneTargeting = false
        self.generalDropTargeting = false
        self.anyDropZoneTargeting = false
        self.dropEvent = false

        if !LockScreenMediaWindow.shared.isWindowVisible {
            MusicManager.shared.isUIActive = false
        }
        Task(priority: .background) {
            ThumbnailService.shared.clearCache()
        }

        if self.isCameraExpanded || self.webcamManager.isSessionRunning {
            self.isCameraExpanded = false
            self.webcamManager.stopSession()
        }

        // Reset currentView to .home on close quietly after the collapse completes (350ms),
        // preventing internal tab-switch animations from clashing with the notch collapse animation
        if !SharingStateManager.shared.preventNotchClose && (force || (!coordinator.openLastTabByDefault && !ShelfStateViewModel.shared.isPinned && !CalendarStateViewModel.shared.isPinned)) {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(350))
                guard let self = self, self.notchState == .closed else { return }
                self.coordinator.currentView = .home
            }
        }
    }

    func closeHello() {
        Task { @MainActor in
            withAnimation(animationLibrary.animation) {
                coordinator.helloAnimationRunning = false
                close()
            }
        }
    }
}
