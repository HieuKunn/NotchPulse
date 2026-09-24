//
//  FaceIDOverlayGeometry.swift
//  NotchPulse
//
//  Pure geometry — no AppKit window knowledge.
//

import AppKit
import CoreGraphics
import Defaults
import SwiftUI

struct FaceIDOverlayGeometry {
    /// Shared interactive spring matching Glance NotchGeometry springs
    static let springAnimation = Animation.spring(response: openSpringResponse, dampingFraction: openSpringDamping, blendDuration: 0)
    static let closeSpringAnimation = Animation.spring(response: closeSpringResponse, dampingFraction: closeSpringDamping, blendDuration: 0)

    /// Physical notch's own dimensions, or `pillClosedSize`.
    let closedSize: CGSize
    /// True if this screen has a real physical notch (vs. the pill fallback).
    let isPhysicalNotch: Bool

    /// Synchronized with NotchPulse's active style preference.
    var style: FaceIDOverlayPanelStyle {
        Defaults[.notchStyle] == .dynamicIsland ? .pill : .notch
    }

    /// Calibrated to match Apple's physical hardware notch width (185pt body + flares)
    static let notchOpenSize = CGSize(width: 216, height: 185)

    /// Corner radii matching Glance & Apple notch curvature.
    static let closedTopRadius: CGFloat = 8
    static let closedBottomRadius: CGFloat = 12
    static let openTopRadius: CGFloat = 16
    static let openBottomRadius: CGFloat = 54

    /// A shape drawn in a rect of width `w` has a visible body of `w - 2 * topRadius`;
    /// zero in pill style, which has no flare.
    static func flareAllowance(topRadius: CGFloat, style: FaceIDOverlayPanelStyle) -> CGFloat {
        style == .notch ? topRadius * 2 : 0
    }

    // MARK: - Pill style (Dynamic Island)

    /// Resting capsule size matching Glance pill closed size
    static let pillClosedSize = CGSize(width: 80, height: 24)

    /// Expanded footprint matching Apple's physical notch width (185pt)
    static let pillOpenSize = CGSize(width: 185, height: 175)

    /// Pinned to NotchPulse's active dynamic island top offset.
    static var pillTopGap: CGFloat { Defaults[.dynamicIslandTopOffset] }

    /// Continuous corner radius matching Apple notch curvature.
    static let pillOpenCornerRadius: CGFloat = 44

    /// Blur applied to the whole panel while off-screen, resolving to zero as it slides into place.
    static let pillEnterBlur: CGFloat = 0

    /// Comfortably more than `pillEnterBlur` — a Gaussian blur spreads past its nominal
    /// radius, and without this margin the parked pill smears a faint band at the screen top.
    static let pillOffscreenSlack: CGFloat = 20

    /// Pill's equivalent of `notchContentPadding*` calibrated to physical notch proportion.
    static let pillContentPaddingTop: CGFloat = 28
    static let pillContentPaddingLeading: CGFloat = 28
    static let pillContentPaddingTrailing: CGFloat = 28
    static let pillContentPaddingBottom: CGFloat = 28

    // MARK: - Panel open/close springs matching Glance
    //
    // Shared by both styles. Opening overshoots slightly; closing is critically damped.
    static let openSpringResponse: Double = 0.45
    static let openSpringDamping: Double = 0.7
    static let closeSpringResponse: Double = 0.45
    static let closeSpringDamping: Double = 1.0

    // MARK: - Pill enter/exit choreography
    //
    // Style `.pill` only. Slide and expansion run on independent timelines:
    // enter slides first then grows; exit shrinks first then slides away.

    /// Ease-out rather than a spring — a straight-line move, not a bouncy resize.
    static let pillSlideDuration: Double = 0.25
    /// Expansion starts this long after the slide begins.
    static let pillEnterExpansionDelay: Double = 0.16
    /// Slide starts this long after the shrink begins.
    static let pillExitSlideDelay: Double = 0.18

    // MARK: - Minimal unlock style (Inline FaceID)
    //
    // `UnlockAnimationStyle.minimal`: the silhouette widens horizontally only,
    // revealing a lock icon on one side and the unlock icon/video on the other,
    // without expanding vertically downwards.

    /// Total notch body width is `geometry.closedSize.width + 2 * this`.
    static let minimalNotchFlankWidth: CGFloat = 68

    /// Pill dimensions: wide enough so lock glyph and face animation are well-spaced,
    /// with height matching standard closed island height (no downward expansion).
    static let minimalPillOpenWidth: CGFloat = 220
    static let minimalPillOpenHeight: CGFloat = 32

    /// Zero extra height — strictly inline, widening sideways only.
    static let minimalNotchHeightBump: CGFloat = 0

    /// Radii matching closed silhouette
    static let minimalNotchTopRadius: CGFloat = 10
    static let minimalNotchBottomRadius: CGFloat = 16

    /// In notch style the flare already occupies `topRadius` of this margin.
    static let minimalContentEdgeInset: CGFloat = 8

    /// Point size of the lock glyph, pill style (and the shared fallback).
    static let minimalLockIconSize: CGFloat = 14
    /// The icon/video is square and fits comfortably inside inline height without vertical overflow.
    static let minimalMediaWidth: CGFloat = 22
    /// Vertical inset so the media aligns nicely without overflowing the capsule.
    static let minimalMediaVerticalInset: CGFloat = 0

    /// Notch-style counterparts matching inline height.
    static let minimalNotchLockIconSize: CGFloat = 15
    static let minimalNotchMediaWidth: CGFloat = 22
    static let minimalNotchMediaVerticalInset: CGFloat = 0

    /// So the lock glyph can be nudged to land with the video's own resolve beat.
    static let minimalLockUnlockDelay: Double = 0
    static let minimalLockAnimationDuration: Double = 0.4

