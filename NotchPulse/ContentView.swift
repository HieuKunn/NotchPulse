import AVFoundation
import Combine
import Defaults
import KeyboardShortcuts
import SwiftUI
import SwiftUIIntrospect
import UniformTypeIdentifiers

@MainActor
struct ContentView: View {
    @EnvironmentObject var vm: NotchPulseViewModel
    @ObservedObject var webcamManager = WebcamManager.shared

    @ObservedObject var coordinator = NotchPulseViewCoordinator.shared
    @ObservedObject var musicManager = MusicManager.shared

    @ObservedObject var brightnessManager = BrightnessManager.shared
    @ObservedObject var volumeManager = VolumeManager.shared
    @State private var hoverOpenTask: Task<Void, Never>?
    @State private var hoverCloseTask: Task<Void, Never>?
    @State private var isHovering: Bool = false
    @State private var isMainNotchHovered = false
    @State private var isTopEdgeHovered = false
    @State private var anyDropDebounceTask: Task<Void, Never>?
    @State private var fullscreenHoverDebounceTask: Task<Void, Never>?

    @State private var gestureProgress: CGFloat = .zero

    @State private var haptics: Bool = false

    @Namespace var albumArtNamespace

    @Default(.useMusicVisualizer) var useMusicVisualizer
    @Default(.appLanguage) var appLanguage

    @Default(.notchStyle) var notchStyle
    @Default(.dynamicIslandTopOffset) var dynamicIslandTopOffset
    @Default(.notchOpenWidth) var notchOpenWidth
    @Default(.extendHoverArea) var extendHoverArea: Bool
    @Default(.hoverAreaPadding) var hoverAreaPadding: Double

    private let animationSpring = Animation.interactiveSpring(response: 0.38, dampingFraction: 0.8, blendDuration: 0)
    private let openAnimation = Animation.spring(response: 0.38, dampingFraction: 0.8, blendDuration: 0)
    private let closeAnimation = Animation.spring(response: 0.38, dampingFraction: 0.84, blendDuration: 0)
    private var faceIDAnimation: Animation {
        let isFaceIDOpening = isFaceIDActive && faceIDOverlay.phase != .collapsing && faceIDOverlay.phase != .closed
        return isFaceIDOpening ? openAnimation : closeAnimation
    }

    @State private var isScanPulseDimmed = false
    @State private var scanPulseTask: Task<Void, Never>?
    @State private var visualIsFaceIDExpanded: Bool = false

    // CRITICAL ARCHITECTURAL NOTE: DO NOT DELETE OR WRAP WITH @ObservedObject!
    // FaceIDOverlayController is annotated with @Observable (Swift Observation framework),
    // NOT ObservableObject. Wrapping it in @ObservedObject breaks contextual type inference
    // across all phase comparisons (.closed, .scanning, etc.) and fails CI xcodebuild.
    private var faceIDOverlay: FaceIDOverlayController {
        FaceIDOverlayController.shared
    }
    @ObservedObject var lockObserver = LockScreenWakeObserver.shared
    @State private var isFaceIDSettlingAfterClose: Bool = false

    private var isEffectivelyLocked: Bool {
        lockObserver.isScreenLocked
            || NotchPulseLockMonitor.isScreenActuallyLocked()
            || faceIDOverlay.isSessionActive
            || faceIDOverlay.isArmed
            || faceIDOverlay.phase == .scanning
    }

    private var isEffectivelyLockedWithFaceID: Bool {
        isFaceIDActive || faceIDOverlay.isArmed || faceIDOverlay.phase != .closed || NotchPulseFaceIDSettings.shared.isFaceUnlockEnabled
    }

    private var isFaceIDActive: Bool {
        false
    }

    private var isFaceIDContentActive: Bool {
        false
    }

    private var isFaceIDContentVisible: Bool {
        false
    }

    private var targetIsFaceIDExpanded: Bool {
        guard isFaceIDActive else { return false }
        switch faceIDOverlay.phase {
        case .scanning, .success, .failure, .onboarding:
            return true
        case .closed, .collapsing:
            return false
        }
    }

    private func updateFaceIDExpansion() {
        let wantExpanded = targetIsFaceIDExpanded
        guard wantExpanded != visualIsFaceIDExpanded else { return }
        let anim = wantExpanded ? openAnimation : closeAnimation
        withAnimation(anim) {
            visualIsFaceIDExpanded = wantExpanded
        }
    }

    private var isMinimalScan: Bool {
        if case .onboarding = faceIDOverlay.content { return false }
        return faceIDOverlay.activeUnlockStyle == .minimal
    }

    private var currentScreen: NSScreen? {
        vm.screenUUID.flatMap { NSScreen.screen(withUUID: $0) }
            ?? NSScreen.screen(withUUID: coordinator.selectedScreenUUID)
            ?? NSScreen.main
    }

    private var hasPhysicalNotch: Bool {
        screenHasPhysicalNotch(currentScreen)
    }

    private var effectiveTopOffset: CGFloat {
        effectiveDynamicIslandTopOffset(for: currentScreen, userOffset: dynamicIslandTopOffset)
    }

    private var faceIDOpenSize: CGSize {
        let isDynamicIsland = notchStyle == .dynamicIsland
        let controller = faceIDOverlay

        if case .onboarding(let enrollmentController) = controller.content {
            return enrollmentController.panelSize
        }

        if isMinimalScan {
            if isDynamicIsland {
                return CGSize(
                    width: max(FaceIDOverlayGeometry.minimalPillOpenWidth, vm.closedNotchSize.width + 60),
                    height: baseClosedHeight
                )
            } else {
                let topR = FaceIDOverlayGeometry.minimalNotchTopRadius
                let flank = FaceIDOverlayGeometry.minimalNotchFlankWidth
                return CGSize(
                    width: vm.closedNotchSize.width + (topR * 2) + (flank * 2),
                    height: max(vm.effectiveClosedNotchHeight, FaceIDOverlayGeometry.minimalPillOpenHeight)
                )
            }
        }

        if isDynamicIsland {
            return FaceIDOverlayGeometry.pillOpenSize
        } else {
            let baseWidth = max(FaceIDOverlayGeometry.notchOpenSize.width, vm.closedNotchSize.width)
            let topR = FaceIDOverlayGeometry.openTopRadius
            return CGSize(
                width: baseWidth + (topR * 2),
                height: FaceIDOverlayGeometry.notchOpenSize.height
            )
        }
    }

