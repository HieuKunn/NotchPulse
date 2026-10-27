import AppKit
import Defaults
import SwiftUI

struct DisplaySettingsPage: View {
    @Default(.enableDisplayHub) var enableDisplayHub
    @ObservedObject var brightnessManager = BrightnessManager.shared

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $enableDisplayHub) {
                    Text(loc("Enable Display Hub"))
                        .font(.headline)
                    Text(loc("Hardware DDC/CI brightness control for external monitors directly from the Notch."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .toggleStyle(.switch)
            }

            if enableDisplayHub {
                Section(header: Text(loc("Connected Displays"))) {
                    ForEach(brightnessManager.availableDisplays()) { target in
                        HStack {
                            Image(systemName: target.isBuiltin ? "laptopcomputer" : "display")
                                .foregroundStyle(Color.effectiveAccent)
                                .frame(width: 20)
                            Text(target.localizedName)
                                .font(.body)
                            Spacer()
                            Text(target.isBuiltin ? loc("Retina") : loc("Hardware DDC"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section(header: Text(loc("Features"))) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "sun.max.fill")
                                .font(.title3)
                                .foregroundStyle(Color.effectiveAccent)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(loc("Hardware DDC/CI Control"))
                                    .font(.headline)
                                Text(loc("Directly adjust backlight of third-party external monitors (Dell, LG, Asus, Samsung, HKC, etc.)."))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Divider()

                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "slider.horizontal.below.rectangle")
                                .font(.title3)
                                .foregroundStyle(Color.effectiveAccent)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(loc("Per-Display Brightness Sliders"))
                                    .font(.headline)
                                Text(loc("Independent sliders with scroll-wheel fine-tuning and quick preset buttons."))
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
