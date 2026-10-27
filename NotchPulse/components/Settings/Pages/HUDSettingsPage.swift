import AppKit
import Defaults
import SwiftUI

struct HUDSettingsPage: View {
    @EnvironmentObject var vm: NotchPulseViewModel
    @Default(.inlineHUD) var inlineHUD
    @Default(.enableGradient) var enableGradient
    @Default(.optionKeyAction) var optionKeyAction
    @Default(.hudReplacement) var hudReplacement
    @Default(.systemEventIndicatorShadow) var systemEventIndicatorShadow
    @Default(.systemEventIndicatorUseAccent) var systemEventIndicatorUseAccent
    @Default(.showOpenNotchHUD) var showOpenNotchHUD
    @Default(.showOpenNotchHUDPercentage) var showOpenNotchHUDPercentage
    @Default(.showClosedNotchHUDPercentage) var showClosedNotchHUDPercentage
    @ObservedObject var coordinator = NotchPulseViewCoordinator.shared
    @State private var accessibilityAuthorized = false

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $hudReplacement) {
                    Text(loc("Replace system HUD"))
                        .font(.headline)
                    Text(loc("Replaces the standard macOS volume, display brightness, and keyboard brightness HUDs with a custom design."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .toggleStyle(.switch)
                .disabled(!accessibilityAuthorized)

                if !accessibilityAuthorized {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(loc("Accessibility access is required to replace the system HUD."))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button(loc("Request Accessibility")) {
                            XPCHelperClient.shared.requestAccessibilityAuthorization()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    .padding(.top, 4)
                }
            }

            Section {
                Picker(loc("Option key behaviour"), selection: $optionKeyAction) {
                    ForEach(OptionKeyAction.allCases) { opt in
                        Text(loc(opt.rawValue)).tag(opt)
                    }
                }

                Picker(loc("Progress bar style"), selection: $enableGradient) {
                    Text(loc("Hierarchical")).tag(false)
                    Text(loc("Gradient")).tag(true)
                }

                Toggle(loc("Enable glowing effect"), isOn: $systemEventIndicatorShadow)
                Toggle(loc("Tint progress bar with accent color"), isOn: $systemEventIndicatorUseAccent)
            } header: {
                Text(loc("General"))
            }
            .disabled(!hudReplacement)

            Section {
                Toggle(loc("Show HUD in open notch"), isOn: $showOpenNotchHUD)
                Toggle(loc("Show percentage"), isOn: $showOpenNotchHUDPercentage)
                    .disabled(!showOpenNotchHUD)
            } header: {
                HStack(spacing: 6) {
                    Text(loc("Open Notch"))
                    customBadge(text: loc("Beta"))
                }
            }
            .disabled(!hudReplacement)

            Section {
                Picker(loc("HUD style"), selection: $inlineHUD) {
                    Text(loc("Default")).tag(false)
                    Text(loc("Inline")).tag(true)
                }
                .onChange(of: inlineHUD) { _, newValue in
                    if newValue {
                        withAnimation {
                            systemEventIndicatorShadow = false
                            enableGradient = false
                        }
                    }
                }

                Toggle(loc("Show percentage"), isOn: $showClosedNotchHUDPercentage)
            } header: {
                Text(loc("Closed Notch"))
            }
            .disabled(!hudReplacement)
        }
        .formStyle(.grouped)
        .task {
            accessibilityAuthorized = await XPCHelperClient.shared.isAccessibilityAuthorized()
        }
        .onAppear {
            XPCHelperClient.shared.startMonitoringAccessibilityAuthorization(every: 1.0)
        }
        .onDisappear {
            XPCHelperClient.shared.stopMonitoringAccessibilityAuthorization()
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
