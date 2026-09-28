//
//  NotchPulseViewModel.swift
//  NotchPulse
//
//  Created by Harsh Vardhan  Goswami  on 04/08/24.
//

import Combine
import Defaults
import SwiftUI

class NotchPulseViewModel: NSObject, ObservableObject {
    @ObservedObject var coordinator = NotchPulseViewCoordinator.shared
    @ObservedObject var detector = FullscreenMediaDetector.shared

    let animationLibrary: NotchPulseAnimations = .init()
    let animation: Animation?

    @Published var contentType: ContentType = .normal
    @Published private(set) var notchState: NotchState = .closed

    @Published var dragDetectorTargeting: Bool = false
    @Published var generalDropTargeting: Bool = false
    @Published var dropZoneTargeting: Bool = false
    @Published var dropEvent: Bool = false
    @Published var anyDropZoneTargeting: Bool = false
    @Published var isCurrentlyDraggingGlobal: Bool = false
    @Published var isHoveringFromRadar: Bool = false
    @Published var customOpenHeight: CGFloat? = nil
    var cancellables: Set<AnyCancellable> = []
    
    @Published var hideOnClosed: Bool = true

    @Published var edgeAutoOpenActive: Bool = false
    @Published var isHoveringCalendar: Bool = false
    @Published var isHoveringClipboard: Bool = false
    @Published var clipboardScrolledToBottom: Bool = true
    @Published var isBatteryPopoverActive: Bool = false

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
            $dropZoneTargeting.map { _ in () },
            $dragDetectorTargeting.map { _ in () }
        )
        .map { [weak self] _ -> Bool in
            guard let self = self else { return false }
            return self.dropZoneTargeting || self.dragDetectorTargeting
        }
        .assign(to: \.anyDropZoneTargeting, on: self)
        .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .notchDidOpen)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self = self else { return }
                guard let activeVM = notification.object as? NotchPulseViewModel else { return }
                // Rule: Only 1 notch open at any time across all displays!
                // If another display's notch opened, this notch must close immediately and unpin.
                if self !== activeVM && self.notchState == .open {
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

        // Combine all three: screen UUID, fullscreen status, and enabled setting
        Publishers.CombineLatest3(screenPublisher, fullscreenStatusPublisher, enabledPublisher)
            .map { screenUUID, fullscreenStatus, enabled in
                let isFullscreen = fullscreenStatus[screenUUID] ?? false
                return enabled && isFullscreen
            }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] shouldHide in
                withAnimation(.smooth) {
                    self?.hideOnClosed = shouldHide
                }
            }
            .store(in: &cancellables)
    }

    // Computed property for effective notch height
    var effectiveClosedNotchHeight: CGFloat {
        let currentScreen = screenUUID.flatMap { NSScreen.screen(withUUID: $0) }
        let noNotchAndFullscreen = hideOnClosed && (currentScreen?.safeAreaInsets.top ?? 0 <= 0 || currentScreen == nil)
        return noNotchAndFullscreen ? 0 : closedNotchSize.height
    }

    var chinHeight: CGFloat {
        if !Defaults[.hideTitleBar] {
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
        guard let frame = getScreenFrame(screenUUID) else { return false }
        let isDynamicIsland = Defaults[.notchStyle] == .dynamicIsland
        let topOffset = isDynamicIsland ? Defaults[.dynamicIslandTopOffset] : 0
        let currentWidth = notchState == .open ? openNotchWidth : (isDynamicIsland ? 210 : closedNotchSize.width)
        let currentHeight = notchState == .open ? (customOpenHeight ?? openNotchSize.height) : (isDynamicIsland ? 32 : closedNotchSize.height)
        
        let baseY = frame.maxY - currentHeight - topOffset
        let baseX = frame.midX - currentWidth / 2
        
        return position.y >= (baseY - 10) && position.y <= frame.maxY && position.x >= baseX && position.x <= baseX + currentWidth
    }

    func open() {
        self.notchSize = openNotchSize
        self.notchState = .open
        
        MusicManager.shared.isUIActive = true
        // Force music information update when notch is opened
        MusicManager.shared.forceUpdate()

        // Rule: Only 1 notch open at any time across all displays!
        NotificationCenter.default.post(name: .notchDidOpen, object: self)
    }

    func close(force: Bool = false) {
        self.customOpenHeight = nil
        // Do not close while a share picker or sharing service is active unless forced (e.g. on lock screen)
        if !force && SharingStateManager.shared.preventNotchClose {
            return
        }
        self.notchSize = getClosedNotchSize(screenUUID: self.screenUUID)
        self.closedNotchSize = self.notchSize
        self.notchState = .closed
        self.isBatteryPopoverActive = false
        self.coordinator.sneakPeek.show = false
        self.edgeAutoOpenActive = false

        self.dragDetectorTargeting = false
        self.dropZoneTargeting = false
        self.generalDropTargeting = false
        self.anyDropZoneTargeting = false
        self.dropEvent = false
        self.isHoveringFromRadar = false
        self.isHoveringClipboard = false
        self.clipboardScrolledToBottom = true

        if !LockScreenMediaWindow.shared.isWindowVisible {
            MusicManager.shared.isUIActive = false
        }
        Task {
            await ThumbnailService.shared.clearCache()
        }

        if self.isCameraExpanded || self.webcamManager.isSessionRunning {
            self.isCameraExpanded = false
            self.webcamManager.stopSession()
        }

        // Reset currentView to .home on close unless user enabled openLastTabByDefault or pinned Shelf (always reset if forced)
        if force || (!coordinator.openLastTabByDefault && !ShelfStateViewModel.shared.isPinned) {
            coordinator.currentView = .home
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
