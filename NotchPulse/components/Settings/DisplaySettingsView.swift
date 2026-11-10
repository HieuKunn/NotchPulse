import AppKit
import Defaults
import SwiftUI

struct DisplaySettingsView: View {
    @Environment(\.settingsHighlightedId) private var highlightedId
    @Default(.enableDisplayHub) var enableDisplayHub
    @ObservedObject var brightnessManager = BrightnessManager.shared

    var body: some View {
        Form {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc("Enable Display Hub"))
                            .font(.headline)
                        Text(loc("Hardware DDC/CI brightness control for external monitors directly from the Notch."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 40)
                    Defaults.Toggle("", key: .enableDisplayHub)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }
            .id("display_hub")
            .searchHighlight(highlightedId == "display_hub")

            if enableDisplayHub {
                Section(header: Text(loc("Connected Displays")).id("display_monitors")) {
                    ForEach(brightnessManager.availableDisplays()) { target in
                        HStack {
                            Image(systemName: target.isBuiltin ? "laptopcomputer" : "display")
                                .foregroundStyle(.secondary)
                                .frame(width: 20)
                            Text(target.localizedName)
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Text(target.isBuiltin ? loc("Retina") : loc("Hardware DDC"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .id("display_monitors")
                .searchHighlight(highlightedId == "display_monitors")

                Section(header: Text(loc("Features")).id("display_features")) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "sun.max.fill")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(loc("Hardware DDC/CI Control"))
                                    .font(.subheadline.weight(.medium))
                                Text(loc("Directly adjust backlight of third-party external monitors (Dell, LG, Asus, Samsung, HKC, etc.)."))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "slider.horizontal.below.rectangle")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(loc("Per-Display Brightness Sliders"))
                                    .font(.subheadline.weight(.medium))
                                Text(loc("Independent sliders with scroll-wheel fine-tuning and quick preset buttons."))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .id("display_features")
                .searchHighlight(highlightedId == "display_features")
            }
        }
        .formStyle(.grouped)
        .accentColor(.effectiveAccent)
    }
}

