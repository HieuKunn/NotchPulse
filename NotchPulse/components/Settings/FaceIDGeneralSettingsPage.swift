import OSLog
import SwiftUI

struct FaceIDUnlockOptionsPage: View {
    @Bindable private var coordinator = NotchPulseFaceUnlockCoordinator.shared
    @Bindable private var settings = NotchPulseFaceIDSettings.shared

    var body: some View {
        SettingsGroup {
            SettingsRowContent(title: loc("Enable Face Unlock")) {
                NotchPulseToggle(isOn: $coordinator.isEnabled)
            }
            SettingsGroupDivider()
            UnlockTriggerPicker(selection: $settings.unlockTriggers, isEnabled: coordinator.isEnabled)
        }

        VStack(alignment: .leading, spacing: 6) {
            SettingsSectionTitle(text: loc("Behaviour"))
            SettingsGroup {
                SettingsRowContent(title: loc("Retry again on Hover")) {
                    NotchPulseToggle(isOn: $settings.retryOnHover)
                }
                SettingsGroupDivider()
                SettingsRowContent(title: loc("Auto retry again once")) {
                    NotchPulseToggle(isOn: $settings.autoRetryOnce)
                }
                SettingsGroupDivider()
                SettingsRowContent(title: loc("Haptic feedback")) {
                    NotchPulseToggle(isOn: $settings.hapticFeedbackEnabled)
                }
                SettingsGroupDivider()
                SettingsSteppedSliderRowContent(
                    title: loc("Face detection duration"),
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
            SettingsSectionTitle(text: loc("Animation"))
            SettingsGroup {
                SettingsRowContent(title: loc("Show animation")) {
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
}
