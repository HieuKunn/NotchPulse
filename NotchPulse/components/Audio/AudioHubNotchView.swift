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
    @ObservedObject var coordinator = NotchPulseViewCoordinator.shared
    @EnvironmentObject var vm: NotchPulseViewModel

    @AppStorage("NotchPulse_AudioHubAppsExpanded") private var isAppsExpanded: Bool = true

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
                // Tab switcher (Output vs Input) with full cell hit-testing
                HStack(spacing: 2) {
                    Button(action: {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            audioManager.selectedTab = .output
                            updateDynamicHeight()
                        }
                    }) {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(audioManager.selectedTab == .output ? .white : .secondary)
                            .frame(width: 34, height: 26)
                            .background(
                                audioManager.selectedTab == .output ?
                                    Color.white.opacity(0.18) : Color.clear
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            audioManager.selectedTab = .input
                            updateDynamicHeight()
                        }
                    }) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(audioManager.selectedTab == .input ? .white : .secondary)
                            .frame(width: 34, height: 26)
                            .background(
                                audioManager.selectedTab == .input ?
                                    Color.white.opacity(0.18) : Color.clear
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .contentShape(Rectangle())
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
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.top, 2)

            // Content: Devices & Apps
            VStack(spacing: 8) {
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

                    // APPS Section (Collapsible)
                    VStack(alignment: .leading, spacing: 6) {
                        Button(action: {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                isAppsExpanded.toggle()
                                updateDynamicHeight()
                            }
                        }) {
                            HStack(spacing: 6) {
                                Text(loc("APPS"))
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(.secondary)

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.secondary.opacity(0.85))
                                    .rotationEffect(.degrees(isAppsExpanded ? 90 : 0))

                                if !audioManager.activeApps.isEmpty {
                                    Text("\(audioManager.activeApps.count)")
                                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(.white.opacity(0.65))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(Color.white.opacity(0.1))
                                        .clipShape(Capsule())
                                }

                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                        }
                        .buttonStyle(.plain)

                        if isAppsExpanded {
                            if audioManager.activeApps.isEmpty {
                                Text(loc("No active audio applications"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary.opacity(0.8))
                                    .padding(.leading, 8)
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
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 6)
            }
            .padding(.horizontal, 10)
            .padding(.top, 4)
            .frame(width: max(560, min(860, Defaults[.notchOpenWidth] - 28)))
        .onAppear {
            audioManager.refreshDevices()
            audioManager.refreshApps()
            updateDynamicHeight()
        }
        .onDisappear {
            if coordinator.currentView != .audio {
                vm.customOpenHeight = nil
            }
        }
        .onChange(of: isAppsExpanded) { _ in
            updateDynamicHeight()
        }
        .onChange(of: audioManager.selectedTab) { _ in
            updateDynamicHeight()
        }
        .onChange(of: audioManager.outputDevices) { _ in
            updateDynamicHeight()
        }
        .onChange(of: audioManager.inputDevices) { _ in
            updateDynamicHeight()
        }
        .onChange(of: audioManager.activeApps) { _ in
            updateDynamicHeight()
        }
    }

    static func calculateHeight(
        selectedTab: AudioHubTab = AudioDeviceManager.shared.selectedTab,
        isAppsExpanded: Bool = (UserDefaults.standard.object(forKey: "NotchPulse_AudioHubAppsExpanded") as? Bool) ?? true
    ) -> CGFloat {
        let topBarOffset: CGFloat = 48
        let headerBarHeight: CGFloat = 32
        let spacing: CGFloat = 8
        let devicesCount = selectedTab == .output ?
            max(1, AudioDeviceManager.shared.outputDevices.count) :
            max(1, AudioDeviceManager.shared.inputDevices.count)
        let devicesHeight = CGFloat(devicesCount) * 38
        let dividerHeight: CGFloat = 17
        let appsHeaderHeight: CGFloat = 28

        let appsListHeight: CGFloat
        if isAppsExpanded {
            let activeCount = AudioDeviceManager.shared.activeApps.count
            if activeCount == 0 {
                appsListHeight = 28
            } else {
                appsListHeight = CGFloat(activeCount) * 34
            }
        } else {
            appsListHeight = 0
        }

        let bottomPadding: CGFloat = 24
        let total = topBarOffset + headerBarHeight + spacing + devicesHeight + dividerHeight + appsHeaderHeight + appsListHeight + bottomPadding
        return min(560, max(140, total))
    }

    private func updateDynamicHeight() {
        let target = Self.calculateHeight(selectedTab: audioManager.selectedTab, isAppsExpanded: isAppsExpanded)
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            vm.customOpenHeight = target
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

    private var isEffectivelyMuted: Bool {
        device.isMuted || device.volume <= 0.001
    }

    var body: some View {
        HStack(spacing: 8) {
            // Icon & Name tap area (expands across left side)
            Button(action: onSelect) {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(device.isDefault ? Color.blue : Color.white.opacity(0.12))
                            .frame(width: 24, height: 24)

                        Image(systemName: device.iconName)
                            .font(.system(size: 11))
                            .foregroundStyle(device.isDefault ? .white : .white.opacity(0.85))
                    }

                    Text(device.name)
                        .font(.system(size: 12, weight: device.isDefault ? .semibold : .regular))
                        .foregroundStyle(device.isDefault ? .white : .white.opacity(0.85))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Mute Icon
            Button(action: onMuteToggle) {
                Image(systemName: isEffectivelyMuted ? (isInput ? "mic.slash.fill" : "speaker.slash.fill") : (isInput ? "mic.fill" : "speaker.wave.2.fill"))
                    .font(.system(size: 10))
                    .foregroundStyle(isEffectivelyMuted ? Color.red.opacity(0.9) : Color.white.opacity(0.9))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Volume Slider (supports drag & scroll-wheel)
            CustomAudioSlider(
                value: Binding(
                    get: { CGFloat(device.volume) },
                    set: { onVolumeChange(Float($0)) }
                ),
                range: 0...1,
                tintColor: device.isDefault ? Color.blue : Color.white.opacity(0.7)
            )
            .frame(width: 100, height: 16)

            // Percentage Label
            Text("\(Int(round(device.volume * 100)))%")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            device.isDefault ?
                Color.white.opacity(0.08) : Color.clear
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct AudioAppRow: View {
    let appItem: AudioAppItem
    let onVolumeChange: (Float) -> Void
    let onMuteToggle: () -> Void

    private var isEffectivelyMuted: Bool {
        appItem.isMuted || appItem.volume <= 0.001
    }

    var body: some View {
        HStack(spacing: 8) {
            // Equalizer Bars (only if playing media)
            if appItem.isPlaying {
                HStack(spacing: 1.5) {
                    RoundedRectangle(cornerRadius: 0.5)
                        .fill(Color.green)
                        .frame(width: 2, height: 8)
                    RoundedRectangle(cornerRadius: 0.5)
                        .fill(Color.yellow)
                        .frame(width: 2, height: 11)
                    RoundedRectangle(cornerRadius: 0.5)
                        .fill(Color.red)
                        .frame(width: 2, height: 6)
                }
                .frame(width: 10, height: 12)
            }

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
                Image(systemName: isEffectivelyMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(isEffectivelyMuted ? Color.red.opacity(0.9) : Color.white.opacity(0.9))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Volume Slider (supports drag & scroll-wheel + 200% boost for web/apps)
            CustomAudioSlider(
                value: Binding(
                    get: { CGFloat(appItem.volume) },
                    set: { onVolumeChange(Float($0)) }
                ),
                range: 0...2,
                tintColor: appItem.volume > 1.0 ? Color.orange : Color.blue
            )
            .frame(width: 100, height: 16)

            // Percentage Label (shows up to 200% with boost color)
            Text("\(Int(round(appItem.volume * 100)))%")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(appItem.volume > 1.0 ? Color.orange : Color.secondary)
                .frame(width: 36, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
    }
}

// MARK: - Minimal Clean Audio Slider with Scroll-Wheel & Fine-Tuning Support

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
                // Scroll wheel listener covering full slider area
                SliderScrollWheelRepresentable { deltaStep in
                    let span = range.upperBound - range.lowerBound
                    let newValue = max(range.lowerBound, min(range.upperBound, value + deltaStep * span))
                    self.value = newValue
                }

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

private struct SliderScrollWheelRepresentable: NSViewRepresentable {
    var onScroll: (CGFloat) -> Void

    func makeNSView(context: Context) -> SliderScrollWheelNSView {
        let view = SliderScrollWheelNSView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: SliderScrollWheelNSView, context: Context) {
        nsView.onScroll = onScroll
    }
}

private final class SliderScrollWheelNSView: NSView {
    var onScroll: ((CGFloat) -> Void)?
    private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            startMonitoring()
        } else {
            stopMonitoring()
        }
    }

    private func startMonitoring() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
            guard let self = self, let win = self.window, event.window === win else { return event }
            let pointInWindow = event.locationInWindow
            let pointInView = self.convert(pointInWindow, from: nil)

            if self.bounds.contains(pointInView) {
                let delta = event.scrollingDeltaY
                if abs(delta) > 0.001 {
                    let isFineTune = event.modifierFlags.contains(.shift) || event.modifierFlags.contains(.option)
                    let step: CGFloat
                    if event.hasPreciseScrollingDeltas {
                        step = delta * (isFineTune ? 0.001 : 0.004)
                    } else {
                        step = (delta > 0 ? 1.0 : -1.0) * (isFineTune ? 0.01 : 0.03)
                    }
                    self.onScroll?(step)
                    return nil // Intercept & consume so the notch/page doesn't scroll
                }
            }
            return event
        }
    }

    private func stopMonitoring() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    deinit {
        stopMonitoring()
    }
}