    private var targetFaceIDSize: CGSize {
        if !visualIsFaceIDExpanded {
            return CGSize(
                width: isDynamicIsland ? compactDynamicIslandWidth : vm.closedNotchSize.width,
                height: baseClosedHeight
            )
        }
        return faceIDOpenSize
    }

    private var topCornerRadius: CGFloat {
        if isFaceIDActive {
            if !visualIsFaceIDExpanded {
                return ((vm.notchState == .open) && Defaults[.cornerRadiusScaling])
                         ? cornerRadiusInsets.opened.top
                         : cornerRadiusInsets.closed.top
            }
            if isMinimalScan {
                return FaceIDOverlayGeometry.minimalNotchTopRadius
            }
            return FaceIDOverlayGeometry.openTopRadius
        }
        return ((vm.notchState == .open) && Defaults[.cornerRadiusScaling])
                 ? cornerRadiusInsets.opened.top
                 : cornerRadiusInsets.closed.top
    }

    private var bottomCornerRadius: CGFloat {
        if isFaceIDActive {
            if !visualIsFaceIDExpanded {
                return ((vm.notchState == .open) && Defaults[.cornerRadiusScaling])
                    ? cornerRadiusInsets.opened.bottom
                    : cornerRadiusInsets.closed.bottom
            }
            if isMinimalScan {
                return FaceIDOverlayGeometry.minimalNotchBottomRadius
            }
            if case .onboarding(let controller) = faceIDOverlay.content {
                return controller.panelBottomRadius
            }
            return isDynamicIsland ? FaceIDOverlayGeometry.pillOpenCornerRadius : FaceIDOverlayGeometry.openBottomRadius
        }
        return ((vm.notchState == .open) && Defaults[.cornerRadiusScaling])
            ? cornerRadiusInsets.opened.bottom
            : cornerRadiusInsets.closed.bottom
    }

    private var currentNotchShape: NotchShape {
        NotchShape(
            topCornerRadius: topCornerRadius,
            bottomCornerRadius: bottomCornerRadius
        )
    }

    private var baseChinWidth: CGFloat {
        let isDynamicIsland = notchStyle == .dynamicIsland
        // When screen is locked, authenticating Face ID, or waking from sleep, strictly stay at physical notch / closed island width without expanding for inline/media
        if isEffectivelyLocked {
            return isDynamicIsland ? compactDynamicIslandWidth : vm.closedNotchSize.width
        }

        var chinWidth: CGFloat = isDynamicIsland ? compactDynamicIslandWidth : vm.closedNotchSize.width // Always match notch width or compact island

        let isMediaPlaying = Defaults[.enableMediaFeature] && (!coordinator.expandingView.show || coordinator.expandingView.type == .music)
            && vm.notchState == .closed && musicManager.isPlaying && !musicManager.songTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && coordinator.musicLiveActivityEnabled

        var mediaWidth: CGFloat = 0
        if isMediaPlaying {
            let liveHeight: CGFloat = isDynamicIsland ? 32.0 : vm.effectiveClosedNotchHeight
            let artSize: CGFloat = max(18, liveHeight - 12)
            let isInlineMediaActive = coordinator.expandingView.show && coordinator.expandingView.type == .music && Defaults[.sneakPeekStyles] == .inline
            let spacerWidth = mediaSpacerWidth(isDynamicIsland: isDynamicIsland, isInlineActive: isInlineMediaActive)
            let sidePadding: CGFloat = (isDynamicIsland && !hasPhysicalNotch) ? 28 : 34
            mediaWidth = (artSize * 2) + spacerWidth + sidePadding + gestureProgress
        }

        if coordinator.expandingView.type == .battery && coordinator.expandingView.show
            && vm.notchState == .closed && Defaults[.showPowerStatusNotifications]
        {
            chinWidth = openNotchSize.width
        } else if coordinator.sneakPeek.show && coordinator.sneakPeek.type != .music && vm.notchState == .closed {
            if Defaults[.inlineHUD] || coordinator.sneakPeek.type == .battery {
                chinWidth = InlineHUD.totalWidth(for: coordinator.sneakPeek.type, isDynamicIsland: isDynamicIsland, hasPhysicalNotch: hasPhysicalNotch, closedNotchWidth: vm.closedNotchSize.width) + gestureProgress
            } else {
                let minDefaultHUDWidth = (isDynamicIsland && !hasPhysicalNotch) ? 260 : (vm.closedNotchSize.width + 80)
                let defaultHUDWidth = max(minDefaultHUDWidth, isDynamicIsland ? 260 : 250) + gestureProgress
                chinWidth = isMediaPlaying ? max(mediaWidth, defaultHUDWidth) : defaultHUDWidth
            }
        } else if coordinator.sneakPeek.show && coordinator.sneakPeek.type == .music && Defaults[.sneakPeekStyles] == .standard && vm.notchState == .closed {
            let minDefaultMusicWidth = (isDynamicIsland && !hasPhysicalNotch) ? 260 : (vm.closedNotchSize.width + 80)
            let defaultMusicWidth = max(minDefaultMusicWidth, isDynamicIsland ? 260 : 250) + gestureProgress
            chinWidth = isMediaPlaying ? max(mediaWidth, defaultMusicWidth) : defaultMusicWidth
        } else if isMediaPlaying {
            chinWidth = mediaWidth
        }
        return chinWidth
    }

    private func mediaSpacerWidth(isDynamicIsland: Bool, isInlineActive: Bool) -> CGFloat {
        if isDynamicIsland && !hasPhysicalNotch {
            let baseSpacer: CGFloat = 56
            let expandedSpacer: CGFloat = 160
            return isInlineActive ? expandedSpacer : baseSpacer
        } else {
            return vm.closedNotchSize.width + (isInlineActive ? 140 : 16)
        }
    }

    private var computedChinWidth: CGFloat {
        if isFaceIDActive || isFaceIDSettlingAfterClose {
            return targetFaceIDSize.width
        }
        return baseChinWidth
    }

