import AVFoundation
import AppKit
import Defaults
import LaunchAtLogin
import SwiftUI

struct NotchWidthLivePreview: View {
    let width: CGFloat
    let style: NotchStyle

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .frame(height: 52)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
                    )

                VStack(spacing: 0) {
                    if style == .notch {
                        Rectangle()
                            .fill(Color(nsColor: .separatorColor).opacity(0.7))
                            .frame(height: 2)

                        let previewScale: CGFloat = 0.22
                        let previewWidth: CGFloat = width * previewScale

                        NotchShape(topCornerRadius: 4, bottomCornerRadius: 7)
                            .fill(Color.primary.opacity(0.85))
                            .frame(width: max(100, previewWidth), height: 18)
                            .overlay(
                                Text("\(Int(width))px")
                                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(Color(nsColor: .windowBackgroundColor))
                            )
                        Spacer()
                    } else {
                        Rectangle()
                            .fill(Color(nsColor: .separatorColor).opacity(0.7))
                            .frame(height: 2)

                        let previewScale: CGFloat = 0.22
                        let previewWidth: CGFloat = width * previewScale

                        Capsule()
                            .fill(Color.primary.opacity(0.85))
                            .frame(width: max(100, previewWidth), height: 16)
                            .padding(.top, 4)
                            .overlay(
                                Text("\(Int(width))px")
                                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(Color(nsColor: .windowBackgroundColor))
                                    .padding(.top, 4)
                            )
                        Spacer()
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct GeneralSettingsView: View {
    @Environment(\.settingsHighlightedId) private var highlightedId
    @State private var screens: [(uuid: String, name: String)] = NSScreen.screens.compactMap { screen in
        guard let uuid = screen.displayUUID else { return nil }
        return (uuid, screen.localizedName)
    }
    @ObservedObject var coordinator = NotchPulseViewCoordinator.shared
    @State private var hasCameraInput: Bool = true

    @Default(.mirrorShape) var mirrorShape
    @Default(.showEmojis) var showEmojis
    @Default(.gestureSensitivity) var gestureSensitivity
    @Default(.minimumHoverDuration) var minimumHoverDuration
    @Default(.nonNotchHeight) var nonNotchHeight
    @Default(.nonNotchHeightMode) var nonNotchHeightMode
    @Default(.notchHeight) var notchHeight
    @Default(.notchHeightMode) var notchHeightMode
    @Default(.showOnAllDisplays) var showOnAllDisplays
    @Default(.automaticallySwitchDisplay) var automaticallySwitchDisplay
    @Default(.enableGestures) var enableGestures
    @Default(.openNotchOnHover) var openNotchOnHover
    @Default(.extendHoverArea) var extendHoverArea
    @Default(.hoverAreaPadding) var hoverAreaPadding
    @Default(.notchStyle) var notchStyle
    @Default(.dynamicIslandTopOffset) var dynamicIslandTopOffset
    @Default(.notchOpenWidth) var notchOpenWidth

    @State private var autoClosePreviewTask: Task<Void, Never>? = nil

    private func triggerWidthPreview(width: CGFloat, isEditing: Bool = false) {
        SharingStateManager.shared.preventNotchClose = true
        NotificationCenter.default.post(name: .previewNotchWidth, object: width)

        autoClosePreviewTask?.cancel()
        if !isEditing {
            autoClosePreviewTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(3500))
                guard !Task.isCancelled else { return }
                SharingStateManager.shared.preventNotchClose = false
                NotificationCenter.default.post(name: .closeNotchPreview, object: nil)
            }
        }
    }

    @ViewBuilder
    private var cameraMirrorSection: some View {
        Section {
            Defaults.Toggle(key: .showMirror) {
                Text(loc("Enable NotchPulse mirror"))
            }
            .disabled(!hasCameraInput)
            .task {
                let available = await Task.detached(priority: .utility) { checkVideoInput() }.value
                hasCameraInput = available
            }

            Picker(loc("Mirror shape"), selection: $mirrorShape) {
                Text(loc("Circle"))
                    .tag(MirrorShapeEnum.circle)
                Text(loc("Square"))
                    .tag(MirrorShapeEnum.rectangle)
            }
        } header: {
            Text(loc("Camera Mirror"))
                .id("camera_mirror")
        } footer: {
            Text(loc("Display a live selfie camera preview directly in your Notch or Dynamic Island."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var styleSection: some View {
        Section {
            HStack(spacing: 14) {
                // Option 1: Classic MacBook Notch
                Button {
                    notchStyle = .notch
                } label: {
                    VStack(spacing: 8) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.regularMaterial)
                                .frame(height: 52)

                            VStack(spacing: 0) {
                                Rectangle()
                                    .fill(Color(nsColor: .separatorColor).opacity(0.35))
                                    .frame(height: 3)
                                NotchShape(topCornerRadius: 3, bottomCornerRadius: 6)
                                    .fill(notchStyle == .notch ? Color.accentColor : Color.primary.opacity(0.7))
                                    .frame(width: 60, height: 16)
                                Spacer()
                            }
                        }

                        HStack(spacing: 5) {
                            Image(systemName: notchStyle == .notch ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(notchStyle == .notch ? Color.accentColor : .secondary)
                            Text(loc("MacBook Notch"))
                                .font(.subheadline)
                                .fontWeight(notchStyle == .notch ? .semibold : .regular)
                        }
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(notchStyle == .notch ? Color.effectiveAccent : Color(nsColor: .separatorColor).opacity(0.5), lineWidth: notchStyle == .notch ? 2 : 1)
                    )
                }
                .buttonStyle(.plain)

                // Option 2: Floating Dynamic Island
                Button {
                    notchStyle = .dynamicIsland
                } label: {
                    VStack(spacing: 8) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.regularMaterial)
                                .frame(height: 52)

                            VStack(spacing: 0) {
                                Rectangle()
                                    .fill(Color(nsColor: .separatorColor).opacity(0.35))
                                    .frame(height: 3)
                                Capsule()
                                    .fill(notchStyle == .dynamicIsland ? Color.accentColor : Color.primary.opacity(0.7))
                                    .frame(width: 52, height: 13)
                                    .padding(.top, 5)
                                Spacer()
                            }
                        }

                        HStack(spacing: 5) {
                            Image(systemName: notchStyle == .dynamicIsland ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(notchStyle == .dynamicIsland ? Color.accentColor : .secondary)
                            Text(loc("Dynamic Island"))
                                .font(.subheadline)
                                .fontWeight(notchStyle == .dynamicIsland ? .semibold : .regular)
                        }
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(notchStyle == .dynamicIsland ? Color.effectiveAccent : Color(nsColor: .separatorColor).opacity(0.5), lineWidth: notchStyle == .dynamicIsland ? 2 : 1)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 4)

            if notchStyle == .dynamicIsland {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(loc("Top Gap (Distance from Screen Edge)"))
                        Spacer()
                        Text("\(Int(dynamicIslandTopOffset)) px")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $dynamicIslandTopOffset, in: 0...24, step: 1) {
                        Text(loc("Top Gap"))
                    } minimumValueLabel: {
                        Text("0px")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } maximumValueLabel: {
                        Text("24px")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(loc("Sets the floating gap between the top bezel and the Dynamic Island capsule."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        } header: {
            Text(loc("Notch / Island Style"))
        }
    }

    @ViewBuilder
    private var dimensionsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(loc("Expanded Width"))
                    Spacer()
                    Text("\(Int(notchOpenWidth)) px")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .fontWeight(.medium)

                    Button(loc("Reset")) {
                        notchOpenWidth = 740
                        triggerWidthPreview(width: 740, isEditing: false)
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .disabled(notchOpenWidth == 740)
                }

                NotchWidthLivePreview(width: notchOpenWidth, style: notchStyle)

                Slider(
                    value: $notchOpenWidth,
                    in: 560...960,
                    step: 10,
                    label: {
                        Text(loc("Notch Width"))
                    },
                    minimumValueLabel: {
                        Text("560px")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    },
                    maximumValueLabel: {
                        Text("960px")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    },
                    onEditingChanged: { editing in
                        triggerWidthPreview(width: notchOpenWidth, isEditing: editing)
                    }
                )

                HStack(spacing: 8) {
                    Button(loc("Compact (580px)")) {
                        notchOpenWidth = 580
                        triggerWidthPreview(width: 580, isEditing: false)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button(loc("Standard (740px)")) {
                        notchOpenWidth = 740
                        triggerWidthPreview(width: 740, isEditing: false)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button(loc("Wide (860px)")) {
                        notchOpenWidth = 860
                        triggerWidthPreview(width: 860, isEditing: false)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.top, 2)

                Text(loc("Controls the horizontal expansion length when the notch or dynamic island is open. The notch opens and resizes live on your screen as you drag the slider."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            .onChange(of: notchOpenWidth) { _, newWidth in
                triggerWidthPreview(width: newWidth, isEditing: true)
            }
            .onDisappear {
                autoClosePreviewTask?.cancel()
                SharingStateManager.shared.preventNotchClose = false
                NotificationCenter.default.post(name: .closeNotchPreview, object: nil)
            }
        } header: {
            Text(loc("Notch Dimensions (Width)"))
        }
    }

    @ViewBuilder
    private var systemFeaturesSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { Defaults[.menubarIcon] },
                set: { Defaults[.menubarIcon] = $0 }
            )) {
                Text(loc("Show menu bar icon"))
            }
            .tint(.effectiveAccent)

            LaunchAtLogin.Toggle(loc("Launch at login"))

            VStack(alignment: .leading, spacing: 4) {
                Defaults.Toggle(key: .preloadExpandedNotch) {
                    Text(loc("Preload expanded notch after launch"))
                }
                Text(loc("Loads the expanded interface shortly after launch for a smoother first open. Uses extra CPU and memory at startup."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Defaults.Toggle(key: .showOnAllDisplays) {
                Text(loc("Show on all displays"))
            }
            .onChange(of: showOnAllDisplays) {
                NotificationCenter.default.post(
                    name: Notification.Name.showOnAllDisplaysChanged, object: nil)
            }

            Picker(loc("Preferred display"), selection: $coordinator.preferredScreenUUID) {
                ForEach(screens, id: \.uuid) { screen in
                    Text(screen.name).tag(screen.uuid as String?)
                }
            }
            .onAppear {
                screens = NSScreen.screens.compactMap { screen in
                    guard let uuid = screen.displayUUID else { return nil }
                    return (uuid, screen.localizedName)
                }
            }
            .onChange(of: NSScreen.screens) {
                screens = NSScreen.screens.compactMap { screen in
                    guard let uuid = screen.displayUUID else { return nil }
                    return (uuid, screen.localizedName)
                }
            }
            .disabled(showOnAllDisplays)

            Defaults.Toggle(key: .automaticallySwitchDisplay) {
                Text(loc("Automatically switch displays"))
            }
            .onChange(of: automaticallySwitchDisplay) {
                NotificationCenter.default.post(
                    name: Notification.Name.automaticallySwitchDisplayChanged, object: nil)
            }
            .disabled(showOnAllDisplays)
        } header: {
            Text(loc("System features"))
        }
    }

    @ViewBuilder
    private var notchSizingSection: some View {
        Section {
            Picker(
                selection: $notchHeightMode,
                label: Text(loc("Notch height on notch displays"))
            ) {
                Text(loc("Match real notch height"))
                    .tag(WindowHeightMode.matchRealNotchSize)
                Text(loc("Match menu bar height"))
                    .tag(WindowHeightMode.matchMenuBar)
                Text(loc("Custom height"))
                    .tag(WindowHeightMode.custom)
            }
            .onChange(of: notchHeightMode) {
                switch notchHeightMode {
                case .matchRealNotchSize:
                    notchHeight = 38
                case .matchMenuBar:
                    notchHeight = 44
                case .custom:
                    notchHeight = 38
                }
                NotificationCenter.default.post(
                    name: Notification.Name.notchHeightChanged, object: nil)
            }

            if notchHeightMode == .custom {
                Slider(value: $notchHeight, in: 15...45, step: 1) {
                    Text(loc("Custom notch size - %@", String(format: "%.0f", notchHeight)))
                }
                .onChange(of: notchHeight) {
                    NotificationCenter.default.post(
                        name: Notification.Name.notchHeightChanged, object: nil)
                }
            }

            Picker(loc("Notch height on non-notch displays"), selection: $nonNotchHeightMode) {
                Text(loc("Match menubar height"))
                    .tag(WindowHeightMode.matchMenuBar)
                Text(loc("Match real notch height"))
                    .tag(WindowHeightMode.matchRealNotchSize)
                Text(loc("Custom height"))
                    .tag(WindowHeightMode.custom)
            }
            .onChange(of: nonNotchHeightMode) {
                switch nonNotchHeightMode {
                case .matchMenuBar:
                    nonNotchHeight = 24
                case .matchRealNotchSize:
                    nonNotchHeight = 32
                case .custom:
                    nonNotchHeight = 32
                }
                NotificationCenter.default.post(
                    name: Notification.Name.notchHeightChanged, object: nil)
            }

            if nonNotchHeightMode == .custom {
                Slider(value: $nonNotchHeight, in: 0...40, step: 1) {
                    Text(loc("Custom notch size - %@", String(format: "%.0f", nonNotchHeight)))
                }
                .onChange(of: nonNotchHeight) {
                    NotificationCenter.default.post(
                        name: Notification.Name.notchHeightChanged, object: nil)
                }
            }
        } header: {
            Text(loc("Notch sizing"))
        }
    }

    var body: some View {
        Form {
            Section {
                Button(action: {
                    FeatureTourController.shared.startTour()
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.primary)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(loc("Feature Tour"))
                                .font(.headline)
                            Text(loc("Interactive Spotlight walkthrough highlighting all Notch features."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .contentShape(Rectangle())
            }
            .id("feature_tour")
            .searchHighlight(highlightedId == "feature_tour")

            styleSection
                .id("notch_style")
                .searchHighlight(highlightedId == "notch_style")

            dimensionsSection
                .id("notch_dimensions")
                .searchHighlight(highlightedId == "notch_dimensions")

            systemFeaturesSection
                .id("system_features")
                .searchHighlight(highlightedId == "system_features")

            cameraMirrorSection
                .id("camera_mirror")
                .searchHighlight(highlightedId == "camera_mirror")

            notchSizingSection
                .id("notch_sizing")
                .searchHighlight(highlightedId == "notch_sizing")

            notchBehaviourSection
                .id("notch_behavior")
                .searchHighlight(highlightedId == "notch_behavior")
        }
        .formStyle(.grouped)
        .tint(.effectiveAccent)
    }

    @ViewBuilder
    private var notchBehaviourSection: some View {
        Section {
            Defaults.Toggle(key: .openNotchOnHover) {
                Text(loc("Open notch on hover"))
            }
            Defaults.Toggle(key: .enableHaptics) {
                Text(loc("Enable haptic feedback"))
            }
            VStack(alignment: .leading, spacing: 4) {
                Toggle(loc("Restore last tab on hover"), isOn: $coordinator.openLastTabByDefault)
                Text(loc("When opening the notch on hover, restore the last selected tab (e.g. CPU/RAM Stats, Battery) instead of resetting to Home."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if openNotchOnHover {
                Slider(value: $minimumHoverDuration, in: 0...1, step: 0.1) {
                    HStack {
                        Text(loc("Hover delay"))
                        Spacer()
                        Text("\(minimumHoverDuration, specifier: "%.1f")s")
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: minimumHoverDuration) {
                    NotificationCenter.default.post(
                        name: Notification.Name.notchHeightChanged, object: nil)
                }

                Defaults.Toggle(key: .extendHoverArea) {
                    Text(loc("Extend hover area"))
                }
                .onChange(of: extendHoverArea) {
                    NotificationCenter.default.post(
                        name: Notification.Name.expandedDragDetectionChanged,
                        object: nil
                    )
                }

                if extendHoverArea {
                    Slider(value: $hoverAreaPadding, in: 5...60, step: 5) {
                        HStack {
                            Text(loc("Hover detection range"))
                            Spacer()
                            Text("\(hoverAreaPadding, specifier: "%.0f") px")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onChange(of: hoverAreaPadding) {
                        NotificationCenter.default.post(
                            name: Notification.Name.expandedDragDetectionChanged,
                            object: nil
                        )
                    }
                    Text(loc("Expands the sensitivity area for hovering to open the notch, separate from Drag & Drop distance."))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        } header: {
            Text(loc("Notch behavior"))
        }
    }
}

typealias GeneralSettings = GeneralSettingsView

