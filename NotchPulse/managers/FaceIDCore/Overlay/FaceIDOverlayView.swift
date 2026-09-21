//
//  FaceIDOverlayView.swift
//  NotchPulse
//
//  SwiftUI root hosted inside the fixed-size FaceIDOverlayWindow — only content moves/resizes.
//  Two silhouettes per screen (see FaceIDOverlayPanelStyle): `.notch` sits on the physical
//  cutout; `.pill` is a detached island that slides on/off screen (and docks in place
//  on the lock screen instead of sliding).
//
//  Enter/exit choreography (pill only, see `scheduleChoreography()`) staggers slide vs.
//  expansion using real `Task.sleep` delays on separate `@State` mirrors, not two
//  `.animation(value:)` modifiers — those don't stagger reliably, since SwiftUI can't
//  cleanly split which properties belong to which modifier when both fire in one transaction.
//

import SwiftUI
import AppKit

/// The visible panel's current frame, relative to the fixed window's full
/// bounds — see the `.background(GeometryReader...)` in `body` and
/// `FaceIDOverlayWindowController.updateMousePassthrough()`.
private struct InteractivePanelFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect? = nil
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = nextValue() ?? value
    }
}

struct FaceIDOverlayView: View {
    let controller: FaceIDOverlayController

    @State private var isHovering = false

    /// Visual mirrors of the controller's target state — see the file header for why
    /// these are separate `@State` rather than computed directly.
    @State private var visualIsExpanded = false
    @State private var visualIsPositioned = false
    /// The in-flight trailing half of an enter/exit choreography, if any.
    @State private var choreographyTask: Task<Void, Never>?

    /// Mirrors "phase is `.success`", not the phase itself, so the flip can be delayed
    /// (`minimalLockUnlockDelay`) and held open across the collapse.
    @State private var isMinimalLockOpen = false
    /// The pending delayed unlock, if any.
    @State private var lockUnlockTask: Task<Void, Never>?

    /// Only ever mutated inside an explicit `withAnimation`, so it never jumps.
    @State private var isScanPulseDimmed = false
    /// The running ping-pong loop while `.scanning`, if any.
    @State private var scanPulseTask: Task<Void, Never>?

    private var style: FaceIDOverlayPanelStyle {
        controller.geometry.style
    }

    /// `scheduleChoreography()` compares this against `visualIsExpanded` to decide what needs to move.
    private var targetIsExpanded: Bool {
        switch controller.phase {
        case .closed, .collapsing: return false
        case .scanning, .success, .failure, .onboarding: return true
        }
    }

    /// Notch style is always positioned (the physical notch never travels). Expanded
    /// always implies positioned regardless of the docked flag, so a mid-success
    /// `disarm()` (which undocks) doesn't yank the panel away mid-animation.
    private var targetIsPositioned: Bool {
        if targetIsExpanded { return true }
        if style == .notch { return true }
        return controller.isPillDocked
    }

    /// While onboarding is active, the panel body tracks its step size instead of the
    /// fixed scan-mode footprint — this is what makes the panel grow/shrink per step.
    private var onboardingController: FaceIDEnrollmentController? {
        if case .onboarding(let controller) = controller.content { return controller }
        return nil
    }

    /// Onboarding always uses the full panel, and `.none` keeps the full expansion too
    /// (it only drops the video) — so this is specifically `.minimal` scan content.
    private var isMinimalScan: Bool {
        onboardingController == nil && controller.activeUnlockStyle == .minimal
    }

    private var scanOpenSize: CGSize {
        style == .notch ? FaceIDOverlayGeometry.notchOpenSize : FaceIDOverlayGeometry.pillOpenSize
    }

    /// In notch style the width grows to add flanking black beside the physical cutout;
    /// the height grows since the cutout itself can't, so the bump appears below it.
    private var minimalOpenBodySize: CGSize {
        switch style {
        case .notch:
            return CGSize(
                width: closedBodySize.width + FaceIDOverlayGeometry.minimalNotchFlankWidth * 2,
                height: closedBodySize.height + FaceIDOverlayGeometry.minimalNotchHeightBump
            )
        case .pill:
            return CGSize(
                width: FaceIDOverlayGeometry.minimalPillOpenWidth,
                height: FaceIDOverlayGeometry.minimalPillOpenHeight
            )
        }
    }

    private var openBodySize: CGSize {
        if let onboardingController { return onboardingController.panelSize }
        return isMinimalScan ? minimalOpenBodySize : scanOpenSize
    }