    private var isEffectivelyHiddenInFullscreen: Bool {
        vm.hideOnClosed && !vm.isHoverRevealed && !isEffectivelyLocked
    }
    private var isDynamicIsland: Bool { notchStyle == .dynamicIsland }
    private var baseClosedHeight: CGFloat {
        if hasPhysicalNotch && !isDynamicIsland {
            return vm.effectiveClosedNotchHeight
        }
        return isDynamicIsland ? 32 : max(vm.closedNotchSize.height, 0)
    }
    private var islandRadius: CGFloat {
        if isFaceIDActive {
            if !visualIsFaceIDExpanded {
                return isDynamicIsland ? (baseClosedHeight > 0 ? baseClosedHeight / 2 : 16) : max(14, vm.effectiveClosedNotchHeight / 2)
            }
            if isMinimalScan {
                return FaceIDOverlayGeometry.minimalPillOpenHeight / 2
            }
            return FaceIDOverlayGeometry.pillOpenCornerRadius
        }
        return vm.notchState == .open ? 26 : (isDynamicIsland ? (baseClosedHeight > 0 ? baseClosedHeight / 2 : 16) : max(14, vm.effectiveClosedNotchHeight / 2))
    }
    private var isDefaultHUDActive: Bool {
        guard coordinator.sneakPeek.show && vm.notchState == .closed else { return false }
        if coordinator.sneakPeek.type == .battery { return false }
        if coordinator.sneakPeek.type == .music {
            return Defaults[.sneakPeekStyles] == .standard
        }
        return !Defaults[.inlineHUD]
    }
    private var currentNotchWidth: CGFloat {
        if isFaceIDActive {
            return targetFaceIDSize.width
        }
        if vm.notchState == .open {
            return isDynamicIsland ? notchOpenWidth : (notchOpenWidth + topCornerRadius * 2)
        }
        return computedChinWidth
    }
    private var currentNotchHeight: CGFloat {
        if isFaceIDActive {
            return targetFaceIDSize.height
        }
        if vm.notchState == .open {
            return vm.effectiveOpenHeight
        }
        if isEffectivelyLocked {
            return baseClosedHeight
        }
        return isDefaultHUDActive ? baseClosedHeight + 34 : baseClosedHeight
    }
    private var gestureScale: CGFloat {
        guard gestureProgress != 0 else { return 1.0 }
        let scaleFactor = 1.0 + gestureProgress * 0.01
        return max(0.6, scaleFactor)
    }

    @ViewBuilder
    private func applyHitShape<V: View>(_ view: V) -> some View {
        if isDynamicIsland {
            view.contentShape(RoundedRectangle(cornerRadius: islandRadius, style: .continuous))
        } else {
            view.contentShape(currentNotchShape)
        }
    }

