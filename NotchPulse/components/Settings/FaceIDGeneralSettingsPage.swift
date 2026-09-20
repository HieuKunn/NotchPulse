//
//  FaceIDGeneralSettingsPage.swift
//  NotchPulse
//

import OSLog
import SwiftUI

struct FaceIDUnlockOptionsPage: View {
    @Bindable private var coordinator = NotchPulseFaceUnlockCoordinator.shared
    @Bindable private var settings = NotchPulseFaceIDSettings.shared

    /// Refreshed when the app regains focus, so granting the permission in
    /// System Settings clears the prompt below without a relaunch.
    @State private var inputMonitoring = NotchPulseSpaceKeyMonitor.inputMonitoringAccess

    /// True once "On space" is selected but NotchPulse can't read the keyboard yet.
    private var needsInputMonitoring: Bool {
        settings.unlockTriggers.contains(.onSpace) && inputMonitoring != .granted
    }

    /// Dev-only: under Xcode the reading above is Xcode's permission, not
    /// NotchPulse's, so it's meaningless. See `NotchPulseSpaceKeyMonitor.isLaunchedByXcode`.
    private var hasInheritedXcodePermission: Bool {
        settings.unlockTriggers.contains(.onSpace) && NotchPulseSpaceKeyMonitor.isLaunchedByXcode
    }

    var body: some View {
        SettingsGroup {
            SettingsRowContent(title: "Enable Face Unlock") {
                NotchPulseToggle(isOn: $coordinator.isEnabled)
            }
            SettingsGroupDivider()
            UnlockTriggerPicker(selection: $settings.unlockTriggers, isEnabled: coordinator.isEnabled)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            inputMonitoring = NotchPulseSpaceKeyMonitor.inputMonitoringAccess
        }
        .onChange(of: settings.unlockTriggers) { oldValue, newValue in
            // Only prompt on the transition into selecting "On space".
            NotchPulseSpaceKeyMonitor.log.info("unlockTriggers changed: old=\(String(describing: oldValue), privacy: .public) new=\(String(describing: newValue), privacy: .public) state=\(String(describing: inputMonitoring), privacy: .public)")
            if newValue.contains(.onSpace), !oldValue.contains(.onSpace), inputMonitoring != .granted {
                NotchPulseSpaceKeyMonitor.requestInputMonitoringAccess()
                // tccd flips notDetermined -> denied just after the call
                // returns, so re-read on the next beat rather than inline.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    inputMonitoring = NotchPulseSpaceKeyMonitor.inputMonitoringAccess
                }
            }
        }
        if hasInheritedXcodePermission {
            SettingsCaption(text: "Running from Xcode — permission checks resolve against Xcode’s grants, not NotchPulse’s, so this reading is meaningless. Launch NotchPulse.app on its own to see the real state.")
        } else if needsInputMonitoring {
            inputMonitoringNotice()
        }

        VStack(alignment: .leading, spacing: 8) {
            SettingsSectionTitle(text: "Behaviour")
            SettingsGroup {
                SettingsRowContent(title: "Retry again on Hover") {
                    NotchPulseToggle(isOn: $settings.retryOnHover)
                }
                SettingsGroupDivider()
                SettingsRowContent(title: "Auto retry again once") {
                    NotchPulseToggle(isOn: $settings.autoRetryOnce)
                }
                SettingsGroupDivider()
                SettingsRowContent(title: "Haptic feedback") {
                    NotchPulseToggle(isOn: $settings.hapticFeedbackEnabled)
                }
                SettingsGroupDivider()
                SettingsSteppedSliderRowContent(
                    title: "Face detection duration",
                    valueLabel: "\(settings.faceDetectionSeconds)s",
                    index: Binding(
                        get: { Double(settings.faceDetectionSeconds - NotchPulseFaceIDSettings.faceDetectionRange.lowerBound) },
                        set: { settings.faceDetectionSeconds = NotchPulseFaceIDSettings.faceDetectionRange.lowerBound + Int($0.rounded()) }
                    ),
                    stopCount: NotchPulseFaceIDSettings.faceDetectionRange.count
                )
            }
        }

        VStack(alignment: .leading, spacing: 8) {
            SettingsSectionTitle(text: "Animation")
            SettingsGroup {
                SettingsRowContent(title: "Show animation") {
                    NotchPulseToggle(isOn: $settings.showUnlockAnimation)
                }
                SettingsGroupDivider()
                UnlockAnimationPicker(
                    selection: $settings.unlockAnimationStyle,
                    isEnabled: settings.showUnlockAnimation
                )
            }
        }
    }

    /// Shown while "On space" is selected but Input Monitoring isn't granted.
    private func inputMonitoringNotice() -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SettingsCaption(text: "“On space” reads the keyboard directly to see the space key on the lock screen, which needs Accessibility — the same permission NotchPulse uses to type your password. Switch NotchPulse on under Privacy & Security → Accessibility, then quit and reopen NotchPulse.")
            Button("Open Accessibility settings") {
                // Covers the rare install with no Accessibility grant at all.
                NotchPulseSpaceKeyMonitor.requestInputMonitoringAccess()
                openSystemSettings(pane: "Privacy_Accessibility")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    inputMonitoring = NotchPulseSpaceKeyMonitor.inputMonitoringAccess
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(FaceIDTheme.accent)
        }
    }

    private func openSystemSettings(pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }
}

typealias GeneralSettingsPage = FaceIDUnlockOptionsPage