    private var closedBodySize: CGSize {
        controller.geometry.closedSize
    }

    private var topRadius: CGFloat {
        if visualIsExpanded {
            if isMinimalScan {
                // Pill stays a true capsule as it stretches — radius tracks the animating height.
                return style == .notch
                    ? FaceIDOverlayGeometry.minimalNotchTopRadius
                    : minimalOpenBodySize.height / 2
            }
            return style == .notch ? FaceIDOverlayGeometry.openTopRadius : FaceIDOverlayGeometry.pillOpenCornerRadius
        }
        // Half the height is exactly a capsule end, in pill style.
        return style == .notch ? FaceIDOverlayGeometry.closedTopRadius : closedBodySize.height / 2
    }

    private var bottomRadius: CGFloat {
        if visualIsExpanded {
            if isMinimalScan {
                return style == .notch
                    ? FaceIDOverlayGeometry.minimalNotchBottomRadius
                    : minimalOpenBodySize.height / 2
            }
            guard style == .notch else {
                // Uniform corners in pill style — no flare to balance, unlike the notch.
                return FaceIDOverlayGeometry.pillOpenCornerRadius
            }
            return onboardingController?.panelBottomRadius ?? FaceIDOverlayGeometry.openBottomRadius
        }
        return style == .notch ? FaceIDOverlayGeometry.closedBottomRadius : closedBodySize.height / 2
    }

    /// Widened by `flareAllowance` in notch style so the closed state lands exactly on
    /// the physical notch width instead of coming up short by the flare.
    private var currentSize: CGSize {
        let body = visualIsExpanded ? openBodySize : closedBodySize
        let bump: CGFloat = isHovering ? FaceIDOverlayGeometry.hoverBump : 0
        return CGSize(
            width: body.width + FaceIDOverlayGeometry.flareAllowance(topRadius: topRadius, style: style) + bump,
            height: body.height + bump
        )
    }

    /// Top-aligned inside the fixed window frame, so sliding is purely a matter of
    /// where the top edge sits.
    private var verticalOffset: CGFloat {
        guard style == .pill else { return 0 }
        return FaceIDOverlayGeometry.pillTopGap
    }

    private var panelBlur: CGFloat {
        0
    }

    private var scanContentPaddingTop: CGFloat {
        style == .pill ? FaceIDOverlayGeometry.pillContentPaddingTop : FaceIDOverlayGeometry.notchContentPaddingTop
    }

    private var scanContentPaddingLeading: CGFloat {
        style == .pill ? FaceIDOverlayGeometry.pillContentPaddingLeading : FaceIDOverlayGeometry.notchContentPaddingLeading
    }

    private var scanContentPaddingTrailing: CGFloat {
        style == .pill ? FaceIDOverlayGeometry.pillContentPaddingTrailing : FaceIDOverlayGeometry.notchContentPaddingTrailing
    }

    private var scanContentPaddingBottom: CGFloat {
        style == .pill ? FaceIDOverlayGeometry.pillContentPaddingBottom : FaceIDOverlayGeometry.notchContentPaddingBottom
    }

    /// Direction-only — any enter-side delay is a real `Task.sleep` before this is
    /// applied (see `scheduleChoreography()`), not baked into the curve.
    private func expansionAnimation(entering: Bool) -> Animation {
        entering
            ? .spring(response: FaceIDOverlayGeometry.openSpringResponse, dampingFraction: FaceIDOverlayGeometry.openSpringDamping)
            : .spring(response: FaceIDOverlayGeometry.closeSpringResponse, dampingFraction: FaceIDOverlayGeometry.closeSpringDamping)
    }

    /// A straight-line off-screen/on-screen move, not a bouncy resize.
    private var slideAnimation: Animation {
        .easeOut(duration: FaceIDOverlayGeometry.pillSlideDuration)
    }

    // MARK: - Scan pulse

    /// Success and failure both leave `.scanning`, ending the pulse so the resolve
    /// animation plays against steady content.
    private var isScanning: Bool {
        controller.phase == .scanning
    }

    private var scanPulseScale: CGFloat {
        isScanPulseDimmed ? FaceIDOverlayGeometry.scanPulseScale : 1
    }

    private var scanPulseOpacity: Double {
        isScanPulseDimmed ? FaceIDOverlayGeometry.scanPulseOpacity : 1
    }