    // MARK: - Scan "breathing" pulse matching Glance
    //
    // While `.scanning`, content ping-pongs between full size/opacity and
    // `scanPulseScale`/`scanPulseOpacity` so the panel reads as searching, not frozen.
    // See `FaceIDOverlayView.startScanPulse()`.

    /// Scale at the dimmed end of the ping-pong. 1.0 disables the size part.
    static let scanPulseScale: CGFloat = 0.97
    /// Opacity at the dimmed end. 1.0 disables the fade part.
    static let scanPulseOpacity: Double = 0.65
    /// One half-cycle — full → dimmed, or dimmed → full.
    static let scanPulseHalfCycleDuration: Double = 0.4
    /// Pause at each end before reversing. 0 makes it a continuous breathe.
    static let scanPulseHoldDuration: Double = 0.05
    /// Deliberately quicker than a half-cycle so content is back at full while the
    /// success/failure animation is still early in its playback.
    static let scanPulseSettleDuration: Double = 0.2

    /// Wait before the first pulse cycle so breathing starts only once the panel has
    /// finished expanding. Hand-tuned approximation — springs have no hard end time.
    static let scanPulseStartDelay: Double = 0.6

    /// Notch-style padding around scan-mode content calibrated to physical notch proportion.
    static let notchContentPaddingTop: CGFloat = 24
    static let notchContentPaddingLeading: CGFloat = 34
    static let notchContentPaddingTrailing: CGFloat = 34
    static let notchContentPaddingBottom: CGFloat = 26

    /// Cosmetic size bump applied on hover in FaceIDOverlayView. Included here so the
    /// fixed window has margin for it instead of clipping.
    static let hoverBump: CGFloat = 6

    // MARK: - Window size, per style — EDIT HERE
    //
    // Created once and never resized afterward (see FaceIDOverlayWindow.swift). Each style is
    // floored to its own scan-mode footprint and gets its own shadow margin, tuned independently.

    /// Extra margin so SwiftUI's `.shadow()` isn't clipped (the window itself has
    /// `hasShadow = false` — the shadow is drawn in-content).
    static let notchShadowPadding: CGFloat = 24
    static let pillShadowPadding: CGFloat = 24

    static func windowSize(for style: FaceIDOverlayPanelStyle) -> CGSize {
        switch style {
        case .notch:
            let contentWidth = max(notchOpenSize.width, FaceIDMetrics.maxPanelWidth)
            let contentHeight = max(notchOpenSize.height, FaceIDMetrics.maxPanelHeight(for: .notch))
            return CGSize(
                width: contentWidth + notchShadowPadding * 2 + hoverBump,
                height: contentHeight + notchShadowPadding + hoverBump
            )
        case .pill:
            let contentWidth = max(pillOpenSize.width, FaceIDMetrics.maxPanelWidth)
            let contentHeight = max(pillOpenSize.height, FaceIDMetrics.maxPanelHeight(for: .pill))
            return CGSize(
                width: contentWidth + pillShadowPadding * 2 + hoverBump,
                // `pillTopGap` since the detached pill's panel is pushed down by that much.
                height: contentHeight + pillShadowPadding + hoverBump + pillTopGap
            )
        }
    }

    /// Floor for a physical notch's measured width — the auxiliary-area arithmetic
    /// below can come up implausibly small on odd display configurations.
    private static let minimumNotchWidth: CGFloat = 200

    @MainActor
    static func forMainScreen() -> FaceIDOverlayGeometry {
        guard let screen = preferredScreen() ?? NSScreen.main else {
            return FaceIDOverlayGeometry(closedSize: pillClosedSize, isPhysicalNotch: false)
        }
        return forScreen(screen)
    }

    @MainActor
    static func forScreen(_ screen: NSScreen) -> FaceIDOverlayGeometry {
        let isNotchStyle = Defaults[.notchStyle] == .notch
        let screenUUID = screen.displayUUID
        let isPhysical = screen.safeAreaInsets.top > 0 || screen.auxiliaryTopLeftArea != nil
        let closedSize = (isNotchStyle || isPhysical) ? getClosedNotchSize(screenUUID: screenUUID) : pillClosedSize

        return FaceIDOverlayGeometry(
            closedSize: closedSize,
            isPhysicalNotch: isPhysical
        )
    }

    /// Picks the screen the overlay should show on. Follows the camera device's physical
    /// display, falling back to NotchPulse's active display or physical notch display.
    @MainActor
    static func preferredScreen() -> NSScreen? {
        let activeDevice = NotchPulseCameraDeviceCatalog.resolvedDevice()
        if let camScreen = NotchPulseCameraDeviceCatalog.targetScreen(for: activeDevice) {
            return camScreen
        }
        if let prefUUID = NotchPulseViewCoordinator.shared.preferredScreenUUID,
           let screen = NSScreen.screen(withUUID: prefUUID) {
            return screen
        }
        let selectedUUID = NotchPulseViewCoordinator.shared.selectedScreenUUID
        if !selectedUUID.isEmpty, let screen = NSScreen.screen(withUUID: selectedUUID) {
            return screen
        }
        return NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }
}

extension NSScreen {
    /// Stable enough to persist a user's display choice across launches — the only
    /// per-display identity AppKit exposes.
    var stableDisplayID: String? {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return nil
        }
        return String(number)
    }

    /// True for the Mac's own display (vs. an external monitor) — used to pin the Face
    /// Unlock panel there while the built-in camera is selected.
    var isBuiltIn: Bool {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return false
        }
        return CGDisplayIsBuiltin(number) != 0
    }
}

typealias NotchGeometry = FaceIDOverlayGeometry
