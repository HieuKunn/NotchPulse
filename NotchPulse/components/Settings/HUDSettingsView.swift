import AppKit
import Defaults
import SwiftUI

struct HUDSettingsView: View {
    @Environment(\.settingsHighlightedId) private var highlightedId
    @Default(.inlineHUD) var inlineHUD
    @Default(.enableGradient) var enableGradient
    @Default(.optionKeyAction) var optionKeyAction
    @Default(.hudReplacement) var hudReplacement
    @ObservedObject var coordinator = NotchPulseViewCoordinator.shared
    @State private var accessibilityAuthorized = false

    var body: some View {
        Form {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc("Replace system HUD"))
                            .font(.headline)
                        Text(loc("Replaces the standard macOS volume, display brightness, and keyboard brightness HUDs with a custom design."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 40)
                    Defaults.Toggle("", key: .hudReplacement)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .disabled(!accessibilityAuthorized)
                }

                if !accessibilityAuthorized {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(loc("Accessibility access is required to replace the system HUD."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            Button(loc("Request Accessibility")) {
                                XPCHelperClient.shared.requestAccessibilityAuthorization()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(.top, 6)
                }
            }
            .id("hud_volume")
            .searchHighlight(highlightedId == "hud_volume")

            Section {
                Picker(loc("Option key behaviour"), selection: $optionKeyAction) {
                    ForEach(OptionKeyAction.allCases) { opt in
                        Text(loc(opt.rawValue)).tag(opt)
                    }
                }

                Picker(loc("Progress bar style"), selection: $enableGradient) {
                    Text(loc("Hierarchical"))
                        .tag(false)
                    Text(loc("Gradient"))
                        .tag(true)
                }
                Defaults.Toggle(key: .systemEventIndicatorShadow) {
                    Text(loc("Enable glowing effect"))
                }
                Defaults.Toggle(key: .systemEventIndicatorUseAccent) {
                    Text(loc("Tint progress bar with accent color"))
                }
            } header: {
                Text(loc("General"))
            }
            .disabled(!hudReplacement)

            Section {
                Defaults.Toggle(key: .showOpenNotchHUD) {
                    Text(loc("Show HUD in open notch"))
                }
                Defaults.Toggle(key: .showOpenNotchHUDPercentage) {
                    Text(loc("Show percentage"))
                }
                .disabled(!Defaults[.showOpenNotchHUD])
            } header: {
                HStack {
                    Text(loc("Open Notch"))
                    customBadge(text: loc("Beta"))
                }
                .id("hud_power")
            }
            .id("hud_power")
            .searchHighlight(highlightedId == "hud_power")
            .disabled(!hudReplacement)

            Section {
                Picker(loc("HUD style"), selection: $inlineHUD) {
                    Text(loc("Default"))
                        .tag(false)
                    Text(loc("Inline"))
                        .tag(true)
                }
                .onChange(of: Defaults[.inlineHUD]) {
                    if Defaults[.inlineHUD] {
                        withAnimation {
                            Defaults[.systemEventIndicatorShadow] = false
                            Defaults[.enableGradient] = false
                        }
                    }
                }

                Defaults.Toggle(key: .showClosedNotchHUDPercentage) {
                    Text(loc("Show percentage"))
                }
            } header: {
                Text(loc("Closed Notch"))
                    .id("hud_inline")
            }
            .id("hud_inline")
            .searchHighlight(highlightedId == "hud_inline")
            .disabled(!Defaults[.hudReplacement])
        }
        .formStyle(.grouped)
        .tint(.effectiveAccent)
        .task {
            accessibilityAuthorized = await XPCHelperClient.shared.isAccessibilityAuthorized()
        }
        .onAppear {
            XPCHelperClient.shared.startMonitoringAccessibilityAuthorization(every: 1.0)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { @MainActor in
                accessibilityAuthorized = await XPCHelperClient.shared.isAccessibilityAuthorized()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .accessibilityAuthorizationChanged)) { notification in
            if let granted = notification.userInfo?["granted"] as? Bool {
                accessibilityAuthorized = granted
            }
        }
    }
}

typealias HUD = HUDSettingsView