    @ViewBuilder
    private var mainNotchContainer: some View {
        let isIsland = isDynamicIsland
        let isHiddenInFS = isEffectivelyHiddenInFullscreen && vm.notchState == .closed
        let offscreenDistance = currentNotchHeight + (isIsland ? effectiveTopOffset : 0) + 30
        let slideOffset: CGFloat = isHiddenInFS ? -offscreenDistance : 0

        NotchLayout()
            .frame(
                width: currentNotchWidth,
                height: currentNotchHeight,
                alignment: .top
            )
            .background(.black)
            .conditionalModifier(isIsland) { view in
                view
                    .clipShape(RoundedRectangle(cornerRadius: islandRadius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: islandRadius, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8)
                    }
            }
            .conditionalModifier(!isIsland) { view in
                view
                    .clipShape(currentNotchShape)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(.black)
                            .frame(height: 1)
                            .padding(.horizontal, topCornerRadius)
                    }
                    .overlay {
                        currentNotchShape
                            .stroke(Color.white.opacity((isDynamicIsland && vm.notchState == .open) ? 0.10 : 0), lineWidth: 0.8)
                    }
            }
            .compositingGroup()
            .padding(.top, isIsland ? effectiveTopOffset : 0)
            .contentShape(Rectangle())
            .offset(y: slideOffset)
            .opacity(isHiddenInFS ? 0 : 1)
    }

    var body: some View {
        ZStack(alignment: .top) {
            topEdgeHoverSensor
            dragDetector
            VStack(spacing: 0) {
                mainNotchContainer
                    .background {
                        if !isEffectivelyLocked {
                            NotchHoverTrackingBridge(
                                onHoverChanged: { hovering in
                                    // While fullscreen hiding is active, the visible
                                    // notch is off-screen but this background bridge
                                    // still occupies its original layout height. Do
                                    // not let that invisible area reveal the notch;
                                    // only the dedicated 2pt top-edge sensor may do so.
                                    if isEffectivelyHiddenInFullscreen {
                                        isMainNotchHovered = false
                                        return
                                    }
                                    isMainNotchHovered = hovering
                                    handleHover(hovering || isTopEdgeHovered)
                                }
                            )
                        }
                    }
                    .animation(animationSpring, value: vm.notchState)
                    .animation(animationSpring, value: currentNotchWidth)
                    .animation(animationSpring, value: currentNotchHeight)
                    .animation(animationSpring, value: vm.isHoverRevealed)
                    .animation(animationSpring, value: isEffectivelyHiddenInFullscreen)
                    .animation(faceIDAnimation, value: isFaceIDActive)
                    .animation(faceIDAnimation, value: targetFaceIDSize)
                    .animation(.smooth, value: gestureProgress)
                    .onHover { hovering in
                        if shouldHandleFaceIDHover(hovering: hovering) {
                            FaceIDOverlayController.shared.setHovering(hovering)
                            if hovering && faceIDOverlay.phase != .onboarding {
                                FaceIDOverlayController.shared.activate()
                            }
                        }
                    }
                    .conditionalModifier(!isFaceIDContentActive) { view in
                        applyHitShape(view)
                            .onTapGesture {
                                if shouldHandleFaceIDTap() {
                                    FaceIDOverlayController.shared.activate()
                                    return
                                }
                                if MissionControlObserver.shared.checkIsMissionControlActive() {
                                    return
                                }
                                if vm.notchState == .closed {
                                    doOpen()
                                }
                            }
                    }
                    .onAppear {
                        visualIsFaceIDExpanded = targetIsFaceIDExpanded
                    }
                    .onChange(of: faceIDOverlay.phase) { oldPhase, newPhase in
                        updateFaceIDExpansion()
                        updateScanPulse()
                        if newPhase == .collapsing {
                            isFaceIDSettlingAfterClose = true
                        } else if newPhase == .closed && (oldPhase == .collapsing || oldPhase == .success || oldPhase == .failure) {
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(350))
                                withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                                    isFaceIDSettlingAfterClose = false
                                }
                            }
                        } else if newPhase != .closed && newPhase != .collapsing {
                            isFaceIDSettlingAfterClose = false
                        }
                        if newPhase == .onboarding {
                            DispatchQueue.main.async {
                                NSApp.activate(ignoringOtherApps: true)
                                (AppDelegate.shared?.window as? NotchPulseSkyLightWindow)?.makeKeyAndOrderFront(nil)
                            }
                        }
                    }
                    .onChange(of: isFaceIDActive) { _, _ in
                        updateFaceIDExpansion()
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .sharingDidFinish)) { _ in
                        if vm.notchState == .open && !isHovering && canCloseOnHoverExit {
                            self.doClose()
                        }
                    }
                    .onChange(of: vm.notchState) { _, newState in
                        if newState == .open {
                            MissionControlObserver.shared.startMonitoring {
                                Task { @MainActor in
                                    if self.vm.notchState == .open && self.canCloseOnHoverExit {
                                        self.doClose()
                                    }
                                }
                            }
                        } else if newState == .closed {
                            MissionControlObserver.shared.stopMonitoring()
                            hoverOpenTask?.cancel()
                            hoverOpenTask = nil
                            hoverCloseTask?.cancel()
                            hoverCloseTask = nil
                            self.isHovering = false
                            if vm.hideOnClosed {
                                Task { @MainActor in
                                    try? await Task.sleep(for: .milliseconds(350))
                                    if !self.isHovering && self.vm.notchState == .closed {
                                        withAnimation(animationSpring) {
                                            self.vm.isHoverRevealed = false
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .previewNotchWidth)) { notification in
                        let targetWidth = (notification.object as? CGFloat) ?? Defaults[.notchOpenWidth]
                        SharingStateManager.shared.preventNotchClose = true
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            if vm.notchState != .open {
                                vm.open()
                            }
                            vm.notchSize = CGSize(width: targetWidth, height: openNotchSize.height)
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .closeNotchPreview)) { _ in
                        SharingStateManager.shared.preventNotchClose = false
                        withAnimation(.spring(response: 0.45, dampingFraction: 1.0)) {
                            vm.close(force: true)
                        }
                    }
                    .onChange(of: notchOpenWidth) { _, newWidth in
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            if vm.notchState == .open {
                                vm.notchSize = CGSize(width: max(minNotchWidth, min(maxNotchWidth, newWidth)), height: openNotchSize.height)
                            }
                        }
                    }
                    .onChange(of: vm.isBatteryPopoverActive) {
                        if !vm.isBatteryPopoverActive && !isHovering && vm.notchState == .open && canCloseOnHoverExit {
                            self.doClose()
                        }
                    }
                    .sensoryFeedback(.alignment, trigger: haptics)
                    .contextMenu {
                        Button(loc("Settings")) {
                            DispatchQueue.main.async {
                                SettingsWindowController.shared.showWindow()
                            }
                        }
                        .keyboardShortcut(KeyEquivalent(","), modifiers: .command)
                        
                        Divider()
                        
                        Menu("\(loc("Notch Width")) (\(Int(notchOpenWidth))px)") {
                            Button(loc("Compact (580px)")) { notchOpenWidth = 580 }
                            Button(loc("Standard (740px)")) { notchOpenWidth = 740 }
                            Button(loc("Wide (860px)")) { notchOpenWidth = 860 }
                            Button(loc("Extra Wide (940px)")) { notchOpenWidth = 940 }
                        }
                    }
                if vm.chinHeight > 0 {
                    Rectangle()
                        .fill(Color.black.opacity(0.01))
                        .frame(width: computedChinWidth, height: vm.chinHeight)
                        .allowsHitTesting(false)
                }
            }
        }
        .padding(.bottom, 8)
        .frame(maxWidth: windowSize.width, maxHeight: windowSize.height, alignment: .top)
        .compositingGroup()
        .background {
            ScreenEdgeHoverTrackingBridge(
                regionProvider: { topEdgeTrackingRegion },
                isEnabled: { topEdgeTrackingEnabled },
                onHoverChanged: { hovering in
                    isTopEdgeHovered = hovering
                    handleHover(hovering || isMainNotchHovered)
                }
            )
        }
        .scaleEffect(
            x: gestureScale,
            y: gestureScale,
            anchor: .top
        )
        .animation(.smooth, value: gestureProgress)
        .preferredColorScheme(.dark)
        .environmentObject(vm)
        .onChange(of: coordinator.currentView) { _, newView in
            guard !SharingStateManager.shared.preventNotchClose else { return }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                switch newView {
                case .audio:
                    AudioDeviceManager.shared.refreshDevices()
                    vm.customOpenHeight = AudioHubNotchView.calculateHeight(selectedTab: AudioDeviceManager.shared.selectedTab)
                case .display:
                    BrightnessManager.shared.refreshAllDisplays()
                    vm.customOpenHeight = DisplayHubNotchView.calculateHeight()
                case .clipboard:
                    vm.customOpenHeight = ClipboardNotchView.preferredHeight
                case .home, .shelf, .stats:
                    if !CalendarStateViewModel.shared.isFullMonthExpanded {
                        vm.customOpenHeight = nil
                    }
                }
            }
        }
        .onChange(of: vm.anyDropZoneTargeting) { _, isTargeted in
            anyDropDebounceTask?.cancel()

            if isTargeted {
                if vm.notchState == .closed {
                    doOpen(targetView: .shelf)
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        coordinator.currentView = .shelf
                    }
                }
                return
            }

            anyDropDebounceTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(1200))
                guard !Task.isCancelled else { return }

                if vm.dropEvent {
                    vm.dropEvent = false
                    return
                }

                vm.dropEvent = false
                if !SharingStateManager.shared.preventNotchClose && !ShelfStateViewModel.shared.isPinned && !CalendarStateViewModel.shared.isPinned {
                    self.doClose()
                }
            }
        }
        .onAppear {
            updateScanPulse()
        }
        .onDisappear {
            stopScanPulse()
        }
    }

    private func updateScanPulse() {
        if faceIDOverlay.phase == .scanning {
            startScanPulse()
        } else {
            stopScanPulse()
        }
    }

    private func startScanPulse() {
        guard scanPulseTask == nil else { return }
        let entryDelay = (isDynamicIsland ? FaceIDOverlayGeometry.pillEnterExpansionDelay : 0) + FaceIDOverlayGeometry.scanPulseStartDelay
        let half = FaceIDOverlayGeometry.scanPulseHalfCycleDuration
        let hold = FaceIDOverlayGeometry.scanPulseHoldDuration
        scanPulseTask = Task {
            try? await Task.sleep(for: .seconds(entryDelay))
            while !Task.isCancelled {
                withAnimation(.easeInOut(duration: half)) { self.isScanPulseDimmed = true }
                try? await Task.sleep(for: .seconds(half + hold))
                guard !Task.isCancelled else { break }

                withAnimation(.easeInOut(duration: half)) { self.isScanPulseDimmed = false }
                try? await Task.sleep(for: .seconds(half + hold))
            }
        }
    }

    private func stopScanPulse() {
        scanPulseTask?.cancel()
        scanPulseTask = nil
        guard isScanPulseDimmed else { return }
        withAnimation(.easeOut(duration: FaceIDOverlayGeometry.scanPulseSettleDuration)) {
            isScanPulseDimmed = false
        }
    }

    @ViewBuilder
    func NotchLayout() -> some View {
        VStack(alignment: .leading) {
            VStack(alignment: .leading) {
                if coordinator.helloAnimationRunning {
                    Spacer()
                    HelloAnimation(onFinish: {
                        vm.closeHello()
                    }).frame(
                        width: getClosedNotchSize().width,
                        height: 80
                    )
                    .padding(.top, 40)
                    Spacer()
                } else if isEffectivelyLocked && !isFaceIDContentActive {
                    Rectangle().fill(.clear).frame(
                        width: (notchStyle == .dynamicIsland) ? compactDynamicIslandWidth : vm.closedNotchSize.width,
                        height: (notchStyle == .dynamicIsland) ? 32 : vm.effectiveClosedNotchHeight
                    )
                } else {
                    ZStack {
                        Group {
                            if !isEffectivelyLocked && coordinator.sneakPeek.show && (Defaults[.inlineHUD] || coordinator.sneakPeek.type == .battery) && (coordinator.sneakPeek.type != .music) && vm.notchState == .closed {
                                InlineHUD(type: $coordinator.sneakPeek.type, value: $coordinator.sneakPeek.value, icon: $coordinator.sneakPeek.icon, hoverAnimation: $isHovering, gestureProgress: $gestureProgress)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .transition(.opacity)
                            } else if !isEffectivelyLocked && Defaults[.enableMediaFeature] && (!coordinator.expandingView.show || coordinator.expandingView.type == .music) && vm.notchState == .closed && musicManager.isPlaying && !musicManager.songTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && coordinator.musicLiveActivityEnabled {
                                MusicLiveActivity()
                                    .frame(maxWidth: (isDynamicIsland && !hasPhysicalNotch && isDefaultHUDActive) ? .infinity : nil, alignment: .center)
                                    .transition(.opacity)
                            } else if !isEffectivelyLocked && vm.notchState == .open {
                                NotchPulseHeader()
                                    .frame(height: max(32, vm.closedNotchSize.height))
                                    .opacity(gestureProgress != 0 ? 1.0 - min(abs(gestureProgress) * 0.1, 0.3) : 1.0)
                                    .transition(.opacity)
                            } else {
                                Rectangle().fill(.clear).frame(
                                    width: (notchStyle == .dynamicIsland) ? compactDynamicIslandWidth : vm.closedNotchSize.width,
                                    height: (notchStyle == .dynamicIsland) ? 32 : vm.effectiveClosedNotchHeight
                                )
                                .transition(.opacity)
                            }
                        }
                        .opacity((isFaceIDActive || isFaceIDSettlingAfterClose) ? 0 : 1)
                        .animation(.easeInOut(duration: 0.35), value: (isFaceIDActive || isFaceIDSettlingAfterClose))

                        // ARCHITECTURAL RULE: FaceIDContentView must ALWAYS remain on the top-most layer
                        // with zIndex(999) inside NotchLayout ZStack so HUDs and header elements do not draw over it.
                        if isFaceIDContentActive {
                            FaceIDContentView()
                                .zIndex(999)
                                .opacity(isFaceIDContentVisible ? 1 : 0)
                                .scaleEffect(isFaceIDContentVisible ? 1.0 : 0.8, anchor: .top)
                                .animation(.easeInOut(duration: 0.24), value: isFaceIDContentVisible)
                                .transition(.opacity)
                        }
                    }

                    if !isEffectivelyLocked && coordinator.sneakPeek.show && !isFaceIDActive && !isFaceIDSettlingAfterClose {
                        if (coordinator.sneakPeek.type != .music) && (coordinator.sneakPeek.type != .battery) && !Defaults[.inlineHUD] && vm.notchState == .closed {
                            SystemEventIndicatorModifier(
                                eventType: $coordinator.sneakPeek.type,
                                value: $coordinator.sneakPeek.value,
                                icon: $coordinator.sneakPeek.icon,
                                sendEventBack: { newVal in
                                    switch coordinator.sneakPeek.type {
                                    case .volume:
                                        VolumeManager.shared.setAbsolute(Float32(newVal))
                                    case .brightness:
                                        BrightnessManager.shared.setAbsolute(value: Float32(newVal))
                                    default:
                                        break
                                    }
                                }
                            )
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.bottom, 10)
                            .padding(.horizontal, (isDynamicIsland && !hasPhysicalNotch) ? 14 : 18)
                        }
                        // Old sneak peek music
                        else if coordinator.sneakPeek.type == .music {
                            if vm.notchState == .closed && Defaults[.sneakPeekStyles] == .standard {
                                HStack(alignment: .center, spacing: 8) {
                                    Image(systemName: "music.note")
                                        .frame(width: 16)
                                    let musicText = musicManager.artistName.isEmpty ? musicManager.songTitle : "\(musicManager.songTitle) - \(musicManager.artistName)"
                                    Text(musicText)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(Defaults[.playerColorTinting] ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6) : .gray)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                }
                                .frame(maxWidth: .infinity, alignment: .center)
                                .foregroundStyle(.gray)
                                .padding(.bottom, 10)
                                .padding(.horizontal, (isDynamicIsland && !hasPhysicalNotch) ? 14 : 18)
                            }
                        }
                    }
                }
            }
            .zIndex(2)
            if !isEffectivelyLocked && vm.notchState == .open && !isFaceIDActive {
                VStack {
                    switch coordinator.currentView {
                    case .home:
                        NotchHomeView(albumArtNamespace: albumArtNamespace)
                            .id(NotchViews.home)
                    case .shelf:
                        ShelfView()
                            .id(NotchViews.shelf)
                    case .stats:
                        StatsView()
                            .id(NotchViews.stats)
                    case .clipboard:
                        ClipboardNotchView()
                            .environmentObject(vm)
                            .id(NotchViews.clipboard)
                    case .audio:
                        AudioHubNotchView()
                            .environmentObject(vm)
                            .id(NotchViews.audio)
                    case .display:
                        DisplayHubNotchView()
                            .environmentObject(vm)
                            .id(NotchViews.display)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
                .compositingGroup()
                .padding(.horizontal, isDynamicIsland ? 0 : topCornerRadius)
                .transition(
                    .scale(scale: 0.96, anchor: .top)
                    .combined(with: .opacity)
                    .animation(.smooth(duration: 0.32))
                )
                .zIndex(1)
                .allowsHitTesting(vm.notchState == .open)
                .opacity(gestureProgress != 0 ? 1.0 - min(abs(gestureProgress) * 0.1, 0.3) : 1.0)
            }
        }
    }

    @ViewBuilder
    private func FaceIDContentView() -> some View {
        let controller = faceIDOverlay
        Group {
            if case .onboarding(let enrollmentController) = controller.content {
                FaceIDOnboardingNotchView(controller: enrollmentController)
            } else if isMinimalScan {
                FaceIDMinimalUnlockView(
                    media: controller.media,
                    isUnlocked: controller.phase == .success,
                    edgeInset: isDynamicIsland ? 14 : (FaceIDOverlayGeometry.minimalContentEdgeInset + topCornerRadius),
                    lockIconSize: isDynamicIsland ? FaceIDOverlayGeometry.minimalLockIconSize : FaceIDOverlayGeometry.minimalNotchLockIconSize,
                    mediaWidth: isDynamicIsland ? FaceIDOverlayGeometry.minimalMediaWidth : FaceIDOverlayGeometry.minimalNotchMediaWidth,
                    mediaVerticalInset: isDynamicIsland ? FaceIDOverlayGeometry.minimalMediaVerticalInset : FaceIDOverlayGeometry.minimalNotchMediaVerticalInset,
                    pulseScale: isScanPulseDimmed ? FaceIDOverlayGeometry.scanPulseScale : 1.0,
                    pulseOpacity: isScanPulseDimmed ? FaceIDOverlayGeometry.scanPulseOpacity : 1.0
                )
            } else {
                let topPadding: CGFloat = (hasPhysicalNotch && !isDynamicIsland)
                    ? vm.effectiveClosedNotchHeight + 6
                    : (isDynamicIsland ? FaceIDOverlayGeometry.pillContentPaddingTop : FaceIDOverlayGeometry.notchContentPaddingTop)
                FaceIDScanAnimationView(media: controller.media)
                    .padding(.leading, isDynamicIsland ? FaceIDOverlayGeometry.pillContentPaddingLeading : FaceIDOverlayGeometry.notchContentPaddingLeading)
                    .padding(.trailing, isDynamicIsland ? FaceIDOverlayGeometry.pillContentPaddingTrailing : FaceIDOverlayGeometry.notchContentPaddingTrailing)
                    .padding(.top, topPadding)
                    .padding(.bottom, isDynamicIsland ? FaceIDOverlayGeometry.pillContentPaddingBottom : FaceIDOverlayGeometry.notchContentPaddingBottom)
                    .scaleEffect(0.92)
                    .scaleEffect(isScanPulseDimmed ? FaceIDOverlayGeometry.scanPulseScale : 1.0)
                    .opacity(isScanPulseDimmed ? FaceIDOverlayGeometry.scanPulseOpacity : 1.0)
            }
        }
        .frame(width: targetFaceIDSize.width, height: targetFaceIDSize.height, alignment: isMinimalScan ? .center : .top)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture {
            FaceIDOverlayController.shared.activate()
        }
    }

    @ViewBuilder
    func MusicLiveActivity() -> some View {
        let isDynamicIsland = notchStyle == .dynamicIsland
        let liveHeight: CGFloat = isDynamicIsland ? 32.0 : vm.effectiveClosedNotchHeight
        let artSize: CGFloat = max(18, liveHeight - 12)

        let isInlineExpanded = coordinator.expandingView.show
            && coordinator.expandingView.type == .music
            && Defaults[.sneakPeekStyles] == .inline

        let spacerWidth = mediaSpacerWidth(isDynamicIsland: isDynamicIsland, isInlineActive: isInlineExpanded)

        HStack(spacing: 0) {
            Image(nsImage: musicManager.albumArt)
                .resizable()
                .scaledToFill()
                .frame(
                    width: artSize,
                    height: artSize
                )
                .clipped()
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: MusicPlayerImageSizes.cornerRadiusInset.closed,
                        style: .continuous
                    )
                )

            if isDynamicIsland && !hasPhysicalNotch && isDefaultHUDActive {
                Spacer()
            } else {
                Rectangle()
                    .fill(.black)
                    .overlay(
                        HStack(alignment: .center, spacing: 0) {
                            if isInlineExpanded {
                                Text(musicManager.songTitle)
                                    .font(.system(size: 11, weight: .medium))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .foregroundStyle(
                                        Defaults[.coloredSpectrogram]
                                            ? Color(nsColor: musicManager.avgColor) : Color.white
                                    )
                                    .frame(maxWidth: (isDynamicIsland && !hasPhysicalNotch) ? 70 : 55, alignment: .leading)
                                    .opacity(isInlineExpanded ? 1 : 0)

                                Spacer(minLength: hasPhysicalNotch ? (vm.closedNotchSize.width + 24) : 16)

                                // Song Artist
                                Text(musicManager.artistName)
                                    .font(.system(size: 11, weight: .medium))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .foregroundStyle(
                                        Defaults[.coloredSpectrogram]
                                            ? Color(nsColor: musicManager.avgColor).opacity(0.85)
                                            : Color.white.opacity(0.7)
                                    )
                                    .frame(maxWidth: (isDynamicIsland && !hasPhysicalNotch) ? 70 : 55, alignment: .trailing)
                                    .opacity(isInlineExpanded ? 1 : 0)
                            }
                        }
                        .padding(.horizontal, 4)
                    )
                    .frame(width: spacerWidth)
            }

            HStack {
                if useMusicVisualizer {
                    Rectangle()
                        .fill(
                            Defaults[.coloredSpectrogram]
                                ? Color(nsColor: musicManager.avgColor).gradient
                                : Color.gray.gradient
                        )
                        .frame(width: 50, alignment: .center)
                        .mask {
                            AudioSpectrumView(isPlaying: $musicManager.isPlaying)
                                .frame(width: 16, height: 12)
                        }
                } else {
                    LottieAnimationContainer()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(
                width: max(
                    0,
                    artSize + (isDynamicIsland ? 0 : gestureProgress / 2)
                ),
                height: artSize,
                alignment: .center
            )
        }
        .padding(.leading, (isDynamicIsland && !hasPhysicalNotch) ? 14 : 10)
        .padding(.trailing, (isDynamicIsland && !hasPhysicalNotch) ? 14 : 10)
        .frame(
            maxWidth: (isDynamicIsland && !hasPhysicalNotch && isDefaultHUDActive) ? .infinity : nil,
            alignment: .center
        )
        .frame(
            height: liveHeight,
            alignment: .center
        )
    }

    private var canCloseOnHoverExit: Bool {
        !vm.isBatteryPopoverActive &&
        !ShelfStateViewModel.shared.isPinned &&
        !CalendarStateViewModel.shared.isPinned &&
        !FeatureTourController.shared.isTourActive &&
        !vm.anyDropZoneTargeting &&
        !vm.dragDetectorTargeting &&
        !vm.dropEvent
    }

    private var topEdgeTrackingEnabled: Bool {
        !isEffectivelyLocked && !(SettingsWindowController.shared.window?.isVisible == true)
    }

    private var topEdgeSensorSize: CGSize {
        let isFullscreenEdgeReveal = isEffectivelyHiddenInFullscreen && vm.notchState == .closed
        let extraPad: CGFloat = (!isFullscreenEdgeReveal && extendHoverArea) ? CGFloat(hoverAreaPadding) : 0
        let width = (isDynamicIsland ? compactDynamicIslandWidth : computedChinWidth) + (extraPad * 2)
        let height: CGFloat = isFullscreenEdgeReveal
            ? 2
            : (isDynamicIsland ? (effectiveTopOffset + 32) : baseClosedHeight) + extraPad
        return CGSize(width: width, height: height)
    }

    /// Global AppKit coordinates use a bottom-left origin, so the top edge is
    /// `screen.frame.maxY`. The extra point above maxY keeps the exact boundary
    /// inside the region when WindowServer reports a clamped edge coordinate.
    private var topEdgeTrackingRegion: CGRect {
        guard topEdgeTrackingEnabled, let screen = currentScreen else { return .null }
        let size = topEdgeSensorSize
        return CGRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height + 1
        )
    }

    @ViewBuilder
    private var topEdgeHoverSensor: some View {
        if topEdgeTrackingEnabled {
            let sensorSize = topEdgeSensorSize
            Color.clear
                .contentShape(Rectangle())
                .frame(width: sensorSize.width, height: sensorSize.height, alignment: .top)
                .onTapGesture {
                    if shouldHandleFaceIDTap() {
                        FaceIDOverlayController.shared.activate()
                        return
                    }
                    if MissionControlObserver.shared.checkIsMissionControlActive() {
                        return
                    }
                    if vm.notchState == .closed {
                        doOpen()
                    }
                }
        }
    }

    @ViewBuilder
    var dragDetector: some View {
        EmptyView()
    }

    private func doOpen(targetView: NotchViews? = nil) {
        guard !MissionControlObserver.shared.checkIsMissionControlActive() else { return }
        coordinator.dismissExpandingView(animated: false)
        coordinator.sneakPeek.show = false
        hoverOpenTask?.cancel()
        hoverOpenTask = nil
        hoverCloseTask?.cancel()
        hoverCloseTask = nil
        withAnimation(animationSpring) {
            vm.open(targetView: targetView)
        }
    }

    private func doClose() {
        coordinator.dismissExpandingView(animated: false)
        coordinator.sneakPeek.show = false
        hoverOpenTask?.cancel()
        hoverOpenTask = nil
        hoverCloseTask?.cancel()
        hoverCloseTask = nil
        withAnimation(animationSpring) {
            self.isHovering = false
            vm.close()
        }
    }

    // MARK: - Hover Management

    private func shouldHandleFaceIDHover(hovering: Bool) -> Bool {
        if isEffectivelyLocked { return true }
        if isFaceIDActive && (faceIDOverlay.phase == .scanning || faceIDOverlay.phase == .failure) { return true }
        return false
    }

    private func shouldHandleFaceIDTap() -> Bool {
        if isEffectivelyLocked { return true }
        if isFaceIDActive && (faceIDOverlay.phase == .failure || faceIDOverlay.phase == .scanning) { return true }
        return false
    }

    private func handleHover(_ hovering: Bool) {
        if coordinator.firstLaunch && !FeatureTourController.shared.isTourActive { return }
        if faceIDOverlay.phase != .closed || isFaceIDSettlingAfterClose { return }
        fullscreenHoverDebounceTask?.cancel()

        if hovering {
            // Cancel any pending close grace period immediately when mouse re-enters!
            hoverCloseTask?.cancel()
            hoverCloseTask = nil

            // Block hover expansion when Settings window is open!
            if SettingsWindowController.shared.window?.isVisible == true {
                hoverOpenTask?.cancel()
                hoverOpenTask = nil
                if vm.notchState == .open && canCloseOnHoverExit {
                    self.doClose()
                }
                return
            }

            // Block hover expansion when Mission Control is active!
            if MissionControlObserver.shared.checkIsMissionControlActive() {
                hoverOpenTask?.cancel()
                hoverOpenTask = nil
                if vm.notchState == .open && canCloseOnHoverExit {
                    self.doClose()
                }
                return
            }

            if isEffectivelyLocked {
                FaceIDOverlayController.shared.activate()
                return
            }

            if !isHovering {
                withAnimation(animationSpring) {
                    isHovering = true
                    if vm.hideOnClosed {
                        vm.isHoverRevealed = true
                    }
                }
                if vm.notchState == .closed && Defaults[.enableHaptics] {
                    haptics.toggle()
                }
            } else if vm.hideOnClosed && !vm.isHoverRevealed {
                withAnimation(animationSpring) {
                    vm.isHoverRevealed = true
                }
            }

            guard vm.notchState == .closed,
                  !coordinator.sneakPeek.show,
                  Defaults[.openNotchOnHover] else { return }

            // If an open task is already counting down, let it proceed without reset!
            if hoverOpenTask != nil { return }

            let delay = max(0.0, Defaults[.minimumHoverDuration])
            if delay <= 0.02 {
                self.doOpen()
                return
            }

            hoverOpenTask = Task { @MainActor in
                defer { self.hoverOpenTask = nil }
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled,
                      !self.isEffectivelyLocked,
                      self.vm.notchState == .closed,
                      self.isHovering,
                      !(SettingsWindowController.shared.window?.isVisible == true),
                      !MissionControlObserver.shared.checkIsMissionControlActive(),
                      !self.coordinator.sneakPeek.show else { return }
                self.doOpen()
            }
        } else {
            // Keep the grace period longer than the sensor-to-open-notch handoff.
            // The spring needs ~380ms and SwiftUI can briefly emit an exit while
            // replacing the compact hit region with the expanded one.
            hoverCloseTask?.cancel()
            let gracePeriodMs = 280

            hoverCloseTask = Task { @MainActor in
                defer { self.hoverCloseTask = nil }
                try? await Task.sleep(for: .milliseconds(gracePeriodMs))
                guard !Task.isCancelled else { return }

                self.hoverOpenTask?.cancel()
                self.hoverOpenTask = nil

                if self.isMainNotchHovered || self.isTopEdgeHovered {
                    return
                }

                if self.vm.notchState == .open && self.canCloseOnHoverExit {
                    // A drag hold may become stale after the pointer leaves, but an
                    // actual system share/AirDrop session must retain the notch.
                    if !SharingStateManager.shared.isInteractionActive {
                        SharingStateManager.shared.preventNotchClose = false
                        self.doClose()
                    } else {
                        withAnimation(animationSpring) { self.isHovering = false }
                    }
                } else {
                    withAnimation(animationSpring) { self.isHovering = false }
                }
                if self.vm.hideOnClosed && self.vm.notchState == .closed {
                    withAnimation(animationSpring) {
                        self.vm.isHoverRevealed = false
                    }
                }
            }
        }
    }


}

