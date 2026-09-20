//
//  FaceIDGeneralSettingsPage.swift
//  NotchPulse
//

import OSLog
import SwiftUI

struct FaceIDUnlockOptionsPage: View {
    @Bindable private var coordinator = NotchPulseFaceUnlockCoordinator.shared
    @Bindable private var settings = NotchPulseFaceIDSettings.shared
    @Bindable private var authCoordinator = NotchPulseSystemAuthCoordinator.shared

    var body: some View {
        SettingsGroup {
            SettingsRowContent(title: "Enable Face Unlock") {
                NotchPulseToggle(isOn: $coordinator.isEnabled)
            }
        }

        VStack(alignment: .leading, spacing: 6) {
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

        VStack(alignment: .leading, spacing: 6) {
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

        VStack(alignment: .leading, spacing: 6) {
            SettingsSectionTitle(text: "System & Terminal Authorization")
            SettingsGroup {
                SettingsRowContent(
                    title: "Authorize system prompts",
                    subtitle: "Automatically verify with Face ID when macOS requires admin approval or installer confirmation."
                ) {
                    NotchPulseToggle(isOn: $settings.isSystemAuthFaceIDEnabled)
                }
                SettingsGroupDivider()
                SettingsRowContent(
                    title: "Terminal & field quick-auth",
                    subtitle: "Fill passwords in Terminal, iTerm, or active password fields with ⌘⌥F."
                ) {
                    NotchPulseToggle(isOn: $settings.isTerminalQuickAuthEnabled)
                }
                SettingsGroupDivider()
                SettingsRowContent(
                    title: "Apple biometrics fallback",
                    subtitle: "Allow Touch ID, Apple Watch, or system password if Face ID camera scan is unconfirmed."
                ) {
                    NotchPulseToggle(isOn: $settings.useAppleAuthFallback)
                }
                SettingsGroupDivider()
                SettingsRowContent(
                    title: "Terminal sudo Touch ID",
                    subtitle: authCoordinator.isSudoTouchIDConfigured
                        ? "Configured in /etc/pam.d/sudo_local (native Apple Touch ID active for sudo)."
                        : "Enable Apple's native Touch ID PAM module for sudo commands in Terminal."
                ) {
                    if authCoordinator.isSudoTouchIDConfigured {
                        Label("Enabled", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.green)
                    } else {
                        Button("Configure") {
                            Task {
                                _ = await authCoordinator.enableSudoTouchID()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
            }
        }
    }
}

typealias GeneralSettingsPage = FaceIDUnlockOptionsPage
