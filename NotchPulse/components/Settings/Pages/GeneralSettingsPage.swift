import AppKit
import Defaults
import LaunchAtLogin
import SwiftUI

struct GeneralSettingsPage: View {
    @State private var screens: [(uuid: String, name: String)] = NSScreen.screens.compactMap { screen in
        guard let uuid = screen.displayUUID else { return nil }
        return (uuid, screen.localizedName)
    }
    @EnvironmentObject var vm: NotchPulseViewModel
    @ObservedObject var coordinator = NotchPulseViewCoordinator.shared

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
    @Default(.menubarIcon) var menubarIcon
    @Default(.enableHaptics) var enableHaptics

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

    var body: some View {
        Form {
            // MARK: - Feature Tour Row
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(Color.effectiveAccent)
                        .font(.title3)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc("Feature Tour"))
                            .font(.headline)
                        Text(loc("Interactive Spotlight walkthrough highlighting all Notch features."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button(loc("Start Tour...")) {
                        FeatureTourController.shared.startTour()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
                .padding(.vertical, 2)
            }

            // MARK: - Notch / Island Style
            Section {
                Picker(loc("Appearance Style"), selection: $notchStyle) {
                    Text(loc("MacBook Notch")).tag(NotchStyle.notch)
                    Text(loc("Dynamic Island")).tag(NotchStyle.dynamicIsland)
                }
                .pickerStyle(.segmented)

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
                            Text("0px").font(.caption2).foregroundStyle(.secondary)
                        } maximumValueLabel: {
                            Text("24px").font(.caption2).foregroundStyle(.secondary)
                        }
                        Text(loc("Sets the floating gap between the top bezel and the Dynamic Island capsule."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                }
            } header: {
                Text(loc("Notch / Island Style"))
            }

            // MARK: - Notch Dimensions (Width)
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
                        label: { Text(loc("Notch Width")) },
                        minimumValueLabel: { Text("560px").font(.caption2).foregroundStyle(.secondary) },
                        maximumValueLabel: { Text("960px").font(.caption2).foregroundStyle(.secondary) },
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

            // MARK: - System Features
            Section {
                Toggle(loc("Show menu bar icon"), isOn: $menubarIcon)
                LaunchAtLogin.Toggle(loc("Launch at login"))

                Toggle(loc("Show on all displays"), isOn: $showOnAllDisplays)
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
                    refreshScreens()
                }
                .onChange(of: NSScreen.screens) {
                    refreshScreens()
                }
                .disabled(showOnAllDisplays)

                Toggle(loc("Automatically switch displays"), isOn: $automaticallySwitchDisplay)
                    .onChange(of: automaticallySwitchDisplay) {
                        NotificationCenter.default.post(
                            name: Notification.Name.automaticallySwitchDisplayChanged, object: nil)
                    }
                    .disabled(showOnAllDisplays)
            } header: {
                Text(loc("System features"))
            }

            // MARK: - Notch Sizing
            Section {
                Picker(loc("Notch height on notch displays"), selection: $notchHeightMode) {
                    Text(loc("Match real notch height")).tag(WindowHeightMode.matchRealNotchSize)
                    Text(loc("Match menu bar height")).tag(WindowHeightMode.matchMenuBar)
                    Text(loc("Custom height")).tag(WindowHeightMode.custom)
                }
                .onChange(of: notchHeightMode) {
                    switch notchHeightMode {
                    case .matchRealNotchSize: notchHeight = 38
                    case .matchMenuBar: notchHeight = 44
                    case .custom: notchHeight = 38
                    }
                    NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
                }

                if notchHeightMode == .custom {
                    Slider(value: $notchHeight, in: 15...45, step: 1) {
                        Text(loc("Custom notch size - %@", String(format: "%.0f", notchHeight)))
                    }
                    .onChange(of: notchHeight) {
                        NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
                    }
                }

                Picker(loc("Notch height on non-notch displays"), selection: $nonNotchHeightMode) {
                    Text(loc("Match menubar height")).tag(WindowHeightMode.matchMenuBar)
                    Text(loc("Match real notch height")).tag(WindowHeightMode.matchRealNotchSize)
                    Text(loc("Custom height")).tag(WindowHeightMode.custom)
                }
                .onChange(of: nonNotchHeightMode) {
                    switch nonNotchHeightMode {
                    case .matchMenuBar: nonNotchHeight = 24
                    case .matchRealNotchSize: nonNotchHeight = 32
                    case .custom: nonNotchHeight = 32
                    }
                    NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
                }

                if nonNotchHeightMode == .custom {
                    Slider(value: $nonNotchHeight, in: 0...40, step: 1) {
                        Text(loc("Custom notch size - %@", String(format: "%.0f", nonNotchHeight)))
                    }
                    .onChange(of: nonNotchHeight) {
                        NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
                    }
                }
            } header: {
                Text(loc("Notch sizing"))
            }

            // MARK: - Notch Behavior
            Section {
                Toggle(loc("Open notch on hover"), isOn: $openNotchOnHover)
                Toggle(loc("Enable haptic feedback"), isOn: $enableHaptics)

                Toggle(isOn: $coordinator.openLastTabByDefault) {
                    Text(loc("Restore last tab on hover"))
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
                        NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
                    }

                    Toggle(loc("Extend hover area"), isOn: $extendHoverArea)
                        .onChange(of: extendHoverArea) {
                            NotificationCenter.default.post(name: Notification.Name.expandedDragDetectionChanged, object: nil)
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
                            NotificationCenter.default.post(name: Notification.Name.expandedDragDetectionChanged, object: nil)
                        }

                        Text(loc("Expands the sensitivity area for hovering to open the notch, separate from Drag & Drop distance."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text(loc("Notch behavior"))
            }
        }
        .formStyle(.grouped)
    }

    private func refreshScreens() {
        screens = NSScreen.screens.compactMap { screen in
            guard let uuid = screen.displayUUID else { return nil }
            return (uuid, screen.localizedName)
        }
    }
}
