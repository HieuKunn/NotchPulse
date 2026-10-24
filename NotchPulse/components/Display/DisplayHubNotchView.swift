//
//  DisplayHubNotchView.swift
//  NotchPulse
//
//  A beautiful, interactive control hub for managing Built-in & External Displays
//  with native hardware DDC/CI brightness adjustment.
//

import AppKit
import Defaults
import SwiftUI

struct DisplayHubNotchView: View {
    @ObservedObject var brightnessManager = BrightnessManager.shared
    @ObservedObject var coordinator = NotchPulseViewCoordinator.shared
    @EnvironmentObject var vm: NotchPulseViewModel

    private var displays: [DisplayTarget] {
        brightnessManager.availableDisplays()
    }

    var body: some View {
        VStack(spacing: 8) {
            // Header Bar
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.effectiveAccent)
                    
                    Text(loc("Displays"))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                // Connected summary
                HStack(spacing: 4) {
                    Image(systemName: "display.2")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Text("\(displays.count) \(displays.count > 1 ? loc("Displays Connected") : loc("Display Connected"))")
                        .font(.system(size: 10, weight: .medium))
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

            // Display List
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 6) {
                    ForEach(displays) { target in
                        DisplayRowView(target: target)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 4)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            brightnessManager.refreshAllDisplays()
            DispatchQueue.main.async {
                updateDynamicHeight()
            }
        }
        .onChange(of: coordinator.currentView) { _, newView in
            if newView == .display {
                DispatchQueue.main.async {
                    updateDynamicHeight()
                }
            }
        }
    }

    private func updateDynamicHeight() {
        guard coordinator.currentView == .display else { return }
        let targetHeight = Self.calculateHeight(displayCount: displays.count)
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            vm.customOpenHeight = targetHeight
        }
    }

    @MainActor
    static func calculateHeight(displayCount: Int? = nil) -> CGFloat {
        let count = displayCount ?? BrightnessManager.shared.availableDisplays().count
        let effectiveCount = max(1, count)

        // NotchPulseHeader (34) + spacing (8) + Header bar (28) + spacing (8) + list padding (4) = 82
        let headerHeight: CGFloat = 82
        let rowHeight: CGFloat = 48
        let spacing: CGFloat = 6
        let rowsHeight = CGFloat(effectiveCount) * rowHeight + CGFloat(max(0, effectiveCount - 1)) * spacing
        let bottomPadding: CGFloat = 10

        let total = headerHeight + rowsHeight + bottomPadding
        return min(600, max(120, total))
    }
}

// MARK: - Display Row View

private struct DisplayRowView: View {
    let target: DisplayTarget
    @ObservedObject var brightnessManager = BrightnessManager.shared
    @State private var sliderValue: CGFloat = 0.5
    @State private var isProgrammaticUpdate: Bool = false

    private var currentBrightness: Float {
        brightnessManager.brightness(for: target.id)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Display Icon
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 34, height: 34)
                
                Image(systemName: target.isBuiltin ? "laptopcomputer" : "display")
                    .font(.system(size: 15))
                    .foregroundStyle(target.isBuiltin ? Color.effectiveAccent : .white)
            }

            // Name & Badge
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(target.localizedName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    
                    Text(target.isBuiltin ? loc("Retina") : loc("Hardware DDC"))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(target.isBuiltin ? Color.effectiveAccent : Color.green.opacity(0.9))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(
                            (target.isBuiltin ? Color.effectiveAccent : Color.green)
                                .opacity(0.15)
                        )
                        .clipShape(Capsule())
                }

                // Quick Presets
                HStack(spacing: 4) {
                    ForEach([25, 50, 75, 100], id: \.self) { pct in
                        Button(action: {
                            let val = Float(pct) / 100.0
                            sliderValue = CGFloat(val)
                            brightnessManager.setBrightness(for: target.id, value: val)
                        }) {
                            Text("\(pct)%")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(Int(round(sliderValue * 100)) == pct ? Color.effectiveAccent : .secondary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.white.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(width: 170, alignment: .leading)

            // Brightness Slider
            HStack(spacing: 8) {
                Image(systemName: "sun.min")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                CustomDisplaySlider(
                    value: $sliderValue,
                    range: 0...1,
                    tintColor: Color.effectiveAccent
                )
                .frame(height: 22)

                Image(systemName: "sun.max.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            // Percentage Label
            Text("\(Int(round(sliderValue * 100)))%")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 38, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onAppear {
            sliderValue = CGFloat(currentBrightness)
        }
        .onChange(of: currentBrightness) { _, newVal in
            let newCGFloat = CGFloat(newVal)
            if abs(sliderValue - newCGFloat) > 0.005 {
                isProgrammaticUpdate = true
                sliderValue = newCGFloat
            }
        }
        .onChange(of: sliderValue) { _, newVal in
            if isProgrammaticUpdate {
                isProgrammaticUpdate = false
                return
            }
            if abs(Float(newVal) - currentBrightness) > 0.005 {
                brightnessManager.setBrightness(for: target.id, value: Float(newVal))
            }
        }
    }
}

// MARK: - Custom Display Slider with Scroll-Wheel & Dragging

private struct CustomDisplaySlider: View {
    @Binding var value: CGFloat
    var range: ClosedRange<CGFloat> = 0...1
    var tintColor: Color = .blue
    @State private var isDragging: Bool = false

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let progress = max(0, min(1, (value - range.lowerBound) / (range.upperBound - range.lowerBound)))

            ZStack(alignment: .leading) {
                // Scroll wheel listener
                SliderScrollWheelRepresentable { deltaStep in
                    let span = range.upperBound - range.lowerBound
                    let newValue = max(range.lowerBound, min(range.upperBound, value + deltaStep * span))
                    self.value = newValue
                }

                // Background Track
                Capsule()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: width, height: 5)

                // Filled Track
                Capsule()
                    .fill(tintColor)
                    .frame(width: max(5, width * progress), height: 5)

                // Thumb handle
                Circle()
                    .fill(Color.white)
                    .frame(width: 12, height: 12)
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                    .offset(x: max(0, min(width - 12, width * progress - 6)))
            }
            .frame(height: height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        isDragging = true
                        let newProgress = max(0, min(1, gesture.location.x / width))
                        let newValue = range.lowerBound + newProgress * (range.upperBound - range.lowerBound)
                        self.value = newValue
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
            .animation(isDragging ? nil : .easeOut(duration: 0.08), value: progress)
        }
    }
}
