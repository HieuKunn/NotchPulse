//
//  ContentView.swift
//  NotchPulseApp
//
//  Created by Harsh Vardhan Goswami  on 02/08/24
//  Modified by Richard Kunkli on 24/08/2024.
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
    /// Independent cursor-presence poll. The physical-rect poll in handleHover only
    /// starts after an onHover(enter) event, but SwiftUI can silently stop delivering
    /// enter events after the closed silhouette reshapes (music chin grows/shrinks),
    /// leaving hover-to-open dead while the cursor is sitting right on the notch.
    /// This loop starts from app launch and fires the open whenever the cursor is
    /// physically inside the notch rect while closed — no enter event required.
    @State private var hoverPresenceTask: Task<Void, Never>?
    /// Dwell countdown anchor for openFromHoverIfPhysicallyInside: set when the
    /// cursor is first detected inside the physical notch rect, cleared whenever a
    /// check finds it outside. Not a timer — the presence poll advances it.
    @State private var hoverDwellDeadline: ContinuousClock.Instant?
    @State private var isHovering: Bool = false
    /// Staged reveal: false while the black silhouette is springing open, true once
    /// content fades in near the end of the open animation. Reset on close so every
    /// open plays the same "frame first, content after" sequence.
    @State private var isContentRevealed: Bool = false
    @State private var contentRevealTask: Task<Void, Never>?
    /// Keeps the open-state tab content mounted through the closing animation so
    /// the collapsing black frame swallows REAL content instead of an empty box.
    @State private var contentLingerOnClose: Bool = false
    /// Same staged choreography for the FaceID panel: content fades in shortly after
    /// the panel starts expanding, and fades OUT at the start of a collapse so it
    /// never rides the shrinking silhouette.
    @State private var faceIDRevealContent: Bool = false
    @State private var faceIDRevealTask: Task<Void, Never>?
    @State private var anyDropDebounceTask: Task<Void, Never>?

    @State private var gestureProgress: CGFloat = .zero

    @State private var haptics: Bool = false

    @Namespace var albumArtNamespace

    @Default(.useMusicVisualizer) var useMusicVisualizer

    @Default(.showNotHumanFace) var showNotHumanFace
    @Default(.notchStyle) var notchStyle
    @Default(.dynamicIslandTopOffset) var dynamicIslandTopOffset
    @Default(.notchOpenWidth) var notchOpenWidth
    @Default(.expandedDragDetection) var expandedDragDetection: Bool
    @Default(.dragDetectionPadding) var dragDetectionPadding: Double

    // Shared canonical spring for movement/resizing
    private var animationSpring: Animation { NotchPulseViewModel.notchSpring }
    private let openAnimation = Animation.spring(response: FaceIDOverlayGeometry.openSpringResponse, dampingFraction: FaceIDOverlayGeometry.openSpringDamping, blendDuration: 0)
    private let closeAnimation = Animation.spring(response: FaceIDOverlayGeometry.closeSpringResponse, dampingFraction: FaceIDOverlayGeometry.closeSpringDamping, blendDuration: 0)
    private var faceIDAnimation: Animation {
        let isFaceIDOpening = isFaceIDActive && faceIDOverlay.phase != .collapsing && faceIDOverlay.phase != .closed
        return isFaceIDOpening ? openAnimation : closeAnimation
    }

    private let extendedHoverPadding: CGFloat = 30
    private let zeroHeightHoverPadding: CGFloat = 10

    private var faceIDOverlay: FaceIDOverlayController {
        FaceIDOverlayController.shared
    }

    private var isFaceIDActive: Bool {
        if faceIDOverlay.isPresenting || faceIDOverlay.phase != .closed {
            if let targetUUID = NotchPulseCameraDeviceCatalog.cachedTargetScreenUUID() {
                let currentUUID = vm.screenUUID ?? currentScreen?.displayUUID ?? coordinator.selectedScreenUUID
                return currentUUID == targetUUID
            }
            return true
        }
        return false
    }

    private var isFaceIDContentActive: Bool {
        isFaceIDActive
    }

    private var isFaceIDContentVisible: Bool {
        guard isFaceIDActive else { return false }
        switch faceIDOverlay.phase {
        case .scanning, .success, .failure, .onboarding, .collapsing:
            return true
        case .closed:
            return false
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

    private var targetFaceIDSize: CGSize {
        let isDynamicIsland = notchStyle == .dynamicIsland
        let controller = faceIDOverlay

        // When closed or collapsing, target the computed chin width so the notch fluidly pulls up into inline/media content!
        if controller.phase == .closed || controller.phase == .collapsing {
            let baseHeight = isDynamicIsland ? max(32, vm.effectiveClosedNotchHeight) : max(vm.effectiveClosedNotchHeight, 0)
            return CGSize(
                width: baseChinWidth,
                height: baseHeight
            )
        }

        if case .onboarding(let enrollmentController) = controller.content {
            return enrollmentController.panelSize
        }

        if isMinimalScan {
            if isDynamicIsland {
                return CGSize(
                    width: FaceIDOverlayGeometry.minimalPillOpenWidth,
                    height: max(32, vm.effectiveClosedNotchHeight)
                )
            } else {
                return CGSize(
                    width: vm.closedNotchSize.width + FaceIDOverlayGeometry.minimalNotchFlankWidth * 2,
                    height: vm.effectiveClosedNotchHeight
                )
            }
        }

        if isDynamicIsland {
            return CGSize(
                width: max(FaceIDOverlayGeometry.pillOpenSize.width, vm.closedNotchSize.width),
                height: FaceIDOverlayGeometry.pillOpenSize.height
            )
        } else {
            return CGSize(
                width: max(vm.closedNotchSize.width + FaceIDOverlayGeometry.openTopRadius * 2, FaceIDOverlayGeometry.notchOpenSize.width),
                height: FaceIDOverlayGeometry.notchOpenSize.height
            )
        }
    }

    private var topCornerRadius: CGFloat {
        if isFaceIDActive {
            if faceIDOverlay.phase == .collapsing || faceIDOverlay.phase == .closed {
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
            if faceIDOverlay.phase == .collapsing || faceIDOverlay.phase == .closed {
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
            return FaceIDOverlayGeometry.openBottomRadius
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
        let defaultClosedWidth: CGFloat = isDynamicIsland ? 80 : vm.closedNotchSize.width

        if vm.hideOnClosed && vm.notchState == .closed {
            return 0
        }

        if NotchPulseLockMonitor.isScreenActuallyLocked() && !Defaults[.showOnLockScreen] {
            return defaultClosedWidth
        }

        var chinWidth: CGFloat = defaultClosedWidth

        if coordinator.expandingView.type == .battery && coordinator.expandingView.show
            && Defaults[.showPowerStatusNotifications]
        {
            chinWidth = openNotchSize.width
        } else if coordinator.sneakPeek.show && coordinator.sneakPeek.type != .music && (Defaults[.inlineHUD] || coordinator.sneakPeek.type == .battery) {
            chinWidth = InlineHUD.totalWidth(for: coordinator.sneakPeek.type, isDynamicIsland: isDynamicIsland, closedNotchWidth: vm.closedNotchSize.width) + gestureProgress
        // NOTE: ĐẢM BẢO TOÀN BỘ UI CỦA DYNAMIC ISLAND VÀ NOTCH PHẢI GIỐNG HỆT NHAU TRỪ KHI NGƯỜI DÙNG YÊU CẦU SỬA
        } else if coordinator.sneakPeek.show && !Defaults[.inlineHUD] && coordinator.sneakPeek.type != .music && coordinator.sneakPeek.type != .battery {
            chinWidth = max(isDynamicIsland ? 220 : vm.closedNotchSize.width, 220) + gestureProgress
        } else if coordinator.sneakPeek.show && coordinator.sneakPeek.type == .music && Defaults[.sneakPeekStyles] == .standard && !vm.hideOnClosed {
            chinWidth = max(isDynamicIsland ? 260 : (vm.closedNotchSize.width + 40), 260) + gestureProgress
        } else if (!coordinator.expandingView.show || coordinator.expandingView.type == .music)
            && (musicManager.isPlaying || !musicManager.isPlayerIdle)
            && coordinator.musicLiveActivityEnabled && !vm.hideOnClosed
        {
            let liveHeight: CGFloat = isDynamicIsland ? 32.0 : vm.effectiveClosedNotchHeight
            let artSize: CGFloat = max(18, liveHeight - 12)
            chinWidth = vm.closedNotchSize.width + (artSize * 2) + (isDynamicIsland ? 32 : 44) + gestureProgress
            if coordinator.expandingView.show && coordinator.expandingView.type == .music && Defaults[.sneakPeekStyles] == .inline {
                chinWidth = max(chinWidth, (isDynamicIsland ? 440 : 460) + gestureProgress)
            }
        } else if !coordinator.expandingView.show
            && (!musicManager.isPlaying && musicManager.isPlayerIdle) && Defaults[.showNotHumanFace]
            && !vm.hideOnClosed
        {
            let liveHeight: CGFloat = isDynamicIsland ? 32.0 : vm.effectiveClosedNotchHeight
            let artSize: CGFloat = max(18, liveHeight - 12)
            chinWidth = vm.closedNotchSize.width + (artSize * 2) + (isDynamicIsland ? 32 : 44) + gestureProgress
        }
        return chinWidth
    }

    private var computedChinWidth: CGFloat {
        if isFaceIDActive {
            return targetFaceIDSize.width
        }
        return baseChinWidth
    }

    private var isDynamicIsland: Bool { notchStyle == .dynamicIsland }
    private var baseClosedHeight: CGFloat {
        if vm.hideOnClosed { return 0 }
        return isDynamicIsland ? max(32, vm.effectiveClosedNotchHeight) : max(vm.effectiveClosedNotchHeight, 0)
    }
    private var islandRadius: CGFloat {
        if isFaceIDActive && isFaceIDContentVisible {
            if isMinimalScan {
                return FaceIDOverlayGeometry.minimalPillOpenHeight / 2
            }
            return FaceIDOverlayGeometry.pillOpenCornerRadius
        }
        return vm.notchState == .open ? 26 : (isDynamicIsland ? baseClosedHeight / 2 : max(14, vm.effectiveClosedNotchHeight / 2))
    }
    private var isBottomRowHUDActive: Bool {
        coordinator.sneakPeek.show && !Defaults[.inlineHUD] && coordinator.sneakPeek.type != .music && coordinator.sneakPeek.type != .battery && vm.notchState == .closed
    }
    private var isBottomRowMusicActive: Bool {
        coordinator.sneakPeek.show && coordinator.sneakPeek.type == .music && Defaults[.sneakPeekStyles] == .standard && vm.notchState == .closed && !vm.hideOnClosed
    }
    // NOTE: ĐẢM BẢO TOÀN BỘ UI CỦA DYNAMIC ISLAND VÀ NOTCH PHẢI GIỐNG HỆT NHAU TRỪ KHI NGƯỜI DÙNG YÊU CẦU SỬA
    private let bottomRowHUDHeight: CGFloat = 40

    private var isBottomRowActive: Bool {
        isBottomRowHUDActive || isBottomRowMusicActive
    }
    private var currentNotchWidth: CGFloat {
        if isFaceIDActive {
            return targetFaceIDSize.width
        }
        if vm.notchState == .closed && vm.hideOnClosed {
            return 0
        }
        // Closed: bind the silhouette to the live chin width (inline HUD / music live
        // activity / face) so it grows with content. Open: notchSize wins and chin width
        // is always smaller, so max() stays continuous — no interpolation jumps.
        if vm.notchState == .closed {
            return computedChinWidth
        }
        return max(vm.notchSize.width, computedChinWidth)
    }
    private var currentNotchHeight: CGFloat {
        if isFaceIDActive {
            return targetFaceIDSize.height
        }
        if vm.notchState == .closed && vm.hideOnClosed {
            return 0
        }
        let heightFromState = vm.customOpenHeight ?? vm.notchSize.height
        let minHeight = isBottomRowActive ? baseClosedHeight + bottomRowHUDHeight : baseClosedHeight
        return max(heightFromState, minHeight)
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

    var body: some View {
        ZStack(alignment: .top) {
            VStack(alignment: .center, spacing: 0) {
                let mainLayout = NotchLayout()
                    .frame(
                        width: currentNotchWidth,
                        height: currentNotchHeight,
                        alignment: .top
                    )
                    .clipped()
                    .opacity(vm.notchState == .closed && vm.hideOnClosed && !isFaceIDActive ? 0 : 1)
                    .background(.black)
                    .conditionalModifier(isDynamicIsland) { view in
                        view
                            .clipShape(RoundedRectangle(cornerRadius: islandRadius, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: islandRadius, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8)
                            }
                    }
                    .conditionalModifier(!isDynamicIsland) { view in
                        view
                            .clipShape(currentNotchShape)
                            .overlay(alignment: .top) {
                                Rectangle()
                                    .fill(.black)
                                    .frame(height: 1)
                                    .padding(.horizontal, topCornerRadius)
                            }
                    }
                    .shadow(
                        color: isDynamicIsland
                            ? .black.opacity(0.65)
                            : (((vm.notchState == .open || isHovering || isFaceIDContentVisible) && Defaults[.enableShadow])
                                ? .black.opacity(0.7) : .clear),
                        radius: isDynamicIsland ? (vm.notchState == .open || isFaceIDContentVisible ? 14 : 8) : (Defaults[.cornerRadiusScaling] ? 6 : 4),
                        x: 0,
                        y: isDynamicIsland ? 4 : 0
                    )
                    .padding(.top, isDynamicIsland ? dynamicIslandTopOffset : 0)
                    .padding(
                        .bottom,
                        vm.effectiveClosedNotchHeight == 0 ? 10 : 0
                    )
                    // Canonical value-scoped springs (mirrors boring.notch baseline).
                    // Re-applying the animation on EVERY commit where the tracked value
                    // changes keeps the spring alive even when unrelated state changes
                    // flush a non-animated transaction mid-flight — without these, the
                    // notch/FaceID panel snaps open instantly instead of easing frame by frame.
                    .animation(vm.notchState == .open ? animationSpring : NotchPulseViewModel.notchCloseSpring, value: vm.notchState)
                    .animation(.smooth(duration: 0.35), value: coordinator.sneakPeek.show)
                    .animation(.smooth(duration: 0.35), value: coordinator.expandingView.show)
                    .animation(faceIDAnimation, value: faceIDOverlay.phase)
                    .animation(.smooth, value: gestureProgress)
                    // Music start/stop and metadata changes silently recompute baseChinWidth
                    // (the closed notch silhouette). Without a scoped spring on that input,
                    // the width change lands in an unanimated transaction and the notch
                    // visibly snaps/jerks during normal use.
                    .animation(NotchPulseViewModel.notchSpring, value: baseChinWidth)
                
                applyHitShape(mainLayout)
                    .onHover { hovering in
                        if shouldHandleFaceIDHover(hovering: hovering) {
                            FaceIDOverlayController.shared.setHovering(hovering)
                            if hovering && faceIDOverlay.phase != .onboarding && faceIDOverlay.phase != .collapsing {
                                FaceIDOverlayController.shared.activate()
                            }
                            return
                        }

                        if vm.hideOnClosed { return }
                        handleHover(hovering)
                    }
                    // Event-independent hover watchdog: survives SwiftUI silently
                    // dropping enter events when the closed silhouette reshapes.
                    .task { startHoverPresencePoll() }
                    .conditionalModifier(!isFaceIDContentActive && vm.notchState == .closed) { view in
                        view.onTapGesture {
                            if vm.hideOnClosed { return }
                            if shouldHandleFaceIDTap() {
                                FaceIDOverlayController.shared.activate()
                                return
                            }
                            if !NotchPulseLockMonitor.isScreenActuallyLocked() {
                                doOpen()
                            }
                        }
                    }
                    .onChange(of: faceIDOverlay.phase) { _, newPhase in
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
                        // FaceID content is clipped by the panel silhouette (same
                        // mechanism as the notch content), so the static unlock image
                        // can appear the instant the phase becomes visible — the old
                        // 120ms delay + 0.18s fade left the panel as a pure black box
                        // during the whole drop-down (user: "vẫn để nguyên màu đen").
                        faceIDRevealTask?.cancel()
                        faceIDRevealTask = nil
                        switch newPhase {
                        case .closed:
                            faceIDRevealContent = false
                        case .collapsing:
                            faceIDRevealContent = false
                        case .scanning, .success, .failure, .onboarding:
                            faceIDRevealContent = true
                        }
                    }
                    // Failsafe hover-activation while Face ID is armed on the lock screen:
                    // SwiftUI `.onHover` tracking silently MISSES enter events on
                    // SkyLight-delegated windows, so hovering the notch sometimes did
                    // nothing until the user clicked (a real event always arrives). This
                    // lightweight poll runs ONLY while locked + armed, and edge-triggers
                    // on the cursor entering the notch region — driving the exact same
                    // activation path as hover/click, immune to missed tracking events.
                    .task(id: faceIDOverlay.isArmed) {
                        guard faceIDOverlay.isArmed else { return }
                        var wasInside = isMousePhysicallyInsideNotch()
                        while !Task.isCancelled,
                              faceIDOverlay.isArmed,
                              NotchPulseLockMonitor.isScreenActuallyLocked() {
                            try? await Task.sleep(for: .milliseconds(150))
                            guard !Task.isCancelled else { return }
                            let isInside = isMousePhysicallyInsideNotch()
                            let phase = faceIDOverlay.phase
                            if isInside && !wasInside && (phase == .closed || phase == .failure) {
                                FaceIDOverlayController.shared.setHovering(true)
                                FaceIDOverlayController.shared.activate()
                            }
                            wasInside = isInside
                        }
                    }
                    .conditionalModifier(Defaults[.enableGestures] && !isFaceIDActive) { view in
                        view
                            .panGesture(direction: .down) { translation, phase in
                                handleDownGesture(translation: translation, phase: phase)
                            }
                    }
                    .conditionalModifier(Defaults[.closeGestureEnabled] && Defaults[.enableGestures] && !isFaceIDActive) { view in
                        view
                            .panGesture(direction: .up) { translation, phase in
                                handleUpGesture(translation: translation, phase: phase)
                            }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .sharingDidFinish)) { _ in
                        if vm.notchState == .open && !isHovering && !vm.isBatteryPopoverActive && !SharingStateManager.shared.preventNotchClose && !ShelfStateViewModel.shared.isPinned && !CalendarStateViewModel.shared.isPinned {
                            hoverTask?.cancel()
                            hoverTask = Task {
                                try? await Task.sleep(for: .milliseconds(100))
                                guard !Task.isCancelled else { return }
                                await MainActor.run {
                                    if self.vm.notchState == .open && !self.isHovering && !self.vm.isBatteryPopoverActive && !SharingStateManager.shared.preventNotchClose && !ShelfStateViewModel.shared.isPinned && !CalendarStateViewModel.shared.isPinned {
                                        self.vm.close()
                                    }
                                }
                            }
                        }
                    }
                    .onChange(of: vm.notchState) { _, newState in
                        if newState == .closed && isHovering {
                            isHovering = false
                        }
                        // Content reveal is now handled entirely by the shape clip on
                        // the content group (clipped to the same animated silhouette the
                        // black frame draws). The flag stays as a hit-testing gate only:
                        // enabled the moment the notch opens, disabled the moment it
                        // starts closing.
                        contentRevealTask?.cancel()
                        contentRevealTask = nil
                        isContentRevealed = (newState == .open)
                        if newState == .open {
                            contentLingerOnClose = true
                        } else {
                            // Keep real content visible inside the collapsing silhouette
                            // for the whole close spring (~500ms), then drop it.
                            contentRevealTask = Task {
                                try? await Task.sleep(for: .milliseconds(650))
                                guard !Task.isCancelled else { return }
                                contentLingerOnClose = false
                            }
                        }
                    }
                    .onChange(of: coordinator.sneakPeek.show) { _, showing in
                        // When a HUD/sneak-peek disappears while the cursor is parked on
                        // the notch, SwiftUI often delivers NO fresh enter event (nothing
                        // changed from its tracking perspective), so the notch never
                        // opened until the user clicked or moved away and back.
                        // Re-evaluate physically: cursor genuinely inside → open via the
                        // normal hover path (honors minimumHoverDuration and guards).
                        if !showing, vm.notchState == .closed, !vm.hideOnClosed {
                            if isMousePhysicallyInsideNotch() {
                                handleHover(true)
                            }
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .closeNotchPreview)) { _ in
                        vm.close()
                    }
                    .onReceive(DistributedNotificationCenter.default().publisher(for: NSNotification.Name("com.apple.screenIsLocked"))) { _ in
                        handleScreenLock()
                    }
                    .onReceive(DistributedNotificationCenter.default().publisher(for: NSNotification.Name("com.apple.screensaver.didstart"))) { _ in
                        handleScreenLock()
                    }
                    .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)) { _ in
                        handleScreenLock()
                    }
                    .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.screensDidSleepNotification)) { _ in
                        handleScreenLock()
                    }
                    .onReceive(DistributedNotificationCenter.default().publisher(for: NSNotification.Name("com.apple.screenIsUnlocked"))) { _ in
                        withAnimation(animationSpring) {
                            // Trigger layout refresh on unlock
                        }
                    }
                    .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.screensDidWakeNotification)) { _ in
                        withAnimation(animationSpring) {
                            if NotchPulseLockMonitor.isScreenActuallyLocked() {
                                handleScreenLock()
                            }
                        }
                    }
                    .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in
                        withAnimation(animationSpring) {
                            if NotchPulseLockMonitor.isScreenActuallyLocked() {
                                handleScreenLock()
                            }
                        }
                    }
                    .onAppear {
                        if NotchPulseLockMonitor.isScreenActuallyLocked() {
                            handleScreenLock()
                        }
                        // Reveal safety: if this view was (re)created while the notch is
                        // ALREADY open (display change, view re-init), onChange(of:
                        // notchState) never fired — reveal content immediately so the
                        // open notch never stays an empty black frame.
                        if vm.notchState == .open && !isContentRevealed && contentRevealTask == nil {
                            isContentRevealed = true
                        }
                        // FaceID reveal safety: if this view was (re)created mid-panel
                        // (phase already visible), onChange never fired — reveal now so
                        // the panel never stays an empty silhouette.
                        if isFaceIDContentVisible && !faceIDRevealContent && faceIDRevealTask == nil {
                            faceIDRevealContent = true
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
                                        self.vm.close()
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
        .onChange(of: vm.isHoveringFromRadar) { _, isRadarHovering in
            // BUGFIX: this handler previously fired unconditionally — whenever the
            // DragDetector radar toggled, the notch processed hover even with
            // "open on hover" or "extend hover area" disabled, and a stale radar
            // flag (set before the setting was turned off) kept the notch open and
            // blocked every auto-close path. Gate strictly on BOTH settings.
            guard Defaults[.openNotchOnHover] && Defaults[.extendHoverArea] else { return }
            if vm.hideOnClosed { return }
            handleHover(isRadarHovering)
        }
        .onChange(of: coordinator.currentView) { _, newView in
            guard !SharingStateManager.shared.preventNotchClose else { return }
            if vm.customOpenHeight != nil {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    vm.customOpenHeight = nil
                }
            }
        }
        .onChange(of: vm.anyDropZoneTargeting) { _, isTargeted in
            anyDropDebounceTask?.cancel()

            // Shelf only opens via shake gesture — dragging near the open notch no longer
            // auto-switches to the shelf tab.
            if isTargeted { return }

            anyDropDebounceTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(800))
                guard !Task.isCancelled else { return }

                vm.dropEvent = false
                if !self.isHovering && !vm.isHoveringFromRadar && !vm.dragDetectorTargeting && !vm.anyDropZoneTargeting && !SharingStateManager.shared.preventNotchClose && !ShelfStateViewModel.shared.isPinned && !CalendarStateViewModel.shared.isPinned {
                    self.vm.close()
                }
            }
        }
    }

    @ViewBuilder
    func NotchLayout() -> some View {
        VStack(alignment: .center, spacing: 0) {
            VStack(alignment: .center, spacing: 0) {
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
                } else if !isFaceIDActive && NotchPulseLockMonitor.isScreenActuallyLocked() && !Defaults[.showOnLockScreen] {
                    Rectangle().fill(.clear).frame(width: (notchStyle == .dynamicIsland) ? 80 : vm.closedNotchSize.width, height: vm.effectiveClosedNotchHeight)
                } else {
                    ZStack {
                        if !isFaceIDContentVisible {
                            Group {
                                if (!NotchPulseLockMonitor.isScreenActuallyLocked() || Defaults[.showOnLockScreen]) && coordinator.sneakPeek.show && (Defaults[.inlineHUD] || coordinator.sneakPeek.type == .battery) && (coordinator.sneakPeek.type != .music) && vm.notchState == .closed {
                                    InlineHUD(type: $coordinator.sneakPeek.type, value: $coordinator.sneakPeek.value, icon: $coordinator.sneakPeek.icon, hoverAnimation: $isHovering, gestureProgress: $gestureProgress)
                                        .transition(.opacity.combined(with: .scale(scale: 0.75, anchor: .center)))
                                } else if !isBottomRowActive && (!coordinator.expandingView.show || coordinator.expandingView.type == .music) && vm.notchState == .closed && (musicManager.isPlaying || !musicManager.isPlayerIdle) && coordinator.musicLiveActivityEnabled && !vm.hideOnClosed && (!NotchPulseLockMonitor.isScreenActuallyLocked() || Defaults[.showOnLockScreen]) {
                                    MusicLiveActivity()
                                        .frame(alignment: .center)
                                        .transition(.opacity.combined(with: .scale(scale: 0.75, anchor: .center)))
                                } else if !isBottomRowActive && !coordinator.expandingView.show && vm.notchState == .closed && (!musicManager.isPlaying && musicManager.isPlayerIdle) && Defaults[.showNotHumanFace] && !vm.hideOnClosed && (!NotchPulseLockMonitor.isScreenActuallyLocked() || Defaults[.showOnLockScreen])  {
                                    NotchPulseFaceAnimation()
                                        .transition(.opacity.combined(with: .scale(scale: 0.75, anchor: .center)))
                                } else if vm.notchState == .open {
                                    NotchPulseHeader()
                                        .frame(height: max(24, vm.effectiveClosedNotchHeight))
                                        .opacity(gestureProgress != 0 ? 1.0 - min(abs(gestureProgress) * 0.1, 0.3) : 1.0)
                                } else {
                                    Rectangle().fill(.clear).frame(width: (notchStyle == .dynamicIsland) ? 80 : vm.closedNotchSize.width, height: baseClosedHeight)
                                }
                            }
                        }

                        if isFaceIDContentVisible {
                            FaceIDContentView()
                                // Clipped by the panel silhouette — the static unlock image
                                // is visible the instant the panel is on screen (reveal flag
                                // now flips with the phase itself, no 120ms delay + fade).
                                .opacity(faceIDRevealContent ? 1 : 0)
                        }

                        // Open-state tab content lives INSIDE the black silhouette so
                        // the expanding black frame mechanically UNCOVERS it (and the
                        // collapsing frame swallows it back) — the silhouette's own
                        // .clipped() bounds are the reveal mask. Zero opacity fades:
                        // the old sibling-with-cross-fade used to look like a
                        // translucent ghost floating over the desktop. The closed-state
                        // views above stay on top (ZStack order) so the closed
                        // silhouette never shows open content bleeding through.
                        if (vm.notchState != .closed || contentLingerOnClose) && !isFaceIDContentVisible {
                            Group {
                                switch coordinator.currentView {
                                case .home:
                                    NotchHomeView(albumArtNamespace: albumArtNamespace)
                                        .id(NotchViews.home)
                                case .shelf:
                                    ShelfView()
                                        .id(NotchViews.shelf)
                                case .stats:
                                    if vm.notchState == .open {
                                        StatsView()
                                            .id(NotchViews.stats)
                                    }
                                case .clipboard:
                                    ClipboardNotchView()
                                        .environmentObject(vm)
                                        .id(NotchViews.clipboard)
                                }
                            }
                            .frame(
                                width: openNotchWidth,
                                height: vm.customOpenHeight ?? openNotchSize.height,
                                alignment: .top
                            )
                            .padding(.horizontal, isDynamicIsland ? 0 : topCornerRadius)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .allowsHitTesting(vm.notchState == .open)
                        }
                    }

                    // NOTE: ĐẢM BẢO TOÀN BỘ UI CỦA DYNAMIC ISLAND VÀ NOTCH PHẢI GIỐNG HỆT NHAU TRỪ KHI NGƯỜI DÙNG YÊU CẦU SỬA
                    if coordinator.sneakPeek.show && !isFaceIDActive {
                        if (coordinator.sneakPeek.type != .music && coordinator.sneakPeek.type != .battery) && !Defaults[.inlineHUD] && vm.notchState == .closed {
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
                            .padding(.horizontal, 16)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .frame(height: bottomRowHUDHeight, alignment: .center)
                        }
                        // Old sneak peek music
                        else if coordinator.sneakPeek.type == .music {
                            if vm.notchState == .closed && !vm.hideOnClosed && Defaults[.sneakPeekStyles] == .standard {
                                HStack(alignment: .center, spacing: 8) {
                                    Image(systemName: "music.note")
                                        .frame(width: 16, alignment: .center)
                                    GeometryReader { geo in
                                        MarqueeText(.constant(musicManager.songTitle + " - " + musicManager.artistName),  textColor: Defaults[.playerColorTinting] ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6) : .gray, minDuration: 1, frameWidth: geo.size.width)
                                    }
                                }
                                .foregroundStyle(.gray)
                                .padding(.horizontal, 16)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .frame(height: bottomRowHUDHeight, alignment: .center)
                            }
                        }
                    }
                }
            }
              .conditionalModifier(!isFaceIDActive && isBottomRowActive) { view in
                  view
                      .fixedSize(horizontal: false, vertical: true)
              }
              .zIndex(2)
        }
        .padding(.bottom, 8)
        .conditionalModifier(vm.notchState == .open) { view in
            view.onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], delegate: GeneralDropTargetDelegate(isTargeted: $vm.generalDropTargeting))
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
                    edgeInset: FaceIDOverlayGeometry.minimalContentEdgeInset + (notchStyle == .dynamicIsland ? 0 : topCornerRadius),
                    lockIconSize: notchStyle == .dynamicIsland ? FaceIDOverlayGeometry.minimalLockIconSize : FaceIDOverlayGeometry.minimalNotchLockIconSize,
                    mediaWidth: notchStyle == .dynamicIsland ? FaceIDOverlayGeometry.minimalMediaWidth : FaceIDOverlayGeometry.minimalNotchMediaWidth,
                    mediaVerticalInset: notchStyle == .dynamicIsland ? FaceIDOverlayGeometry.minimalMediaVerticalInset : FaceIDOverlayGeometry.minimalNotchMediaVerticalInset,
                    pulseScale: 1.0,
                    pulseOpacity: 1.0
                )
            } else {
                FaceIDScanAnimationView(media: controller.media)
                    .padding(.leading, (notchStyle == .dynamicIsland) ? FaceIDOverlayGeometry.pillContentPaddingLeading : FaceIDOverlayGeometry.notchContentPaddingLeading)
                    .padding(.trailing, (notchStyle == .dynamicIsland) ? FaceIDOverlayGeometry.pillContentPaddingTrailing : FaceIDOverlayGeometry.notchContentPaddingTrailing)
                    .padding(.top, (notchStyle == .dynamicIsland) ? FaceIDOverlayGeometry.pillContentPaddingTop : FaceIDOverlayGeometry.notchContentPaddingTop)
                    .padding(.bottom, (notchStyle == .dynamicIsland) ? FaceIDOverlayGeometry.pillContentPaddingBottom : FaceIDOverlayGeometry.notchContentPaddingBottom)
            }
        }
        .frame(width: targetFaceIDSize.width, height: targetFaceIDSize.height)
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
                .padding(.leading, 11)

            Rectangle()
                .fill(.black)
                .overlay(
                    HStack(alignment: .top) {
                        if coordinator.expandingView.show
                            && coordinator.expandingView.type == .music
                        {
                            MarqueeText(
                                .constant(musicManager.songTitle),
                                textColor: Defaults[.coloredSpectrogram]
                                    ? Color(nsColor: musicManager.avgColor) : Color.gray,
                                minDuration: 0.4,
                                frameWidth: 100
                            )
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
                        : (vm.closedNotchSize.width + (isDynamicIsland ? 8 : 12))
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
                        .mask {
                            AudioSpectrumView(isPlaying: $musicManager.isPlaying)
                                .frame(width: 16, height: 12)
                        }
                } else {
                    LottieAnimationContainer()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(.trailing, 10)
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

    /// `enforcePhysicalRect` is for hover-driven opens only: a hover-ENTER can be
    /// delivered while the closed silhouette is still mid-shrink (or while it is the
    /// wide music chin), so the cursor may be far outside the physical notch. Click
    /// and swipe opens deliberately skip the gate — tapping the visible black shape
    /// should open it regardless of how wide the chin currently is.
    private func doOpen(enforcePhysicalRect: Bool = false) {
        if enforcePhysicalRect && vm.notchState == .closed && !isMousePhysicallyInsideNotch() {
            return
        }
        vm.open(fromWidth: currentNotchWidth)
        // Post-open housekeeping runs AFTER the open spring settles (~420ms), not at
        // +120ms mid-flight: the pasteboard IPC and media fetch used to land on the
        // main thread during the animation — exactly the work the inline HUD never
        // has, which is why the HUD's expansion feels smoother. Same standard: zero
        // main-thread work inside the animation window.
        Task(priority: .utility) {
            try? await Task.sleep(for: .milliseconds(500))
            ClipboardManager.shared.checkImmediately()
        }
    }

    private func shouldHandleFaceIDHover(hovering: Bool) -> Bool {
        if NotchPulseLockMonitor.isScreenActuallyLocked() && faceIDOverlay.isArmed {
            return true
        }
        guard isFaceIDActive else { return false }
        if faceIDOverlay.phase == .collapsing {
            return false
        }
        return true
    }

    private func shouldHandleFaceIDTap() -> Bool {
        if NotchPulseLockMonitor.isScreenActuallyLocked() && faceIDOverlay.isArmed {
            return true
        }
        guard isFaceIDActive else { return false }
        return true
    }

    private func isMousePhysicallyInsideNotch() -> Bool {
        let mouseLoc = NSEvent.mouseLocation
        guard let screen = currentScreen else { return false }
        let screenFrame = screen.frame
        let isDynamicIsland = notchStyle == .dynamicIsland
        let topOffset = (isDynamicIsland && screen.safeAreaInsets.top == 0) ? dynamicIslandTopOffset : 0
        
        let pad = Defaults[.extendHoverArea] ? CGFloat(Defaults[.hoverAreaPadding]) : 6.0
        // BUGFIX: use the PHYSICAL notch dimensions when closed. currentNotchWidth is
        // the live chin width, which balloons to 260-460px while music is playing —
        // the imagined hover rect then covered twice the visible notch and the
        // auto-close path silently refused to fire ("cursor left the notch but it
        // never closes").
        let baseWidth = vm.notchState == .open ? currentNotchWidth : vm.closedNotchSize.width
        let baseHeight = vm.notchState == .open ? currentNotchHeight : vm.closedNotchSize.height
        let width = baseWidth + (pad * 2.0)
        let height = baseHeight + pad + topOffset
        
        let notchRect = CGRect(
            x: screenFrame.midX - (width / 2.0),
            y: screenFrame.maxY - height,
            width: width,
            height: height
        )
        return notchRect.contains(mouseLoc)
    }

    /// Independent cursor-presence watchdog: opens the notch whenever the cursor is
    /// physically inside the notch rect while closed, WITHOUT needing an onHover(enter)
    /// event. Covers the dead-hover failure mode where SwiftUI silently stops
    /// delivering enter events after the closed silhouette reshapes (music chin
    /// grows/shrinks, HUD shows/hides) — the event-gated poll in handleHover never
    /// starts in that state, and hover-to-open feels broken. Dwell and pressed-button
    /// rules match the event-gated path exactly, and both paths funnel through
    /// openFromHoverIfPhysicallyInside so whichever fires first wins.
    private func startHoverPresencePoll() {
        hoverPresenceTask?.cancel()
        hoverPresenceTask = Task {
            // Re-check every 110ms, forever. The check itself is trivial (one
            // NSEvent.mouseLocation + rect math), so the steady-state cost is nil.
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(110))
                guard !Task.isCancelled else { return }
                if vm.notchState == .closed {
                    openFromHoverIfPhysicallyInside()
                } else {
                    // Drop any armed dwell countdown — it belongs to the entry that
                    // already ended (event path opened first, notch was dismissed by
                    // click, …). Keeping it would let the NEXT entry open instantly
                    // with no dwell.
                    hoverDwellDeadline = nil
                    if vm.notchState == .open {
                        // Enter events dying usually means exit events die too — without
                        // this, a presence-opened notch would never close on mouse-leave.
                        closeFromHoverIfCursorLeft()
                    }
                }
            }
        }
    }

    /// Shared hover-open entry: opens from hover only when every hover-open rule
    /// passes. Both the event-gated poll (handleHover) and the presence watchdog
    /// call this, so duplicates are impossible — the first caller flips
    /// vm.notchState to .open and every later call no-ops on the guard.
    private func openFromHoverIfPhysicallyInside() {
        guard vm.notchState == .closed,
              !isFaceIDActive, faceIDOverlay.phase == .closed,
              !NotchPulseLockMonitor.isScreenActuallyLocked(),
              !vm.hideOnClosed,
              !coordinator.sneakPeek.show,
              Defaults[.openNotchOnHover],
              NSEvent.pressedMouseButtons == 0,
              isMousePhysicallyInsideNotch() else {
            hoverDwellDeadline = nil
            return
        }

        let dwell = Defaults[.minimumHoverDuration]
        guard dwell > 0 else {
            hoverDwellDeadline = nil
            doOpen(enforcePhysicalRect: true)
            return
        }

        // Dwell armed on first detection, re-armed whenever the cursor leaves
        // (the guard above clears the deadline). The presence poll re-calls this
        // every 110ms, so the countdown advances in 110ms quanta — indistinguishable
        // from a timer at these dwell lengths and immune to task bookkeeping.
        let now = ContinuousClock.now
        guard let deadline = hoverDwellDeadline else {
            hoverDwellDeadline = now + .seconds(dwell)
            return
        }
        if now >= deadline {
            hoverDwellDeadline = nil
            // Match the event path: the auto-close guards elsewhere in this view
            // (sneak-peek dismissal, gesture end) only spare the notch while
            // isHovering is true, and the shadow depends on it too.
            isHovering = true
            if Defaults[.enableHaptics] { haptics.toggle() }
            doOpen(enforcePhysicalRect: true)
        }
    }

    /// Presence-watchdog close: mirrors the exit branch of handleHover for the case
    /// where exit events never fire. Same guards, same close targets.
    private func closeFromHoverIfCursorLeft() {
        guard !isFaceIDActive, faceIDOverlay.phase == .closed,
              !NotchPulseLockMonitor.isScreenActuallyLocked(),
              !vm.hideOnClosed,
              NSEvent.pressedMouseButtons == 0,
              !isMousePhysicallyInsideNotch(),
              !(Defaults[.extendHoverArea] && vm.isHoveringFromRadar) else { return }

        if !vm.isBatteryPopoverActive, !SharingStateManager.shared.preventNotchClose,
           !ShelfStateViewModel.shared.isPinned, !CalendarStateViewModel.shared.isPinned,
           !vm.dragDetectorTargeting, !vm.anyDropZoneTargeting {
            isHovering = false
            vm.close(targetClosedWidth: baseChinWidth)
        }
    }

    /// Single source of truth for hover: the PHYSICAL cursor position.
    /// Enter only opens when the cursor is inside the real notch rect (never the wide
    /// music chin — rapid passes over the live activity used to open the notch without
    /// touching it); exit closes only when the cursor has really left it.
    private func handleHover(_ hovering: Bool) {
        guard !isFaceIDActive, faceIDOverlay.phase == .closed,
              !NotchPulseLockMonitor.isScreenActuallyLocked(),
              !vm.hideOnClosed else { return }
        hoverTask?.cancel()

        if hovering {
            guard vm.notchState == .closed,
                  !coordinator.sneakPeek.show,
                  Defaults[.openNotchOnHover],
                  NSEvent.pressedMouseButtons == 0 else { return }

            isHovering = true
            if Defaults[.enableHaptics] { haptics.toggle() }

            hoverTask = Task {
                // SwiftUI fires onHover(enter) EXACTLY ONCE — at the boundary of the
                // current closed silhouette. When music is playing that silhouette is
                // the wide live-activity chin (hundreds of px wider than the physical
                // notch), so the single enter event lands far from the notch and the
                // physical-rect gate rejects it; no further event fires while the
                // cursor keeps moving inward, and hover-to-open went dead whenever
                // music (or any wide HUD) was showing. While the cursor sits on the
                // closed silhouette, POLL for it actually reaching the physical notch
                // rect and open the moment it does — same pattern as the FaceID
                // armed-lock-screen poll. Leaving the silhouette fires exit, which
                // cancels this loop via the hoverTask?.cancel() above.
                let dwell = Defaults[.minimumHoverDuration]
                let deadline = ContinuousClock.now + .seconds(max(2.0, dwell + 1.0))
                while !Task.isCancelled,
                      vm.notchState == .closed,
                      !coordinator.sneakPeek.show,
                      NSEvent.pressedMouseButtons == 0,
                      ContinuousClock.now < deadline {
                    if isMousePhysicallyInsideNotch() {
                        if dwell > 0 { try? await Task.sleep(for: .seconds(dwell)) }
                        guard !Task.isCancelled,
                              isMousePhysicallyInsideNotch(),
                              vm.notchState == .closed,
                              NSEvent.pressedMouseButtons == 0 else { return }
                        doOpen(enforcePhysicalRect: true)
                        return
                    }
                    try? await Task.sleep(for: .milliseconds(90))
                }
            }
        } else {
            guard vm.notchState == .open else {
                isHovering = false
                return
            }
            hoverTask = Task {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled,
                      !isMousePhysicallyInsideNotch(),
                      !(Defaults[.extendHoverArea] && vm.isHoveringFromRadar),
                      NSEvent.pressedMouseButtons == 0 else { return }

                isHovering = false
                if !vm.isBatteryPopoverActive, !SharingStateManager.shared.preventNotchClose,
                   !ShelfStateViewModel.shared.isPinned, !CalendarStateViewModel.shared.isPinned,
                   !vm.dragDetectorTargeting, !vm.anyDropZoneTargeting {
                    vm.close(targetClosedWidth: baseChinWidth)
                }
            }
        }
    }

    private func handleScreenLock() {
        hoverTask?.cancel()
        isHovering = false
        gestureProgress = .zero
        SharingStateManager.shared.preventNotchClose = false
        ShelfStateViewModel.shared.isPinned = false
        CalendarStateViewModel.shared.isPinned = false
        vm.close(force: true)
    }

    // MARK: - Gesture Handling

    private func handleDownGesture(translation: CGFloat, phase: NSEvent.Phase) {
        guard !NotchPulseLockMonitor.isScreenActuallyLocked() else { return }
        guard vm.notchState == .closed else { return }

        if phase == .ended {
            withAnimation(animationSpring) { gestureProgress = .zero }
            return
        }

        withAnimation(animationSpring) {
            gestureProgress = (translation / Defaults[.gestureSensitivity]) * 20
        }

        if translation > Defaults[.gestureSensitivity] {
            if Defaults[.enableHaptics] {
                haptics.toggle()
            }
            withAnimation(animationSpring) {
                gestureProgress = .zero
            }
            doOpen()
        }
    }

    private func handleUpGesture(translation: CGFloat, phase: NSEvent.Phase) {
        guard vm.notchState == .open && !vm.isHoveringCalendar else { return }

        // If in Clipboard view (or hovering over Clipboard), do NOT close the notch unless user has scrolled all the way to the last copied item
        if (coordinator.currentView == .clipboard || vm.isHoveringClipboard) && !vm.clipboardScrolledToBottom {
            if gestureProgress != .zero {
                withAnimation(animationSpring) {
                    gestureProgress = .zero
                }
            }
            return
        }

        withAnimation(animationSpring) {
            gestureProgress = (translation / Defaults[.gestureSensitivity]) * -20
        }

        if phase == .ended {
            withAnimation(animationSpring) {
                gestureProgress = .zero
            }
        }

        if translation > Defaults[.gestureSensitivity] {
            withAnimation(animationSpring) {
                isHovering = false
            }
            if !SharingStateManager.shared.preventNotchClose { 
                gestureProgress = .zero
                vm.close(targetClosedWidth: baseChinWidth)
            }

            if Defaults[.enableHaptics] {
                haptics.toggle()
            }
        }
    }
}

class FullScreenDropDelegate: DropDelegate {
    @Binding var isTargeted: Bool
    let onDrop: () -> Void

    init(isTargeted: Binding<Bool>, onDrop: @escaping () -> Void) {
        self._isTargeted = isTargeted
        self.onDrop = onDrop
    }

    func dropEntered(info: DropInfo) {
        isTargeted = true
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
    }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        onDrop()
        return true
    }

}

class GeneralDropTargetDelegate: DropDelegate {
    @Binding var isTargeted: Bool

    init(isTargeted: Binding<Bool>) {
        self._isTargeted = isTargeted
    }

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
        let providers = info.itemProviders(for: [
            UTType.fileURL.identifier,
            UTType.url.identifier,
            UTType.utf8PlainText.identifier,
            UTType.plainText.identifier,
            UTType.data.identifier
        ])
        if !providers.isEmpty {
            ShelfStateViewModel.shared.load(providers)
            return true
        }
        return true
    }
}

#Preview {
    let vm = NotchPulseViewModel()
    vm.open()
    return ContentView()
        .environmentObject(vm)
        .frame(width: vm.notchSize.width, height: vm.notchSize.height)
}
