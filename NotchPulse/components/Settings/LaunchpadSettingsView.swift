import Defaults
import KeyboardShortcuts
import SwiftUI

struct LaunchpadSettingsView: View {
    @Environment(\.settingsHighlightedId) private var highlightedId
    @ObservedObject private var launchpad = LaunchpadManager.shared
    @ObservedObject private var permissions = PermissionsManager.shared

    @Default(.enableLaunchpad) private var enableLaunchpad
    @Default(.launchpadReplaceSystemGesture) private var launchpadReplaceSystemGesture
    @Default(.launchpadColumns) private var launchpadColumns
    @Default(.launchpadRows) private var launchpadRows
    @Default(.launchpadIconSize) private var launchpadIconSize
    @Default(.launchpadShowLabels) private var launchpadShowLabels
    @Default(.launchpadBackgroundStyle) private var launchpadBackgroundStyle
    @Default(.launchpadHotCorner) private var launchpadHotCorner

    @State private var showResetConfirmation = false

    var body: some View {
        Form {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc("Enable Launchpad Home"))
                            .font(.headline)
                        Text(loc("Classic full-screen paged app grid with folders, swipe navigation, and instant search."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 40)
                    Defaults.Toggle("", key: .enableLaunchpad)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .onChange(of: enableLaunchpad) { _, _ in
                            LaunchpadWindowController.shared.configureHotCornerMonitor()
                            LaunchpadWindowController.shared.configureSystemLaunchpadInterceptor()
                        }
                }

                KeyboardShortcuts.Recorder(loc("Open Launchpad:"), name: .toggleLaunchpad)
                    .disabled(!enableLaunchpad)

                Picker(loc("Hot corner trigger"), selection: $launchpadHotCorner) {
                    ForEach(LaunchpadHotCorner.allCases) { corner in
                        Text(loc(corner.rawValue)).tag(corner)
                    }
                }
                .disabled(!enableLaunchpad)

                Defaults.Toggle(loc("Replace macOS Trackpad pinch gesture"), key: .launchpadReplaceSystemGesture)
                    .disabled(!enableLaunchpad)
                    .onChange(of: launchpadReplaceSystemGesture) { _, _ in
                        LaunchpadWindowController.shared.configureSystemLaunchpadInterceptor()
                    }

                HStack {
                    Text(loc("Preview Launchpad Home"))
                    Spacer()
                    Button(loc("Open Launchpad")) {
                        LaunchpadWindowController.shared.show()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(!enableLaunchpad)
                }

                if permissions.accessibilityStatus != .granted {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: "accessibility")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(loc("Accessibility Permission Missing"))
                                .font(.subheadline.weight(.medium))
                            Text(loc("Accessibility access is required to intercept Trackpad pinch gestures and Dock Applications."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Button(loc("Grant")) {
                            permissions.request(permission: .accessibility)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            } header: {
                Text(loc("Launchpad Home"))
            }
            .id("launchpad_general")
            .searchHighlight(highlightedId == "launchpad_general")

            Section {
                Stepper(
                    loc("Columns per page: %lld", launchpadColumns),
                    value: $launchpadColumns,
                    in: 4...10
                )
                .onChange(of: launchpadColumns) { _, _ in
                    launchpad.reflowOverflowIfNeeded()
                }

                Stepper(
                    loc("Rows per page: %lld", launchpadRows),
                    value: $launchpadRows,
                    in: 3...8
                )
                .onChange(of: launchpadRows) { _, _ in
                    launchpad.reflowOverflowIfNeeded()
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(loc("Icon size"))
                        Spacer()
                        Text("\(Int(launchpadIconSize)) px")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $launchpadIconSize, in: 56...104, step: 4)
                }

                Defaults.Toggle(loc("Show application names"), key: .launchpadShowLabels)

                Picker(loc("Background style"), selection: $launchpadBackgroundStyle) {
                    ForEach(LaunchpadBackgroundStyle.allCases) { style in
                        Text(loc(style.rawValue)).tag(style)
                    }
                }
            } header: {
                Text(loc("Grid & Appearance"))
            } footer: {
                Text(loc("Swipe with two fingers on your trackpad to switch pages, drag icons onto each other to create folders, and pinch in or press Esc to close."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .id("launchpad_layout")
            .searchHighlight(highlightedId == "launchpad_layout")
            .disabled(!enableLaunchpad)

            Section {
                HStack {
                    Text(loc("Indexed applications"))
                    Spacer()
                    Text("\(launchpad.allApplications.count)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                HStack {
                    Text(loc("Pages"))
                    Spacer()
                    Text("\(launchpad.pages.count)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                HStack(spacing: 12) {
                    Button(loc("Refresh Applications")) {
                        launchpad.refreshApps(force: true)
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button(loc("Reset Layout & Folders"), role: .destructive) {
                        showResetConfirmation = true
                    }
                    .buttonStyle(.bordered)
                }
            } header: {
                Text(loc("Applications & Layout"))
            }
            .id("launchpad_management")
            .searchHighlight(highlightedId == "launchpad_management")
            .disabled(!enableLaunchpad)
        }
        .formStyle(.grouped)
        .tint(.effectiveAccent)
        .onAppear {
            if launchpad.pages.isEmpty {
                launchpad.prepareForPresentation()
            }
            permissions.refreshAccessibility()
            if permissions.accessibilityStatus == .granted {
                LaunchpadWindowController.shared.configureSystemLaunchpadInterceptor()
            }
        }
        .alert(loc("Reset Launchpad Layout?"), isPresented: $showResetConfirmation) {
            Button(loc("Reset"), role: .destructive) {
                launchpad.resetLayout()
            }
            Button(loc("Cancel"), role: .cancel) {}
        } message: {
            Text(loc("This will restore all folders and icon positions to the default alphabetical order."))
        }
    }
}

