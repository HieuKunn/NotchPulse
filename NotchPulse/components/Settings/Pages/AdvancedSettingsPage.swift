import AppKit
import Defaults
import SwiftUI

struct AdvancedSettingsPage: View {
    @Default(.useCustomAccentColor) var useCustomAccentColor
    @Default(.customAccentColorData) var customAccentColorData
    @Default(.showOnLockScreen) var showOnLockScreen
    @Default(.hideFromScreenRecording) var hideFromScreenRecording
    @Default(.cornerRadiusScaling) var cornerRadiusScaling
    @Default(.hideTitleBar) var hideTitleBar

    @State private var customAccentColor: Color = .accentColor
    @State private var selectedPresetColor: PresetAccentColor? = nil
    let icons: [String] = ["logo2"]
    @State private var selectedIcon: String = "logo2"

    enum PresetAccentColor: String, CaseIterable, Identifiable {
        case blue = "Blue"
        case purple = "Purple"
        case pink = "Pink"
        case red = "Red"
        case orange = "Orange"
        case yellow = "Yellow"
        case green = "Green"
        case graphite = "Graphite"

        var id: String { self.rawValue }

        var color: Color {
            switch self {
            case .blue: return .blue
            case .purple: return .purple
            case .pink: return .pink
            case .red: return .red
            case .orange: return .orange
            case .yellow: return .yellow
            case .green: return .green
            case .graphite: return .gray
            }
        }
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    Picker(loc("Accent color"), selection: $useCustomAccentColor) {
                        Text(loc("System")).tag(false)
                        Text(loc("Custom")).tag(true)
                    }
                    .pickerStyle(.segmented)

                    if !useCustomAccentColor {
                        HStack(spacing: 12) {
                            AccentCircleButton(
                                isSelected: true,
                                color: .accentColor,
                                isSystemDefault: true
                            ) {}

                            VStack(alignment: .leading, spacing: 2) {
                                Text(loc("Using System Accent"))
                                    .font(.body)
                                Text(loc("Your macOS system accent color"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(loc("Color Presets"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

                            HStack(spacing: 12) {
                                ForEach(PresetAccentColor.allCases) { preset in
                                    AccentCircleButton(
                                        isSelected: selectedPresetColor == preset,
                                        color: preset.color
                                    ) {
                                        selectedPresetColor = preset
                                        customAccentColor = preset.color
                                        saveCustomColor(preset.color)
                                        forceUiUpdate()
                                    }
                                }
                                Spacer()
                            }

                            Divider()
                                .padding(.vertical, 2)

                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(loc("Pick a Color"))
                                        .font(.body)
                                    Text(loc("Choose any color"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                ColorPicker(selection: Binding(
                                    get: { customAccentColor },
                                    set: { newColor in
                                        customAccentColor = newColor
                                        selectedPresetColor = nil
                                        saveCustomColor(newColor)
                                        forceUiUpdate()
                                    }
                                ), supportsOpacity: false) {
                                    EmptyView()
                                }
                                .labelsHidden()
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text(loc("Accent color"))
            } footer: {
                Text(loc("Choose between your system accent color or customize it with your own selection."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .onAppear {
                initializeAccentColorState()
            }

            Section {
                Toggle(loc("Corner radius scaling"), isOn: $cornerRadiusScaling)
            } header: {
                Text(loc("Window Appearance"))
            }

            Section {
                HStack {
                    ForEach(icons, id: \.self) { icon in
                        Spacer()
                        VStack(spacing: 6) {
                            Image(icon)
                                .resizable()
                                .frame(width: 72, height: 72)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .strokeBorder(
                                            icon == selectedIcon ? Color.effectiveAccent : .clear,
                                            lineWidth: 2
                                        )
                                )

                            Text(loc("Default"))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(icon == selectedIcon ? Color.effectiveAccent : .secondary)
                        }
                        Spacer()
                    }
                }
                .padding(.vertical, 4)
            } header: {
                HStack(spacing: 6) {
                    Text(loc("App icon"))
                    customBadge(text: loc("Coming soon"))
                }
            }

            Section {
                Toggle(loc("Hide title bar"), isOn: $hideTitleBar)
                Toggle(loc("Show notch on lock screen"), isOn: $showOnLockScreen)
                Toggle(loc("Hide from screen recording"), isOn: $hideFromScreenRecording)
            } header: {
                Text(loc("Window Behavior"))
            }
        }
        .formStyle(.grouped)
        .onAppear {
            loadCustomColor()
        }
    }

    private func forceUiUpdate() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Notification.Name("AccentColorChanged"), object: nil)
        }
    }

    private func saveCustomColor(_ color: Color) {
        let nsColor = NSColor(color)
        if let colorData = try? NSKeyedArchiver.archivedData(withRootObject: nsColor, requiringSecureCoding: false) {
            Defaults[.customAccentColorData] = colorData
            forceUiUpdate()
        }
    }

    private func loadCustomColor() {
        if let colorData = Defaults[.customAccentColorData],
           let nsColor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: colorData) {
            customAccentColor = Color(nsColor: nsColor)

            selectedPresetColor = nil
            for preset in PresetAccentColor.allCases {
                if colorsAreEqual(Color(nsColor: nsColor), preset.color) {
                    selectedPresetColor = preset
                    break
                }
            }
        }
    }

    private func colorsAreEqual(_ color1: Color, _ color2: Color) -> Bool {
        let nsColor1 = NSColor(color1).usingColorSpace(.sRGB) ?? NSColor(color1)
        let nsColor2 = NSColor(color2).usingColorSpace(.sRGB) ?? NSColor(color2)

        return abs(nsColor1.redComponent - nsColor2.redComponent) < 0.01 &&
               abs(nsColor1.greenComponent - nsColor2.greenComponent) < 0.01 &&
               abs(nsColor1.blueComponent - nsColor2.blueComponent) < 0.01
    }

    private func initializeAccentColorState() {
        if !useCustomAccentColor {
            selectedPresetColor = nil
        } else {
            loadCustomColor()
        }
    }
}

// MARK: - Accent Circle Button Component
struct AccentCircleButton: View {
    let isSelected: Bool
    let color: Color
    var isSystemDefault: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 28, height: 28)

                Circle()
                    .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                    .frame(width: 28, height: 28)

                if isSelected {
                    Circle()
                        .strokeBorder(Color.white, lineWidth: 2)
                        .frame(width: 22, height: 22)
                }
            }
        }
        .buttonStyle(.plain)
        .help(isSystemDefault ? loc("Your macOS system accent color") : "")
    }
}
