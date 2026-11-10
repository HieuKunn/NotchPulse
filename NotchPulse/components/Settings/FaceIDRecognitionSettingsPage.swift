import SwiftUI

struct RecognitionSettingsPage: View {
    @Bindable private var coordinator = NotchPulseFaceUnlockCoordinator.shared
    @Bindable private var pocController = NotchPulsePOCController.shared
    @Bindable private var settings = NotchPulseFaceIDSettings.shared

    var body: some View {
        Section {
            Picker(loc("Match confidence"), selection: matchConfidenceIndex) {
                ForEach(MatchConfidenceLevel.allCases, id: \.self) { level in
                    Text(level.title).tag(level.sliderIndex)
                }
            }

            Picker(loc("Detection distance"), selection: detectionDistanceIndex) {
                ForEach(DetectionDistanceLevel.allCases, id: \.self) { level in
                    Text(level.title).tag(level.sliderIndex)
                }
            }
        } header: {
            Text(loc("Recognition"))
        } footer: {
            Text(loc("Higher match confidence requires closer similarity to your enrolled face. Closer detection distance ignores faces standing far away in the background."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Section {
            Toggle(loc("Liveness detection"), isOn: $settings.livenessChecksEnabled)

            if settings.livenessChecksEnabled {
                Picker(loc("Liveness Mode"), selection: $settings.livenessMode) {
                    ForEach(LivenessMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }
        } header: {
            Text(loc("Liveness Checks"))
        } footer: {
            Text(loc("Checks that you are a live person rather than a printed photo or screen. May slightly increase recognition time."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Match confidence

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
enum MatchConfidenceLevel: Int, CaseIterable, Hashable {
    case lessStrict, standard, moreStrict

    var title: String {
        switch self {
        case .lessStrict: return loc("Less strict")
        case .standard: return loc("Default")
        case .moreStrict: return loc("More strict")
        }
    }

    var threshold: Float {
        switch self {
        case .lessStrict: return 0.58
        case .standard: return 0.63
        case .moreStrict: return 0.68
        }
    }

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
enum DetectionDistanceLevel: Int, CaseIterable, Hashable {
    case close, standard, far

    var title: String {
        switch self {
        case .close: return loc("Close")
        case .standard: return loc("Default")
        case .far: return loc("Far")
        }
    }

    var minimumFaceWidth: Float {
        switch self {
        case .close: return 0.23
        case .standard: return 0.19
        case .far: return 0.15
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