    /// The breathing pulse is applied to the video only, never the lock icon or the
    /// whole panel — hence passing it into `FaceIDMinimalUnlockView` rather than wrapping `Group`.
    @ViewBuilder
    private var scanContent: some View {
        if isMinimalScan {
            FaceIDMinimalUnlockView(
                media: controller.media,
                isUnlocked: isMinimalLockOpen,
                // The notch's flare eats `topRadius` before any real black starts.
                edgeInset: FaceIDOverlayGeometry.minimalContentEdgeInset
                    + (style == .notch ? topRadius : 0),
                lockIconSize: style == .notch
                    ? FaceIDOverlayGeometry.minimalNotchLockIconSize : FaceIDOverlayGeometry.minimalLockIconSize,
                mediaWidth: style == .notch
                    ? FaceIDOverlayGeometry.minimalNotchMediaWidth : FaceIDOverlayGeometry.minimalMediaWidth,
                mediaVerticalInset: style == .notch
                    ? FaceIDOverlayGeometry.minimalNotchMediaVerticalInset
                    : FaceIDOverlayGeometry.minimalMediaVerticalInset,
                pulseScale: scanPulseScale,
                pulseOpacity: scanPulseOpacity
            )
        } else {
            FaceIDScanAnimationView(media: controller.media)
                .padding(.leading, scanContentPaddingLeading)
                .padding(.trailing, scanContentPaddingTrailing)
                .padding(.top, scanContentPaddingTop)
                .padding(.bottom, scanContentPaddingBottom)
                .scaleEffect(isScanning ? (0.80 * scanPulseScale) : 0.80)
                .opacity(isScanning ? scanPulseOpacity : 1.0)
        }
    }

