import SwiftUI

enum SettingsMetrics {
    static let windowSize = CGSize(width: 620, height: 650)
    /// No `outerCornerRadius` token — the window's outer corner is AppKit's
    /// own native mask (see WindowConfiguringView), not a hardcoded clip.
    ///
    /// Vertical strip at the top of the sidebar left empty for the window's
    /// real traffic lights, which AppKit draws over our content.
    static let trafficLightBandHeight: CGFloat = 52
    static let contentCornerRadius: CGFloat = 19
    static let sidebarWidth: CGFloat = 190

    /// Semantic system background adhering to Apple HIG declarative tokens.
    static let contentBackgroundColor = Color(nsColor: .windowBackgroundColor)

    /// Native sidebar background token.
    static let sidebarBackgroundColor = Color(nsColor: .windowBackgroundColor)

    /// Gap between the content panel and window edges.
    static let contentOuterSpacing: CGFloat = 8
    static let contentShadowColor = Color.clear
    static let contentShadowRadius: CGFloat = 0
    static let contentShadowFill = Color.clear

    /// Native hairline separator stroke around panels.
    static let contentStrokeColor = Color(nsColor: .separatorColor).opacity(0.3)

    static let selectedPillRadius: CGFloat = 10
    static let selectedPillColor = Color(nsColor: .quaternaryLabelColor)

    static let sidebarItemHeight: CGFloat = 36
    static let sidebarSectionSpacing: CGFloat = 8
    static let sidebarContentLeadingInset: CGFloat = 12
    static let sidebarContentTrailingInset: CGFloat = 2
    static let sidebarItemFont = Font.system(size: 13, weight: .regular)
    static let sectionHeaderFont = Font.system(size: 13, weight: .medium)
    static let contentTitleFont = Font.system(size: 15, weight: .medium)

    /// Dynamic semantic system typography colors automatically adapting across Light/Dark modes.
    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
    static let textTertiary = Color.secondary

    static let rowHeight: CGFloat = 44
    /// Standard continuous corner radius matching macOS System Settings grouped cards.
    static let rowRadius: CGFloat = 10
    static let rowColor = Color(nsColor: .controlBackgroundColor)
    static let rowBorder = Color(nsColor: .separatorColor).opacity(0.35)
    static let rowBorderWidth: CGFloat = 0.5
    static let rowFont = Font.system(size: 13, weight: .regular)
    static let rowSpacing: CGFloat = 12
    static let rowHorizontalInset: CGFloat = 14
    static let sliderRowVerticalPadding: CGFloat = 12

    /// Semantic button fills adhering to macOS Human Interface Guidelines.
    static let neutralButtonFill = Color(nsColor: .quaternaryLabelColor)
    static let destructiveFill = Color.red

    /// Centered empty/locked-state block (icon, caption, action button).
    static let emptyStateIconSize: CGFloat = 34
    static let emptyStateSpacing: CGFloat = 12
    static let emptyStateMinHeight: CGFloat = 110
    static let stateTransitionAnimation = Animation.easeInOut(duration: 0.28)

    static let optionCardVerticalPadding: CGFloat = 14
    static let optionPreviewHeight: CGFloat = 58
    static let unlockAnimationPreviewHeight: CGFloat = 108
    static let optionPreviewCornerRadius: CGFloat = 10
    static let optionPreviewFill = Color(nsColor: .quaternaryLabelColor).opacity(0.4)
    static let pickerPillFill = Color(nsColor: .quaternaryLabelColor).opacity(0.6)
    static let optionPreviewSelectedTintOpacity: CGFloat = 0.12
    static let optionLabelFont = Font.system(size: 12, weight: .medium)
    static let optionSelectionOutset: CGFloat = 2.5
    static let optionSelectionStrokeWidth: CGFloat = 3.5
    static let optionItemSpacing: CGFloat = 15
    static let optionPreviewShadowColor = Color.black.opacity(0.08)
    static let optionPreviewShadowRadius: CGFloat = 3
    static let optionPreviewOuterStroke = Color.clear
    static let optionPreviewOuterStrokeWidth: CGFloat = 0
    static let optionPreviewBorderWidth: CGFloat = 0.5
    static let sectionTitleFont = Font.subheadline.weight(.semibold)
    static let sectionTitleHorizontalInset: CGFloat = 6
    static let sectionTitleVerticalPadding: CGFloat = 2

    static let contentHorizontalPadding: CGFloat = 16

    // MARK: - Tab icon badges
    //
    // The small colored squircle behind each tab's glyph. Corner radius is
    // kept proportional to size (~28%, matching macOS's own rounded-square
    // icon tiles) so both sizes read as the same shape.

    static let sidebarIconBadgeSize: CGFloat = 23
    static let sidebarIconBadgeCornerRadius: CGFloat = 7
    static let sidebarIconBadgeGlyphSize: CGFloat = 13.5

    static let headerIconBadgeSize: CGFloat = 23
    static let headerIconBadgeCornerRadius: CGFloat = 7
    static let headerIconBadgeGlyphSize: CGFloat = 13.5


    // MARK: - Capture-quality tick strip (Your Face)
    //
    // One tick per stored sample, colored by `FaceSample.QualityTier`.
    // Fixed literals rather than `adaptiveColor` — semantic red/amber/green
    // that reads correctly against both dark and light content panels.

    static let qualityPoorColor = Color.red
    static let qualityFairColor = Color.orange
    static let qualityGoodColor = Color.green
    /// Samples with no recorded score — enrollments predating per-sample
    /// quality. Deliberately neutral: unrated is not the same as poor.
    static let qualityUnratedColor = Color.secondary.opacity(0.3)

    static let qualityTickWidth: CGFloat = 3.5
    static let qualityTickSpacing: CGFloat = 5.5
    static let qualityTickHeight: CGFloat = 26
    /// Caps the strip so an identity with an unusual number of samples
    /// compresses its ticks rather than running off the card.
    static let qualityStripMaxWidth: CGFloat = 250

    static let buttonBackgroundColor = Color(nsColor: .quaternaryLabelColor)

    static let headerHeight: CGFloat = 40

    /// No blur or scrim sits behind the header — every tint/blur approach
    /// tried either read as an "extra white band" or couldn't render inside
    /// SwiftUI's hosting view over native controls. Don't re-attempt without
    /// an explicit ask.

    /// Resolves live against the current system appearance rather than a
    /// value fixed at evaluation time.
    private static func adaptiveColor(dark: NSColor, light: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}
