import AppKit
import Defaults
import SwiftUI

struct AudioSettingsPage: View {
    @Default(.enableAudioHub) var enableAudioHub
    @ObservedObject var audioManager = AudioDeviceManager.shared

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $enableAudioHub) {
                    Text(loc("Enable Audio Hub"))
                        .font(.headline)
                    Text(loc("Manage audio devices, per-device volume & mute directly from the Notch."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .toggleStyle(.switch)
            }

            if enableAudioHub {
                Section(header: Text(loc("Features"))) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.title3)
                                .foregroundStyle(Color.effectiveAccent)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(loc("Quick Device Switcher"))
                                    .font(.headline)
                                Text(loc("Switch between speakers, headphones, and microphones with one click."))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Divider()

                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.title3)
                                .foregroundStyle(Color.effectiveAccent)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(loc("Per-Device Volume & Mute"))
                                    .font(.headline)
                                Text(loc("Adjust volume sliders and mute states independently for each connected audio device."))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .formStyle(.grouped)
    }
}
