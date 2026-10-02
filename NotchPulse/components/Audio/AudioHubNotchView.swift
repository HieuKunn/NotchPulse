//
//  AudioHubNotchView.swift
//  NotchPulse
//
//  Created by Alexander on 2026-10-02.
//

import AppKit
import Defaults
import SwiftUI

struct AudioHubNotchView: View {
    @ObservedObject var audioManager = AudioDeviceManager.shared
    @EnvironmentObject var vm: NotchPulseViewModel

    private var activeOutputName: String {
        audioManager.defaultOutputDevice?.name ?? loc("Speakers")
    }

    private var activeInputName: String {
        audioManager.defaultInputDevice?.name ?? loc("Microphone")
    }

    var body: some View {
        VStack(spacing: 8) {
            // Header Bar
            HStack(spacing: 10) {
                // Tab switcher (Output vs Input)
                HStack(spacing: 2) {
                    Button(action: {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            audioManager.selectedTab = .output
                        }
                    }) {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(audioManager.selectedTab == .output ? .white : .secondary)
                            .frame(width: 26, height: 24)
                            .background(
                                audioManager.selectedTab == .output ?
                                    Color.white.opacity(0.18) : Color.clear
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            audioManager.selectedTab = .input
                        }
                    }) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(audioManager.selectedTab == .input ? .white : .secondary)
                            .frame(width: 26, height: 24)
                            .background(
                                audioManager.selectedTab == .input ?
                                    Color.white.opacity(0.18) : Color.clear
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(2)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                // Active Devices Breadcrumb
                HStack(spacing: 4) {
                    Image(systemName: "speaker.wave.1.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Text(activeOutputName)
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(.white.opacity(0.85))

                    Text("·")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)

                    Image(systemName: "mic.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Text(activeInputName)
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(.white.opacity(0.85))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()

                // Settings Shortcut
                Button(action: {
                    DispatchQueue.main.async {
                        SettingsWindowController.shared.showWindow()
                    }
                }) {
                    Image(systemName: "gear")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.top, 2)

            // Scrollable Content: Devices & Apps
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 10) {
                    // Devices List Section
                    VStack(spacing: 4) {
                        if audioManager.selectedTab == .output {
                            if audioManager.outputDevices.isEmpty {
                                Text(loc("No output devices found"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.vertical, 8)
                            } else {
                                ForEach(audioManager.outputDevices) { device in
                                    AudioDeviceRow(
                                        device: device,
                                        isInput: false,
                                        onSelect: {
                                            audioManager.setDefaultDevice(id: device.id, isInput: false)
                                        },
                                        onVolumeChange: { newVol in
                                            audioManager.setDeviceVolume(id: device.id, volume: newVol, isInput: false)
                                        },
                                        onMuteToggle: {
                                            audioManager.toggleDeviceMute(id: device.id, isInput: false)
                                        }
                                    )
                                }
                            }
                        } else {
                            if audioManager.inputDevices.isEmpty {
                                Text(loc("No input devices found"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.vertical, 8)
                            } else {
                                ForEach(audioManager.inputDevices) { device in
                                    AudioDeviceRow(
                                        device: device,
                                        isInput: true,
                                        onSelect: {
                                            audioManager.setDefaultDevice(id: device.id, isInput: true)
                                        },
                                        onVolumeChange: { newVol in
                                            audioManager.setDeviceVolume(id: device.id, volume: newVol, isInput: true)
                                        },
                                        onMuteToggle: {
                                            audioManager.toggleDeviceMute(id: device.id, isInput: true)
                                        }
                                    )
                                }
                            }
                        }
                    }

                    // Divider
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 1)
                        .padding(.horizontal, 4)

                    // APPS Section
                    VStack(alignment: .leading, spacing: 6) {
                        Text(loc("APPS"))
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 6)

                        if audioManager.activeApps.isEmpty {
                            Text(loc("No active audio applications"))
                                .font(.caption)
                                .foregroundStyle(.secondary.opacity(0.8))
                                .padding(.leading, 6)
                                .padding(.vertical, 4)
                        } else {
                            ForEach(audioManager.activeApps) { appItem in
                                AudioAppRow(
                                    appItem: appItem,
                                    onVolumeChange: { newVol in
                                        audioManager.setAppVolume(id: appItem.id, volume: newVol)
                                    },
                                    onMuteToggle: {
                                        audioManager.toggleAppMute(id: appItem.id)
                                    }
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 8)
            }
            .frame(maxHeight: 220)
        }
        .padding(.horizontal, 6)
        .padding(.top, 4)
        .onAppear {
            audioManager.refreshDevices()
            audioManager.refreshApps()
            vm.customOpenHeight = 290
        }
    }
}

// MARK: - Subviews: Device Row & App Row

private struct AudioDeviceRow: View {
    let device: AudioDeviceItem
    let isInput: Bool
    let onSelect: () -> Void
    let onVolumeChange: (Float) -> Void
    let onMuteToggle: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            // Icon
            Button(action: onSelect) {
                ZStack {
                    Circle()
                        .fill(device.isDefault ? Color.blue : Color.white.opacity(0.12))
                        .frame(width: 24, height: 24)

                    Image(systemName: device.iconName)
                        .font(.system(size: 11))
                        .foregroundStyle(device.isDefault ? .white : .white.opacity(0.85))
                }
            }
            .buttonStyle(.plain)

            // Name
            Button(action: onSelect) {
                Text(device.name)
                    .font(.system(size: 12, weight: device.isDefault ? .semibold : .regular))
                    .foregroundStyle(device.isDefault ? .white : .white.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            // Mute Icon
            Button(action: onMuteToggle) {
                Image(systemName: device.isMuted ? (isInput ? "mic.slash.fill" : "speaker.slash.fill") : (isInput ? "mic.fill" : "speaker.wave.2.fill"))
                    .font(.system(size: 10))
                    .foregroundStyle(device.isMuted ? Color.red.opacity(0.85) : Color.secondary)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)

            // Volume Slider
            CustomAudioSlider(
                value: Binding(
                    get: { CGFloat(device.volume) },
                    set: { onVolumeChange(Float($0)) }
                ),
                range: 0...1,
                tintColor: device.isDefault ? Color.blue : Color.white.opacity(0.7)
            )
            .frame(width: 110, height: 14)

            // Percentage Label
            Text("\(Int(round(device.volume * 100)))%")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .trailing)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            device.isDefault ?
                Color.white.opacity(0.06) : Color.clear
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct AudioAppRow: View {
    let appItem: AudioAppItem
    let onVolumeChange: (Float) -> Void
    let onMuteToggle: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            // Equalizer Bars (FineTune style minimal indicator)
            HStack(spacing: 1.5) {
                RoundedRectangle(cornerRadius: 0.5)
                    .fill(appItem.isPlaying ? Color.green : Color.gray.opacity(0.4))
                    .frame(width: 2, height: 8)
                RoundedRectangle(cornerRadius: 0.5)
                    .fill(appItem.isPlaying ? Color.yellow : Color.gray.opacity(0.4))
                    .frame(width: 2, height: 11)
                RoundedRectangle(cornerRadius: 0.5)
                    .fill(appItem.isPlaying ? Color.red : Color.gray.opacity(0.4))
                    .frame(width: 2, height: 6)
            }
            .frame(width: 10, height: 12)

            // App Icon
            Image(nsImage: appItem.icon)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

            // App Name
            Text(appItem.name)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Mute Icon
            Button(action: onMuteToggle) {
                Image(systemName: appItem.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(appItem.isMuted ? Color.red.opacity(0.85) : Color.secondary)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)

            // Volume Slider
            CustomAudioSlider(
                value: Binding(
                    get: { CGFloat(appItem.volume) },
                    set: { onVolumeChange(Float($0)) }
                ),
                range: 0...1,
                tintColor: Color.blue
            )
            .frame(width: 110, height: 14)

            // Percentage Label
            Text("\(Int(round(appItem.volume * 100)))%")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .trailing)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
    }
}

// MARK: - Minimal Clean Audio Slider

private struct CustomAudioSlider: View {
    @Binding var value: CGFloat
    var range: ClosedRange<CGFloat> = 0...1
    var tintColor: Color = .blue

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let progress = max(0, min(1, (value - range.lowerBound) / (range.upperBound - range.lowerBound)))

            ZStack(alignment: .leading) {
                // Background Track
                Capsule()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: width, height: 4)

                // Filled Track
                Capsule()
                    .fill(tintColor)
                    .frame(width: max(4, width * progress), height: 4)

                // Thumb handle
                Circle()
                    .fill(Color.white)
                    .frame(width: 10, height: 10)
                    .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
                    .offset(x: max(0, min(width - 10, width * progress - 5)))
            }
            .frame(height: height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let newProgress = max(0, min(1, gesture.location.x / width))
                        let newValue = range.lowerBound + newProgress * (range.upperBound - range.lowerBound)
                        self.value = newValue
                    }
            )
        }
    }
}
