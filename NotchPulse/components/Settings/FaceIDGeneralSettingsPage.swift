import OSLog
import SwiftUI

struct FaceIDUnlockOptionsPage: View {
    @Bindable private var coordinator = NotchPulseFaceUnlockCoordinator.shared
    @Bindable private var settings = NotchPulseFaceIDSettings.shared

    var body: some View {
        Section {
            Toggle(loc("Enable Face Unlock"), isOn: $coordinator.isEnabled)

            if coordinator.isEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    Text(loc("Unlock Triggers"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    UnlockTriggerPicker(selection: $settings.unlockTriggers, isEnabled: coordinator.isEnabled)
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text(loc("Face Unlock"))
        } footer: {
            Text(loc("Uses on-device face recognition with your camera to unlock by entering your password. NotchPulse processes all facial recognition strictly locally and does not bypass macOS system security."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Section {
            Toggle(loc("Retry again on Hover"), isOn: $settings.retryOnHover)
                .disabled(!coordinator.isEnabled)

            Toggle(loc("Auto retry again once"), isOn: $settings.autoRetryOnce)
                .disabled(!coordinator.isEnabled)

            Toggle(loc("Haptic feedback"), isOn: $settings.hapticFeedbackEnabled)
                .disabled(!coordinator.isEnabled)

            HStack {
                Text(loc("Face detection duration"))
                Spacer()
                Text("\(settings.faceDetectionSeconds)s")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .disabled(!coordinator.isEnabled)

            Slider(
                value: Binding(
                    get: { Double(settings.faceDetectionSeconds) },
                    set: { settings.faceDetectionSeconds = Int($0.rounded()) }
                ),
                in: Double(NotchPulseFaceIDSettings.faceDetectionRange.lowerBound)...Double(NotchPulseFaceIDSettings.faceDetectionRange.upperBound),
                step: 1
            )
            .disabled(!coordinator.isEnabled)
        } header: {
            Text(loc("Behaviour"))
        } footer: {
            if !coordinator.isEnabled {
                Text(loc("Enable Face Unlock above to configure recognition behaviour."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        Section {
            Toggle(loc("Show animation"), isOn: $settings.showUnlockAnimation)
                .disabled(!coordinator.isEnabled)

            if settings.showUnlockAnimation {
                UnlockAnimationPicker(
                    selection: $settings.unlockAnimationStyle,
                    isEnabled: coordinator.isEnabled && settings.showUnlockAnimation
                )
                .padding(.vertical, 4)
            }
        } header: {
            Text(loc("Animation"))
        }
    }
}

typealias GeneralSettingsPage = FaceIDUnlockOptionsPage