/// Tracks the screen-edge activation zone from global mouse coordinates instead
/// of relying on a 1–2pt SwiftUI hit area at the window boundary. This remains
/// stable in fullscreen Spaces and when the closed notch is translated offscreen.
private struct ScreenEdgeHoverTrackingBridge: NSViewRepresentable {
    let regionProvider: @MainActor () -> CGRect
    let isEnabled: @MainActor () -> Bool
    let onHoverChanged: @MainActor (Bool) -> Void

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.regionProvider = regionProvider
        view.isEnabled = isEnabled
        view.onHoverChanged = onHoverChanged
        return view
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        nsView.regionProvider = regionProvider
        nsView.isEnabled = isEnabled
        nsView.onHoverChanged = onHoverChanged
        nsView.installMonitorsIfNeeded()
        nsView.scheduleEvaluation()
    }

    static func dismantleNSView(_ nsView: TrackingView, coordinator: ()) {
        nsView.stopMonitoring()
    }

    @MainActor
    final class TrackingView: NSView {
        var regionProvider: (() -> CGRect)?
        var isEnabled: (() -> Bool)?
        var onHoverChanged: ((Bool) -> Void)?

        private var globalMonitor: Any?
        private var localMonitor: Any?
        private var lastInside = false
        private var evaluationScheduled = false

        private static let eventMask: NSEvent.EventTypeMask = [
            .mouseMoved,
            .leftMouseDragged,
            .rightMouseDragged,
            .otherMouseDragged
        ]

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil {
                stopMonitoring()
            } else {
                window?.acceptsMouseMovedEvents = true
                installMonitorsIfNeeded()
                scheduleEvaluation()
            }
        }

        func installMonitorsIfNeeded() {
            guard window != nil else { return }

            if globalMonitor == nil {
                globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: Self.eventMask) { [weak self] _ in
                    DispatchQueue.main.async { self?.evaluateHover() }
                }
            }

            if localMonitor == nil {
                localMonitor = NSEvent.addLocalMonitorForEvents(matching: Self.eventMask) { [weak self] event in
                    self?.scheduleEvaluation()
                    return event
                }
            }
        }

        func stopMonitoring() {
            if let globalMonitor {
                NSEvent.removeMonitor(globalMonitor)
                self.globalMonitor = nil
            }
            if let localMonitor {
                NSEvent.removeMonitor(localMonitor)
                self.localMonitor = nil
            }
            if lastInside {
                lastInside = false
                onHoverChanged?(false)
            }
        }

        func scheduleEvaluation() {
            guard !evaluationScheduled else { return }
            evaluationScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.evaluationScheduled = false
                self.evaluateHover()
            }
        }

        private func evaluateHover() {
            let enabled = isEnabled?() == true
            let region = regionProvider?() ?? .null
            let inside = enabled && !region.isNull && region.contains(NSEvent.mouseLocation)

            // Re-emit true on movement so hover recovers immediately after a
            // transient blocker such as Mission Control disappears.
            if inside || inside != lastInside {
                lastInside = inside
                onHoverChanged?(inside)
            }
        }

        deinit {
            if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
            if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        }
    }
}

