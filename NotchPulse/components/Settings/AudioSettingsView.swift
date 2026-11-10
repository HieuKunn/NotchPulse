import AppKit
import Defaults
import SwiftUI

struct AudioSettingsView: View {
    @Environment(\.settingsHighlightedId) private var highlightedId
    @Default(.enableAudioHub) var enableAudioHub
    @ObservedObject var audioManager = AudioDeviceManager.shared

    var body: some View {
        Form {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc("Enable Audio Hub"))
                            .font(.headline)
                        Text(loc("Manage audio devices, per-device volume & mute directly from the Notch."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 40)
                    Defaults.Toggle("", key: .enableAudioHub)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }
            .id("audio_hub")
            .searchHighlight(highlightedId == "audio_hub")

            if enableAudioHub {
                Section(header: Text(loc("Features"))) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(loc("Quick Device Switcher"))
                                    .font(.subheadline.weight(.medium))
                                Text(loc("Switch between speakers, headphones, and microphones with one click."))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(loc("Per-Device Volume & Mute"))
                                    .font(.subheadline.weight(.medium))
                                Text(loc("Adjust volume sliders and mute states independently for each connected audio device."))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .id("audio_routing")
                .searchHighlight(highlightedId == "audio_routing")
            }
        }
        .formStyle(.grouped)
        .accentColor(.effectiveAccent)
    }
}

