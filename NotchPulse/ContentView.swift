//
//  ContentView.swift
//  NotchPulseApp
//
//  Created by Harsh Vardhan Goswami on 02/08/24.
//  Modified by Richard Kunkli on 24/08/2024.
//
//  ⚠️ [UI Policy Rule]: Notch and Dynamic Island styles MUST always render identical internal views,
//  contents, layout metrics, tabs, and components unless specifically requested otherwise by the user.
//

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
    @State private var hoverTask: Task<Void, Never>?
    @State private var isHovering: Bool = false
    @State private var anyDropDebounceTask: Task<Void, Never>?

    @State private var gestureProgress: CGFloat = .zero

    @State private var haptics: Bool = false

    @Namespace var albumArtNamespace

    @Default(.useMusicVisualizer) var useMusicVisualizer
    @Default(.appLanguage) var appLanguage

    @Default(.showNotHumanFace) var showNotHumanFace
    @Default(.notchStyle) var notchStyle
    @Default(.dynamicIslandTopOffset) var dynamicIslandTopOffset
    @Default(.notchOpenWidth) var notchOpenWidth
    @Default(.expandedDragDetection) var expandedDragDetection: Bool
    @Default(.dragDetectionPadding) var dragDetectionPadding: Double

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

    private let extendedHoverPadding: CGFloat = 30
    private let zeroHeightHoverPadding: CGFloat = 10

    private var faceIDOverlay: FaceIDOverlayController {
        FaceIDOverlayController.shared
    }
    @State private var isFaceIDSettlingAfterClose: Bool = false

    private var isFaceIDActive: Bool {
        let isSessionActive = faceIDOverlay.isSessionActive || (faceIDOverlay.isArmed && NotchPulseLockMonitor.isScreenActuallyLocked())
        if isSessionActive || faceIDOverlay.phase != .closed || visualIsFaceIDExpanded {
            let cameraDevice = NotchPulseCameraDeviceCatalog.resolvedDevice()
            if let targetScreen = NotchPulseCameraDeviceCatalog.targetScreen(for: cameraDevice),
               let targetUUID = targetScreen.displayUUID {
                let thisScreenUUID = vm.screenUUID ?? currentScreen?.displayUUID
                if thisScreenUUID == targetUUID {
                    return true
                }
                if !Defaults[.showOnAllDisplays] && AppDelegate.shared?.faceIDCameraWindow == nil {
                    return true
                }
                return false
            }
            if let builtInScreen = NSScreen.screens.first(where: { $0.isBuiltIn || $0.safeAreaInsets.top > 0 }),
               let targetUUID = builtInScreen.displayUUID {
                let thisScreenUUID = vm.screenUUID ?? currentScreen?.displayUUID
                if thisScreenUUID == targetUUID {
                    return true
                }
                if !Defaults[.showOnAllDisplays] && AppDelegate.shared?.faceIDCameraWindow == nil {
                    return true
                }
                return false
            }
            return true
        }
        return false
    }

    private var isFaceIDContentActive: Bool {
        isFaceIDActive
    }

    private var isFaceIDContentVisible: Bool {
        visualIsFaceIDExpanded
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
        let screen = currentScreen
        return (screen?.safeAreaInsets.top ?? 0) > 0 || screen?.auxiliaryTopLeftArea != nil
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
            return CGSize(
                width: vm.closedNotchSize.width,
                height: 180
            )
        } else {
            let topR = hasPhysicalNotch ? cornerRadiusInsets.closed.top : FaceIDOverlayGeometry.openTopRadius
            return CGSize(
                width: vm.closedNotchSize.width + (topR * 2),
                height: 180
            )
        }
    }

    private var targetFaceIDSize: CGSize {
        if !visualIsFaceIDExpanded {
            return CGSize(
                width: vm.closedNotchSize.width,
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
            return hasPhysicalNotch ? cornerRadiusInsets.closed.top : FaceIDOverlayGeometry.openTopRadius
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
        // When screen is locked or waking from sleep, strictly stay at physical notch / closed island width without expanding for inline/media
        if NotchPulseLockMonitor.isScreenActuallyLocked() {
            return vm.closedNotchSize.width
        }

        let isDynamicIsland = notchStyle == .dynamicIsland
        var chinWidth: CGFloat = vm.closedNotchSize.width // Always match notch width like the user requested

        if coordinator.expandingView.type == .battery && coordinator.expandingView.show
            && vm.notchState == .closed && Defaults[.showPowerStatusNotifications]
        {
            chinWidth = openNotchSize.width
        } else if coordinator.sneakPeek.show && Defaults[.inlineHUD] && coordinator.sneakPeek.type != .music && vm.notchState == .closed {
            chinWidth = InlineHUD.totalWidth(for: coordinator.sneakPeek.type, isDynamicIsland: isDynamicIsland, closedNotchWidth: vm.closedNotchSize.width) + gestureProgress
        } else if Defaults[.enableMediaFeature] && (!coordinator.expandingView.show || coordinator.expandingView.type == .music)
            && vm.notchState == .closed && (musicManager.isPlaying || !musicManager.isPlayerIdle)
            && coordinator.musicLiveActivityEnabled && !vm.hideOnClosed
        {
            let liveHeight: CGFloat = isDynamicIsland ? 32.0 : vm.effectiveClosedNotchHeight
            let artSize: CGFloat = max(18, liveHeight - 12)
            chinWidth = vm.closedNotchSize.width + (artSize * 2) + (isDynamicIsland ? 24 : 32) + gestureProgress
            if isDynamicIsland && coordinator.expandingView.show && coordinator.expandingView.type == .music && Defaults[.sneakPeekStyles] == .inline {
                chinWidth = max(chinWidth, 440 + gestureProgress)
            }
        } else if !coordinator.expandingView.show && vm.notchState == .closed
            && (!musicManager.isPlaying && musicManager.isPlayerIdle) && Defaults[.showNotHumanFace]
            && !vm.hideOnClosed
        {
            let liveHeight: CGFloat = isDynamicIsland ? 32.0 : vm.effectiveClosedNotchHeight
            let artSize: CGFloat = max(18, liveHeight - 12)
            chinWidth = vm.closedNotchSize.width + (artSize * 2) + (isDynamicIsland ? 24 : 32) + gestureProgress
        }
        return chinWidth
    }

    private var computedChinWidth: CGFloat {
        if isFaceIDActive || isFaceIDSettlingAfterClose {
            return targetFaceIDSize.width
        }
        return baseChinWidth
    }

    private var isDynamicIsland: Bool { notchStyle == .dynamicIsland }
    private var baseClosedHeight: CGFloat {
        if hasPhysicalNotch {
            return vm.effectiveClosedNotchHeight
        }
        return isDynamicIsland ? max(32, vm.effectiveClosedNotchHeight) : max(vm.effectiveClosedNotchHeight, 0)
    }
    private var islandRadius: CGFloat {
        if isFaceIDActive {
            if !visualIsFaceIDExpanded {
                return isDynamicIsland ? baseClosedHeight / 2 : max(14, vm.effectiveClosedNotchHeight / 2)
            }
            if isMinimalScan {
                return FaceIDOverlayGeometry.minimalPillOpenHeight / 2
            }
            return FaceIDOverlayGeometry.pillOpenCornerRadius
        }
        return vm.notchState == .open ? 26 : (isDynamicIsland ? baseClosedHeight / 2 : max(14, vm.effectiveClosedNotchHeight / 2))
    }
    private var isDefaultHUDActive: Bool {
        coordinator.sneakPeek.show && !Defaults[.inlineHUD] && coordinator.sneakPeek.type != .music && coordinator.sneakPeek.type != .battery && vm.notchState == .closed
    }
    private var currentNotchWidth: CGFloat {
        if isFaceIDActive {
            return targetFaceIDSize.width
        }
        if vm.notchState == .open {
            return notchOpenWidth
        }
        return computedChinWidth
    }
    private var currentNotchHeight: CGFloat {
        if isFaceIDActive {
            return targetFaceIDSize.height
        }
        if vm.notchState == .open {
            return vm.customOpenHeight ?? vm.notchSize.height
        }
        return isDefaultHUDActive ? baseClosedHeight + 42 : baseClosedHeight
    }
    private var gestureScale: CGFloat {
        guard gestureProgress != 0 else { return 1.0 }
        let scaleFactor = 1.0 + gestureProgress * 0.01
        return max(0.6, scaleFactor)
    }

    @ViewBuilder
    private func applyHitShape<V: View>(_ view: V) -> some View {
        if isDynamicIsland && !hasPhysicalNotch {
            view.contentShape(RoundedRectangle(cornerRadius: islandRadius, style: .continuous))
        } else {
            view.contentShape(currentNotchShape)
        }
    }

    @ViewBuilder
    private var mainNotchContainer: some View {
        let isIsland = isDynamicIsland && !hasPhysicalNotch
        NotchLayout()
            .frame(
                width: currentNotchWidth,
                height: currentNotchHeight,
                alignment: .top
            )
            .padding(
                .horizontal,
                (vm.notchState == .open)
                ? 10
                : (isIsland
                    ? (isFaceIDContentVisible ? 0 : 12)
                    : (isFaceIDContentVisible ? 0 : cornerRadiusInsets.closed.bottom))
            )
            .padding(.horizontal, (vm.notchState == .open) ? 4 : 0)
            .padding(.bottom, (vm.notchState == .open) ? 8 : 0)
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
            .shadow(
                color: isIsland
                    ? .black.opacity(0.65)
                    : (((vm.notchState == .open || isHovering || isFaceIDContentVisible) && Defaults[.enableShadow])
                        ? .black.opacity(0.7) : .clear),
                radius: isIsland ? (vm.notchState == .open || isFaceIDContentVisible ? 14 : 8) : (Defaults[.cornerRadiusScaling] ? 6 : 4),
                x: 0,
                y: isIsland ? 4 : 0
            )
            .padding(.top, isIsland ? dynamicIslandTopOffset : 0)
            .padding(
                .bottom,
                vm.effectiveClosedNotchHeight == 0 ? 10 : 0
            )
    }

    var body: some View {
        ZStack(alignment: .top) {
            dragDetector
            VStack(spacing: 0) {
                mainNotchContainer
                    .conditionalModifier(true) { view in
                        return view
                            .animation(animationSpring, value: vm.notchState)
                            .animation(animationSpring, value: currentNotchWidth)
                            .animation(animationSpring, value: currentNotchHeight)
                            .animation(animationSpring, value: islandRadius)
                            .animation(animationSpring, value: topCornerRadius)
                            .animation(animationSpring, value: bottomCornerRadius)
                            .animation(faceIDAnimation, value: isFaceIDActive)
                            .animation(faceIDAnimation, value: targetFaceIDSize)
                            .animation(.smooth, value: gestureProgress)
                    }
                    .onHover { hovering in
                        handleHover(hovering)
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
                                try? await Task.sleep(for: .milliseconds(250))
                                withAnimation(animationSpring) {
                                    isFaceIDSettlingAfterClose = false
                                }
                            }
                        } else if newPhase != .closed && newPhase != .collapsing {
                            isFaceIDSettlingAfterClose = false
                        }
                        if newPhase == .onboarding {
                            DispatchQueue.main.async {
                                NSApp.activate(ignoringOtherApps: true)
                                for window in NSApp.windows {
                                    if window is NotchPulseSkyLightWindow {
                                        window.makeKeyAndOrderFront(nil)
                                    }
                                }
                            }
                        }
                    }
                    .onChange(of: isFaceIDActive) { _, _ in
                        updateFaceIDExpansion()
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .sharingDidFinish)) { _ in
                        if vm.notchState == .open && !isHovering && !vm.isBatteryPopoverActive {
                            hoverTask?.cancel()
                            hoverTask = Task {
                                try? await Task.sleep(for: .milliseconds(100))
                                guard !Task.isCancelled else { return }
                                await MainActor.run {
                                    if self.vm.notchState == .open && !self.isHovering && !self.vm.isBatteryPopoverActive && !SharingStateManager.shared.preventNotchClose && !ShelfStateViewModel.shared.isPinned && !CalendarStateViewModel.shared.isPinned {
                                        self.doClose()
                                    }
                                }
                            }
                        }
                    }
                    .onChange(of: vm.notchState) { _, newState in
                        if newState == .closed && isHovering {
                            withAnimation {
                                isHovering = false
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
                        if !vm.isBatteryPopoverActive && !isHovering && vm.notchState == .open && !SharingStateManager.shared.preventNotchClose && !ShelfStateViewModel.shared.isPinned && !CalendarStateViewModel.shared.isPinned {
                            hoverTask?.cancel()
                            hoverTask = Task {
                                try? await Task.sleep(for: .milliseconds(100))
                                guard !Task.isCancelled else { return }
                                await MainActor.run {
                                    if !self.vm.isBatteryPopoverActive && !self.isHovering && self.vm.notchState == .open && !SharingStateManager.shared.preventNotchClose && !ShelfStateViewModel.shared.isPinned && !CalendarStateViewModel.shared.isPinned {
                                        self.doClose()
                                    }
                                }
                            }
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
            if newView != .audio && newView != .stats && vm.customOpenHeight != nil {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    vm.customOpenHeight = nil
                }
            }
        }
        .onChange(of: vm.anyDropZoneTargeting) { _, isTargeted in
            anyDropDebounceTask?.cancel()

            if isTargeted {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    coordinator.currentView = .shelf
                }
                if vm.notchState == .closed {
                    doOpen()
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
                } else if NotchPulseLockMonitor.isScreenActuallyLocked() && !Defaults[.showOnLockScreen] && !isFaceIDActive {
                    Rectangle().fill(.clear).frame(width: max(190, vm.closedNotchSize.width) - 20, height: vm.effectiveClosedNotchHeight)
                } else {
                    ZStack {
                        Group {
                            if coordinator.sneakPeek.show && Defaults[.inlineHUD] && (coordinator.sneakPeek.type != .music) && vm.notchState == .closed {
                                InlineHUD(type: $coordinator.sneakPeek.type, value: $coordinator.sneakPeek.value, icon: $coordinator.sneakPeek.icon, hoverAnimation: $isHovering, gestureProgress: $gestureProgress)
                                    .transition(.opacity)
                            } else if Defaults[.enableMediaFeature] && (!coordinator.expandingView.show || coordinator.expandingView.type == .music) && vm.notchState == .closed && (musicManager.isPlaying || !musicManager.isPlayerIdle) && coordinator.musicLiveActivityEnabled && !vm.hideOnClosed {
                                MusicLiveActivity()
                                    .frame(alignment: .center)
                                    .transition(.opacity)
                            } else if !coordinator.expandingView.show && vm.notchState == .closed && (!musicManager.isPlaying && musicManager.isPlayerIdle) && Defaults[.showNotHumanFace] && !vm.hideOnClosed  {
                                NotchPulseFaceAnimation()
                                    .transition(.opacity)
                            } else if vm.notchState == .open {
                                NotchPulseHeader()
                                    .frame(height: max(24, vm.effectiveClosedNotchHeight))
                                    .opacity(gestureProgress != 0 ? 1.0 - min(abs(gestureProgress) * 0.1, 0.3) : 1.0)
                                    .transition(.opacity)
                            } else {
                                Rectangle().fill(.clear).frame(width: max(190, vm.closedNotchSize.width) - 20, height: (notchStyle == .dynamicIsland) ? 32 : vm.effectiveClosedNotchHeight)
                                    .transition(.opacity)
                            }
                        }
                        .opacity((isFaceIDActive || isFaceIDSettlingAfterClose) ? 0 : 1)
                        .scaleEffect((isFaceIDActive || isFaceIDSettlingAfterClose) ? 0.8 : 1.0)
                        .animation(.easeInOut(duration: 0.25), value: (isFaceIDActive || isFaceIDSettlingAfterClose))

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

                    if coordinator.sneakPeek.show && !isFaceIDActive && !isFaceIDSettlingAfterClose {
                        if (coordinator.sneakPeek.type != .music) && !Defaults[.inlineHUD] && vm.notchState == .closed {
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
                            .padding(.bottom, 10)
                            .padding(.leading, 4)
                            .padding(.trailing, 8)
                        }
                        // Old sneak peek music
                        else if coordinator.sneakPeek.type == .music {
                            if vm.notchState == .closed && !vm.hideOnClosed && Defaults[.sneakPeekStyles] == .standard {
                                HStack(alignment: .center) {
                                    Image(systemName: "music.note")
                                    Text(musicManager.songTitle + " - " + musicManager.artistName)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(Defaults[.playerColorTinting] ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6) : .gray)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                }
                                .foregroundStyle(.gray)
                                .padding(.bottom, 10)
                            }
                        }
                    }
                }
            }
            .conditionalModifier((coordinator.sneakPeek.show && (coordinator.sneakPeek.type == .music) && vm.notchState == .closed && !vm.hideOnClosed && Defaults[.sneakPeekStyles] == .standard) || (coordinator.sneakPeek.show && (coordinator.sneakPeek.type != .music) && (vm.notchState == .closed))) { view in
                view
                    .fixedSize()
            }
            .zIndex(2)
            if vm.notchState == .open && !isFaceIDActive {
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
                    }
                }
                .transition(
                    .scale(scale: 0.8, anchor: .top)
                    .combined(with: .opacity)
                    .animation(.smooth(duration: 0.35))
                )
                .zIndex(1)
                .allowsHitTesting(vm.notchState == .open)
                .opacity(gestureProgress != 0 ? 1.0 - min(abs(gestureProgress) * 0.1, 0.3) : 1.0)
            }
        }
        .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], delegate: GeneralDropTargetDelegate(isTargeted: $vm.generalDropTargeting))
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
                FaceIDScanAnimationView(media: controller.media)
                    .padding(.leading, isDynamicIsland ? FaceIDOverlayGeometry.pillContentPaddingLeading : FaceIDOverlayGeometry.notchContentPaddingLeading)
                    .padding(.trailing, isDynamicIsland ? FaceIDOverlayGeometry.pillContentPaddingTrailing : FaceIDOverlayGeometry.notchContentPaddingTrailing)
                    .padding(.top, isDynamicIsland ? FaceIDOverlayGeometry.pillContentPaddingTop : FaceIDOverlayGeometry.notchContentPaddingTop)
                    .padding(.bottom, isDynamicIsland ? FaceIDOverlayGeometry.pillContentPaddingBottom : FaceIDOverlayGeometry.notchContentPaddingBottom)
                    .scaleEffect(0.80)
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
    func NotchPulseFaceAnimation() -> some View {
        let isDynamicIsland = notchStyle == .dynamicIsland
        let faceHeight: CGFloat = isDynamicIsland ? 32.0 : vm.effectiveClosedNotchHeight
        HStack {
            HStack {
                Rectangle()
                    .fill(.clear)
                    .frame(
                        width: max(0, faceHeight - 12),
                        height: max(0, faceHeight - 12)
                    )
                Rectangle()
                    .fill(.black)
                    .frame(width: max(0, vm.closedNotchSize.width - 20))
                MinimalFaceFeatures()
            }
        }.frame(
            height: faceHeight,
            alignment: .center
        )
    }

    @ViewBuilder
    func MusicLiveActivity() -> some View {
        let isDynamicIsland = notchStyle == .dynamicIsland
        let liveHeight: CGFloat = isDynamicIsland ? 32.0 : vm.effectiveClosedNotchHeight
        let artSize: CGFloat = max(18, liveHeight - 12)

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
                .padding(.leading, isDynamicIsland ? 0 : 5)
                .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)

            Rectangle()
                .fill(.black)
                .overlay(
                    HStack(alignment: .top) {
                        if coordinator.expandingView.show
                            && coordinator.expandingView.type == .music
                        {
                            Text(musicManager.songTitle)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .foregroundStyle(
                                    Defaults[.coloredSpectrogram]
                                        ? Color(nsColor: musicManager.avgColor) : Color.gray
                                )
                                .frame(maxWidth: 100, alignment: .leading)
                            .opacity(
                                (coordinator.expandingView.show
                                    && Defaults[.sneakPeekStyles] == .inline)
                                    ? 1 : 0
                            )
                            Spacer(minLength: isDynamicIsland ? 20 : vm.closedNotchSize.width + 12)
                            // Song Artist
                            Text(musicManager.artistName)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .foregroundStyle(
                                    Defaults[.coloredSpectrogram]
                                        ? Color(nsColor: musicManager.avgColor)
                                        : Color.gray
                                )
                                .opacity(
                                    (coordinator.expandingView.show
                                        && coordinator.expandingView.type == .music
                                        && Defaults[.sneakPeekStyles] == .inline)
                                        ? 1 : 0
                                )
                        }
                    }
                )
                .frame(
                    width: (coordinator.expandingView.show
                        && coordinator.expandingView.type == .music
                        && Defaults[.sneakPeekStyles] == .inline)
                        ? (isDynamicIsland ? 360 : 380)
                        : (vm.closedNotchSize.width + (isDynamicIsland ? 12 : 12))
                )

            HStack {
                if useMusicVisualizer {
                    Rectangle()
                        .fill(
                            Defaults[.coloredSpectrogram]
                                ? Color(nsColor: musicManager.avgColor).gradient
                                : Color.gray.gradient
                        )
                        .frame(width: 50, alignment: .center)
                        .matchedGeometryEffect(id: "spectrum", in: albumArtNamespace)
                        .mask {
                            AudioSpectrumView(isPlaying: $musicManager.isPlaying)
                                .frame(width: 16, height: 12)
                        }
                } else {
                    LottieAnimationContainer()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(.trailing, isDynamicIsland ? 0 : 5)
            .frame(
                width: max(
                    0,
                    artSize + (isDynamicIsland ? 0 : gestureProgress / 2)
                ),
                height: artSize,
                alignment: .center
            )
        }
        .frame(
            height: liveHeight,
            alignment: .center
        )
    }

    @ViewBuilder
    var dragDetector: some View {
        EmptyView()
    }

    private func doOpen() {
        withAnimation(animationSpring) {
            vm.open()
        }
    }

    private func doClose() {
        withAnimation(animationSpring) {
            vm.close()
        }
    }

    // MARK: - Hover Management

    private func shouldHandleFaceIDHover(hovering: Bool) -> Bool {
        if NotchPulseLockMonitor.isScreenActuallyLocked() { return true }
        if isFaceIDActive && (faceIDOverlay.phase == .scanning || faceIDOverlay.phase == .failure) { return true }
        return false
    }

    private func shouldHandleFaceIDTap() -> Bool {
        if NotchPulseLockMonitor.isScreenActuallyLocked() { return true }
        if isFaceIDActive && (faceIDOverlay.phase == .failure || faceIDOverlay.phase == .scanning) { return true }
        return false
    }

    private func handleHover(_ hovering: Bool) {
        if coordinator.firstLaunch && !FeatureTourController.shared.isTourActive { return }
        if faceIDOverlay.phase != .closed || (faceIDOverlay.isArmed && NotchPulseLockMonitor.isScreenActuallyLocked()) || isFaceIDSettlingAfterClose { return }
        hoverTask?.cancel()
        
        if hovering {
            if NotchPulseLockMonitor.isScreenActuallyLocked() {
                FaceIDOverlayController.shared.activate()
                return
            }

            withAnimation(animationSpring) {
                isHovering = true
            }
            
            if vm.notchState == .closed && Defaults[.enableHaptics] {
                haptics.toggle()
            }
            
            guard vm.notchState == .closed,
                  !coordinator.sneakPeek.show,
                  Defaults[.openNotchOnHover] else { return }
            
            let delay = max(0.0, Defaults[.minimumHoverDuration])
            if delay <= 0.02 {
                self.doOpen()
                return
            }
            
            hoverTask = Task {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    guard !NotchPulseLockMonitor.isScreenActuallyLocked(),
                          self.vm.notchState == .closed,
                          self.isHovering,
                          !self.coordinator.sneakPeek.show else { return }
                    
                    self.doOpen()
                }
            }
        } else {
            hoverTask = Task {
                try? await Task.sleep(for: .milliseconds(280))
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    withAnimation(animationSpring) {
                        self.isHovering = false
                        if self.vm.notchState == .open && !self.vm.isBatteryPopoverActive && !SharingStateManager.shared.preventNotchClose && !ShelfStateViewModel.shared.isPinned && !CalendarStateViewModel.shared.isPinned && !FeatureTourController.shared.isTourActive && !self.vm.anyDropZoneTargeting && !self.vm.dropEvent {
                            self.vm.close()
                        }
                    }
                }
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

struct GeneralDropTargetDelegate: DropDelegate {
    @Binding var isTargeted: Bool

    func dropEntered(info: DropInfo) {
        isTargeted = true
        Task { @MainActor in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                NotchPulseViewCoordinator.shared.currentView = .shelf
            }
        }
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .copy)
    }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        let providers = info.itemProviders(for: [.fileURL, .url, .utf8PlainText, .plainText, .data])
        if !providers.isEmpty {
            ShelfStateViewModel.shared.load(providers)
            return true
        }
        return true
    }
}