/// A stable AppKit tracking area for the visible notch. SwiftUI's `.onHover`
/// can emit a false exit when the notch changes size because its hit-test region
/// is rebuilt. This bridge keeps one tracking owner alive across that resize.
private struct NotchHoverTrackingBridge: NSViewRepresentable {
    let onHoverChanged: @MainActor (Bool) -> Void

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onHoverChanged = onHoverChanged
        return view
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        nsView.onHoverChanged = onHoverChanged
        nsView.scheduleEvaluation()
    }

    @MainActor
    final class TrackingView: NSView {
        var onHoverChanged: ((Bool) -> Void)?
        private var trackingAreaRef: NSTrackingArea?
        private var lastInside = false
        private var evaluationScheduled = false

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.acceptsMouseMovedEvents = true
            updateTrackingAreas()
            scheduleEvaluation()
        }

        override func updateTrackingAreas() {
            if let trackingAreaRef {
                removeTrackingArea(trackingAreaRef)
            }
            let area = NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
            trackingAreaRef = area
            super.updateTrackingAreas()
        }

        override func mouseEntered(with event: NSEvent) {
            evaluateHover()
        }

        override func mouseMoved(with event: NSEvent) {
            evaluateHover()
        }

        override func mouseDragged(with event: NSEvent) {
            evaluateHover()
        }

        override func mouseExited(with event: NSEvent) {
            evaluateHover()
        }

        func scheduleEvaluation() {
            guard !evaluationScheduled else { return }
            evaluationScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.evaluationScheduled = false
                self.evaluateHover()
            }
        }

        private func evaluateHover() {
            guard let window else { return }
            let pointInView = convert(window.mouseLocationOutsideOfEventStream, from: nil)
            let inside = !isHidden && bounds.contains(pointInView)
            // Re-emit `true` while moving inside so hover can recover immediately
            // after Settings or Mission Control stops blocking expansion.
            if inside || inside != lastInside {
                lastInside = inside
                onHoverChanged?(inside)
            }
        }
    }
}

struct FullScreenDropDelegate: DropDelegate {
    @Binding var isTargeted: Bool
    let onDrop: () -> Void

    func dropEntered(info _: DropInfo) {
        isTargeted = true
    }

    func dropExited(info _: DropInfo) {
        isTargeted = false
    }

    func performDrop(info _: DropInfo) -> Bool {
        isTargeted = false
        onDrop()
        return true
    }
}
