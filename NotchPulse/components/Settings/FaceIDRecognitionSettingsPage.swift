//
//  RecognitionSettingsPage.swift
//  NotchPulse
//

import SwiftUI

struct RecognitionSettingsPage: View {
    @Bindable private var coordinator = NotchPulseFaceUnlockCoordinator.shared
    @Bindable private var pocController = NotchPulsePOCController.shared
    @Bindable private var settings = NotchPulseFaceIDSettings.shared

    var body: some View {
        unlockedState
    }

    // MARK: - Content

    private var unlockedState: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.rowSpacing) {
            SettingsGroup {
                SettingsSteppedSliderRowContent(
                    title: "Match confidence",
                    valueLabel: matchConfidenceLevel.title,
                    index: matchConfidenceIndex,
                    stopCount: MatchConfidenceLevel.allCases.count
                )

                SettingsGroupDivider()

                SettingsSteppedSliderRowContent(
                    title: "Detection distance",
                    valueLabel: detectionDistanceLevel.title,
                    index: detectionDistanceIndex,
                    stopCount: DetectionDistanceLevel.allCases.count
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                SettingsSectionTitle(text: "Liveness")
                SettingsGroup {
                    SettingsRowContent(
                        title: "Liveness detection",
                        info: "Checks that you're a live person, not a photo. May increase unlock time."
                    ) {
                        NotchPulseToggle(isOn: $settings.livenessChecksEnabled)
                    }
                    SettingsGroupDivider()
                    LivenessModePicker(
                        selection: $settings.livenessMode,
                        isEnabled: settings.livenessChecksEnabled
                    )
                }
            }
        }
    }

    // MARK: - Match confidence

    /// Nearest of the three snap points to whatever's stored, in case the
    /// value doesn't land exactly on one of the stops.
    private var matchConfidenceLevel: MatchConfidenceLevel {
        .nearest(to: coordinator.matchThreshold)
    }

    private var matchConfidenceIndex: Binding<Double> {
        Binding(
            get: { matchConfidenceLevel.sliderIndex },
            set: { coordinator.matchThreshold = MatchConfidenceLevel.from(sliderIndex: $0).threshold }
        )
    }

    // MARK: - Detection distance

    private var detectionDistanceLevel: DetectionDistanceLevel {
        .nearest(to: settings.minimumFaceWidth)
    }

    private var detectionDistanceIndex: Binding<Double> {
        Binding(
            get: { detectionDistanceLevel.sliderIndex },
            set: { settings.minimumFaceWidth = DetectionDistanceLevel.from(sliderIndex: $0).minimumFaceWidth }
        )
    }
}

/// The three selectable points on the "Match confidence" slider — named
/// rather than exposing the raw cosine-similarity threshold directly.
private enum MatchConfidenceLevel: Int, CaseIterable {
    case lessStrict, standard, moreStrict

    var title: String {
        switch self {
        case .lessStrict: return "Less strict"
        case .standard: return "Default"
        case .moreStrict: return "More strict"
        }
    }

    var threshold: Float {
        switch self {
        case .lessStrict: return 0.58
        case .standard: return 0.63
        case .moreStrict: return 0.68
        }
    }

    /// Position in `allCases` — same role as `AutoLockInterval.sliderIndex`.
    var sliderIndex: Double {
        Double(Self.allCases.firstIndex(of: self) ?? 0)
    }

    static func from(sliderIndex: Double) -> Self {
        let clamped = Int(sliderIndex.rounded())
        return allCases.indices.contains(clamped) ? allCases[clamped] : .standard
    }

    static func nearest(to threshold: Float) -> Self {
        allCases.min { abs($0.threshold - threshold) < abs($1.threshold - threshold) } ?? .standard
    }
}

/// The three selectable points on the "Detection distance" slider.
private enum DetectionDistanceLevel: Int, CaseIterable {
    case close, standard, far

    var title: String {
        switch self {
        case .close: return "Close"
        case .standard: return "Default"
        case .far: return "Far"
        }
    }

    var minimumFaceWidth: Float {
        switch self {
        case .close: return 0.22
        case .standard: return 0.16
        case .far: return 0.12
        }
    }

    var sliderIndex: Double {
        Double(Self.allCases.firstIndex(of: self) ?? 0)
    }

    static func from(sliderIndex: Double) -> Self {
        let clamped = Int(sliderIndex.rounded())
        return allCases.indices.contains(clamped) ? allCases[clamped] : .standard
    }

    static func nearest(to width: Float) -> Self {
        allCases.min { abs($0.minimumFaceWidth - width) < abs($1.minimumFaceWidth - width) } ?? .standard
    }
}
