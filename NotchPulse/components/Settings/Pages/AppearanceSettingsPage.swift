import AVFoundation
import AppKit
import Defaults
import SwiftUI

struct AppearanceSettingsPage: View {
    @ObservedObject var coordinator = NotchPulseViewCoordinator.shared
    @Default(.mirrorShape) var mirrorShape
    @Default(.sliderColor) var sliderColor
    @Default(.useMusicVisualizer) var useMusicVisualizer
    @Default(.customVisualizers) var customVisualizers
    @Default(.selectedVisualizer) var selectedVisualizer
    @Default(.settingsIconInNotch) var settingsIconInNotch
    @Default(.coloredSpectrogram) var coloredSpectrogram
    @Default(.playerColorTinting) var playerColorTinting
    @Default(.lightingEffect) var lightingEffect
    @Default(.showMirror) var showMirror

    @State private var selectedListVisualizer: CustomVisualizer? = nil
    @State private var isPresented: Bool = false
    @State private var name: String = ""
    @State private var url: String = ""
    @State private var speed: CGFloat = 1.0

    var body: some View {
        Form {
            Section {
                Toggle(loc("Always show tabs"), isOn: $coordinator.alwaysShowTabs)
                Toggle(loc("Show settings icon in notch"), isOn: $settingsIconInNotch)
            } header: {
                Text(loc("General"))
            }

            Section {
                Toggle(loc("Colored spectrogram"), isOn: $coloredSpectrogram)
                Toggle(loc("Player tinting"), isOn: $playerColorTinting)
                Toggle(loc("Enable blur effect behind album art"), isOn: $lightingEffect)
                Picker(loc("Slider color"), selection: $sliderColor) {
                    ForEach(SliderColorEnum.allCases, id: \.self) { option in
                        Text(loc(option.rawValue)).tag(option)
                    }
                }
            } header: {
                Text(loc("Media"))
            }

            Section {
                Toggle(
                    loc("Use music visualizer spectrogram"),
                    isOn: $useMusicVisualizer.animation()
                )
                .disabled(true)

                if !useMusicVisualizer {
                    if !customVisualizers.isEmpty {
                        Picker(loc("Selected animation"), selection: $selectedVisualizer) {
                            ForEach(customVisualizers, id: \.self) { visualizer in
                                Text(visualizer.name).tag(visualizer as CustomVisualizer?)
                            }
                        }
                    } else {
                        HStack {
                            Text(loc("Selected animation"))
                            Spacer()
                            Text(loc("No custom animation available"))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                HStack {
                    Text(loc("Custom music live activity animation"))
                    customBadge(text: loc("Coming soon"))
                }
            }

            Section {
                List {
                    ForEach(customVisualizers, id: \.self) { visualizer in
                        HStack {
                            LottieView(
                                url: visualizer.url, speed: visualizer.speed,
                                loopMode: .loop
                            )
                            .frame(width: 30, height: 30, alignment: .center)
                            Text(visualizer.name)
                            Spacer(minLength: 0)
                            if selectedVisualizer == visualizer {
                                Text(loc("selected"))
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.secondary)
                                    .padding(.trailing, 8)
                            }
                        }
                        .padding(.vertical, 2)
                        .background(
                            selectedListVisualizer == visualizer ? Color.effectiveAccent.opacity(0.15) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if selectedListVisualizer == visualizer {
                                selectedListVisualizer = nil
                            } else {
                                selectedListVisualizer = visualizer
                            }
                        }
                    }
                }
                .frame(minHeight: 120)
                .actionBar {
                    HStack(spacing: 8) {
                        Button {
                            name = ""
                            url = ""
                            speed = 1.0
                            isPresented.toggle()
                        } label: {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.borderless)

                        Divider()

                        Button {
                            if let visualizer = selectedListVisualizer {
                                selectedListVisualizer = nil
                                if let idx = customVisualizers.firstIndex(of: visualizer) {
                                    customVisualizers.remove(at: idx)
                                }
                                if visualizer == selectedVisualizer && !customVisualizers.isEmpty {
                                    selectedVisualizer = customVisualizers[0]
                                }
                            }
                        } label: {
                            Image(systemName: "minus")
                        }
                        .buttonStyle(.borderless)
                        .disabled(selectedListVisualizer == nil)
                    }
                }
                .overlay {
                    if customVisualizers.isEmpty {
                        Text(loc("No custom visualizer"))
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 22)
                    }
                }
                .sheet(isPresented: $isPresented) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(loc("Add new visualizer"))
                            .font(.headline)
                        TextField(loc("Name"), text: $name)
                        TextField(loc("Lottie JSON URL"), text: $url)
                        HStack {
                            Text(loc("Speed"))
                            Spacer(minLength: 80)
                            Text("\(speed, specifier: "%.1f")s")
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(.secondary)
                            Slider(value: $speed, in: 0...2, step: 0.1)
                        }
                        HStack {
                            Button(loc("Cancel")) {
                                isPresented.toggle()
                            }
                            .buttonStyle(.bordered)

                            Spacer()

                            Button(loc("Add")) {
                                if let validURL = URL(string: url) {
                                    let visualizer = CustomVisualizer(
                                        UUID: UUID(),
                                        name: name,
                                        url: validURL,
                                        speed: speed
                                    )
                                    if !customVisualizers.contains(visualizer) {
                                        customVisualizers.append(visualizer)
                                    }
                                }
                                isPresented.toggle()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(name.isEmpty || url.isEmpty)
                        }
                    }
                    .padding(20)
                    .frame(width: 380)
                }
            } header: {
                HStack(spacing: 4) {
                    Text(loc("Custom vizualizers (Lottie)"))
                    if !customVisualizers.isEmpty {
                        Text("– \(customVisualizers.count)")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Toggle(loc("Enable NotchPulse mirror"), isOn: $showMirror)
                    .disabled(!checkVideoInput())

                Picker(loc("Mirror shape"), selection: $mirrorShape) {
                    Text(loc("Circle")).tag(MirrorShapeEnum.circle)
                    Text(loc("Square")).tag(MirrorShapeEnum.rectangle)
                }
                .disabled(!showMirror)
            } header: {
                Text(loc("Additional features"))
            }
        }
        .formStyle(.grouped)
    }

    private func checkVideoInput() -> Bool {
        return AVCaptureDevice.default(for: .video) != nil
    }
}