    var body: some View {
        ZStack {
            Group {
                if let onboardingController {
                    // Onboarding's step views fill `panelSize` themselves — no shared padding here.
                    FaceIDOnboardingNotchView(controller: onboardingController)
                } else {
                    scanContent
                }
            }
            // Content dissolves (blur + fade) as the panel shrinks, rather than being
            // abruptly clipped by the collapsing shape. Rides the animation already
            // active on `visualIsExpanded` — no separate `.animation` needed.
            .blur(radius: visualIsExpanded ? 0 : 40)
            .opacity(visualIsExpanded ? 1 : 0)
            .scaleEffect(visualIsExpanded ? 1 : 0.3)
            .environment(\.notchPanelStyle, style)
        }
        .frame(width: currentSize.width, height: currentSize.height)
        .background(Color.black)
        .clipShape(FaceIDOverlayShape(topRadius: topRadius, bottomRadius: bottomRadius, style: style))
        .overlay {
            if style == .pill {
                RoundedRectangle(cornerRadius: bottomRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.8)
            }
        }
        .overlay(alignment: .top) {
            if style == .notch {
                Rectangle()
                    .fill(.black)
                    .frame(height: 1)
                    .padding(.horizontal, topRadius)
            }
        }
        // Reports this panel's own current frame, relative to the fixed
        // window's full bounds (`Self.interactiveCoordinateSpace`, declared
        // below on the outermost frame) — restricts the window's click
        // capture to the shape actually on screen instead of its whole
        // fixed max-envelope frame. See `FaceIDOverlayWindowController.updateMousePassthrough()`.
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: InteractivePanelFramePreferenceKey.self,
                    value: proxy.frame(in: .named(Self.interactiveCoordinateSpace))
                )
            }
        )
        // Shadow only while expanded — matching NotchPulse's shadow profile.
        .shadow(
            color: .black.opacity(visualIsExpanded ? (isHovering ? 0.65 : 0.5) : 0),
            radius: style == .pill ? (visualIsExpanded ? 14 : 8) : 6,
            x: 0,
            y: style == .pill ? 4 : 0
        )
        // Drives the per-step resize while onboarding is active — `visualIsExpanded`
        // alone only fires on entering/leaving the expanded state.
        .animation(expansionAnimation(entering: true), value: onboardingController?.panelSize)
        .blur(radius: panelBlur)
        // Applied after the shadow so both travel together, before `.onHover`.
        .offset(y: verticalOffset)
        .animation(.easeOut(duration: 0.18), value: isHovering)
        .contentShape(FaceIDOverlayShape(topRadius: topRadius, bottomRadius: bottomRadius, style: style))
        .onHover { hovering in
            isHovering = hovering
            controller.setHovering(hovering)
            if hovering {
                performHapticFeedback(.generic)
                controller.activate()
            }
        }
        .onTapGesture {
            controller.activate()
        }
        .onAppear {
            // Sync without animating — nothing to animate from on first appearance.
            visualIsExpanded = targetIsExpanded
            visualIsPositioned = targetIsPositioned
            updateScanPulse()
            updateMinimalLock()
        }
        .onDisappear {
            scanPulseTask?.cancel()
            scanPulseTask = nil
            lockUnlockTask?.cancel()
            lockUnlockTask = nil
        }
        .onChange(of: controller.phase) { _, newPhase in
            scheduleChoreography()
            updateScanPulse()
            updateMinimalLock()
            if newPhase == .success {
                performHapticFeedback(.levelChange)
            }
        }
        .onChange(of: controller.isPillDocked) { _, _ in scheduleChoreography() }
        .frame(
            width: FaceIDOverlayGeometry.windowSize(for: style).width,
            height: FaceIDOverlayGeometry.windowSize(for: style).height,
            alignment: .top
        )
        // Anchored on this outermost, full-window-sized frame so the panel's
        // reported frame above is directly comparable to the hosting view's
        // own bounds — see `FaceIDOverlayWindowController.updateMousePassthrough()`.
        .coordinateSpace(name: Self.interactiveCoordinateSpace)
        .onPreferenceChange(InteractivePanelFramePreferenceKey.self) { rect in
            Task { @MainActor in
                controller.updateInteractiveContentRect(rect)
            }
        }
    }

    private static let interactiveCoordinateSpace = "NotchOverlayRoot"

    private func scheduleChoreography() {
        let wantExpanded = targetIsExpanded
        choreographyTask?.cancel()
        choreographyTask = nil

        guard wantExpanded != visualIsExpanded else { return }

        withAnimation(expansionAnimation(entering: wantExpanded)) {
            visualIsExpanded = wantExpanded
            visualIsPositioned = true
        }
    }

    // MARK: - Haptics

    /// `defaultPerformer` isn't tied to this view/window, so this is safe to call even
    /// while this panel isn't key (hover on the lock screen never makes it key).
    private func performHapticFeedback(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        guard NotchPulseFaceIDSettings.shared.hapticFeedbackEnabled else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .default)
    }

    // MARK: - Scan pulse

    private func updateScanPulse() {
        if isScanning {
            startScanPulse()
        } else {
            stopScanPulse()
        }
    }

    // MARK: - Minimal lock glyph

    /// The animation lives on the glyph itself, so setting the state plainly here is
    /// already animated.
    private func updateMinimalLock() {
        let shouldOpen: Bool
        switch controller.phase {
        case .success:
            shouldOpen = true
        case .collapsing:
            // Hold whatever it currently is — re-locking now would read as undoing the unlock.
            return
        case .closed, .scanning, .failure, .onboarding:
            shouldOpen = false
        }

        lockUnlockTask?.cancel()
        lockUnlockTask = nil
        guard shouldOpen != isMinimalLockOpen else { return }

        // Only the unlock is delayable; re-locking happens while invisible anyway.
        let delay = FaceIDOverlayGeometry.minimalLockUnlockDelay
        guard shouldOpen, delay > 0 else {
            isMinimalLockOpen = shouldOpen
            return
        }
        lockUnlockTask = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self.isMinimalLockOpen = true
        }
    }

    /// Each half-cycle is its own finite `withAnimation` rather than one
    /// `.repeatForever(autoreverses:)` — a repeatForever owns the property for its
    /// whole lifetime and snaps on removal, whereas discrete half-cycles let
    /// `stopScanPulse()` retarget mid-flight and interpolate from the rendered value.
    private func startScanPulse() {
        // Already breathing (or waiting to start) — don't stack a second loop on top.
        guard scanPulseTask == nil else { return }

        // Pill doesn't start expanding until `pillEnterExpansionDelay` elapses, so
        // that's added on top here too.
        let entryDelay = (style == .pill ? FaceIDOverlayGeometry.pillEnterExpansionDelay : 0)
            + FaceIDOverlayGeometry.scanPulseStartDelay
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

    /// Retargets to `false` so SwiftUI animates from the current rendered value back to
    /// full without a jump; the guard leaves an already-settled/returning panel alone.
    private func stopScanPulse() {
        scanPulseTask?.cancel()
        scanPulseTask = nil
        isScanPulseDimmed = false
    }
}
