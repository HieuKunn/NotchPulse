//
//  StatsView.swift
//  NotchPulse
//
//  Created for NotchPulse - System Monitor Feature (Apple Activity Monitor Style)
//

import Defaults
import SwiftUI

struct AppleActivityGraphView: View {
    let data: [Double]
    var secondaryData: [Double]? = nil
    let color: Color
    var secondaryColor: Color = .orange
    var maxVal: Double = 100.0
    var referenceFraction: Double = 0.5
    var showCeilingGuide: Bool = true
    var isSolidFill: Bool = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let count = max(1, data.count)
            let step = count > 1 ? w / CGFloat(count - 1) : w


            ZStack {
                // macOS Activity Monitor dark container background
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black.opacity(0.40))

                // Apple-style horizontal reference grid line
                Path { path in
                    let yRef = h * CGFloat(1.0 - referenceFraction)
                    path.move(to: CGPoint(x: 0, y: yRef))
                    path.addLine(to: CGPoint(x: w, y: yRef))
                }
                .stroke(Color.white.opacity(0.18), lineWidth: 0.8)

                if showCeilingGuide {
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: 1.5))
                        path.addLine(to: CGPoint(x: w, y: 1.5))
                    }
                    .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                }

                // Stacked chart if secondaryData is provided
                if let sec = secondaryData, sec.count == data.count {
                    // Total CPU fill in primary color
                    Path { path in
                        guard !data.isEmpty else { return }
                        path.move(to: CGPoint(x: 0, y: h))
                        for (i, val) in data.enumerated() {
                            let clamped = max(0.0, min(maxVal, val))
                            let x = CGFloat(i) * step
                            let y = h - (CGFloat(clamped / maxVal) * (h - 2))
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                        path.addLine(to: CGPoint(x: CGFloat(data.count - 1) * step, y: h))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.56), color.opacity(0.28)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    // System CPU fill in secondary color
                    Path { path in
                        guard !sec.isEmpty else { return }
                        path.move(to: CGPoint(x: 0, y: h))
                        for (i, val) in sec.enumerated() {
                            let clamped = max(0.0, min(maxVal, val))
                            let x = CGFloat(i) * step
                            let y = h - (CGFloat(clamped / maxVal) * (h - 2))
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                        path.addLine(to: CGPoint(x: CGFloat(sec.count - 1) * step, y: h))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [secondaryColor.opacity(0.65), secondaryColor.opacity(0.35)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    // System stroke line
                    Path { path in
                        guard !sec.isEmpty else { return }
                        for (i, val) in sec.enumerated() {
                            let clamped = max(0.0, min(maxVal, val))
                            let x = CGFloat(i) * step
                            let y = h - (CGFloat(clamped / maxVal) * (h - 2))
                            if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                        }
                    }
                    .stroke(secondaryColor.opacity(0.95), style: StrokeStyle(lineWidth: 1.0, lineCap: .round, lineJoin: .round))

                    // Total CPU stroke line
                    Path { path in
                        guard !data.isEmpty else { return }
                        for (i, val) in data.enumerated() {
                            let clamped = max(0.0, min(maxVal, val))
                            let x = CGFloat(i) * step
                            let y = h - (CGFloat(clamped / maxVal) * (h - 2))
                            if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                        }
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
                } else {
                    // Single series (RAM Memory Pressure or GPU)
                    Path { path in
                        guard !data.isEmpty else { return }
                        path.move(to: CGPoint(x: 0, y: h))
                        for (i, val) in data.enumerated() {
                            let clamped = max(0.0, min(maxVal, val))
                            let x = CGFloat(i) * step
                            let y = h - (CGFloat(clamped / maxVal) * (h - 2))
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                        path.addLine(to: CGPoint(x: CGFloat(data.count - 1) * step, y: h))
                        path.closeSubpath()
                    }
                    .fill(
                        isSolidFill
                            ? LinearGradient(colors: [color.opacity(0.85), color.opacity(0.68)], startPoint: .top, endPoint: .bottom)
                            : LinearGradient(colors: [color.opacity(0.58), color.opacity(0.30)], startPoint: .top, endPoint: .bottom)
                    )

                    // Line stroke
                    Path { path in
                        guard !data.isEmpty else { return }
                        for (i, val) in data.enumerated() {
                            let clamped = max(0.0, min(maxVal, val))
                            let x = CGFloat(i) * step
                            let y = h - (CGFloat(clamped / maxVal) * (h - 2))
                            if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                        }
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
                }
            }
            .drawingGroup()
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
        }
    }
}

typealias SparklineView = AppleActivityGraphView

struct StatsView: View {
    @ObservedObject var monitor = SystemMonitorManager.shared
    @Default(.systemMonitorShowProcesses) var showProcesses
    @EnvironmentObject var vm: NotchPulseViewModel

    private enum ExpandedMetric { case cpu, ram }
    @State private var expandedMetric: ExpandedMetric?
    @State private var isThermalExpanded: Bool = false

    // Keep the 3 cards at identical constant height both when collapsed and when expanded
    private let cardRowHeight: CGFloat = 118

    var body: some View {
        GeometryReader { geo in
            let isDynamicIsland = Defaults[.notchStyle] == .dynamicIsland
            let horizontalMargin: CGFloat = isDynamicIsland ? 10 : 20
            let spacing: CGFloat = 10
            let availableWidth = max(0, geo.size.width - (horizontalMargin * 2) - (spacing * 2))
            // CPU: 1/3 (33.33%)
            let cpuWidth = availableWidth * (1.0 / 3.0)
            // RAM + GPU: 2/3 (66.67%)
            let ramGpuWidth = availableWidth * (2.0 / 3.0)
            // RAM: 60% of 2/3 (= 40% of total)
            let ramWidth = ramGpuWidth * 0.60
            // GPU: 40% of 2/3 (= 26.67% of total)
            let gpuWidth = ramGpuWidth * 0.40

            VStack(spacing: 8) {
                // The 3 Cards Row (always kept intact and identical in size)
                HStack(spacing: spacing) {
                    cpuCard
                        .frame(width: cpuWidth, height: cardRowHeight)

                    ramCard
                        .frame(width: ramWidth, height: cardRowHeight)

                    gpuCard
                        .frame(width: gpuWidth, height: cardRowHeight)
                }
                .frame(maxWidth: .infinity)
                .frame(height: cardRowHeight)

                // 8 Highest Consuming Processes List (Activity Monitor style)
                if showProcesses, expandedMetric == .cpu {
                    StatsProcessList(
                        tint: .blue,
                        items: monitor.topCpuProcesses,
                        emptyText: loc("No processes using CPU right now")
                    )
                    .frame(maxWidth: .infinity)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if showProcesses, expandedMetric == .ram {
                    StatsProcessList(
                        tint: .green,
                        items: monitor.topRamProcesses,
                        emptyText: loc("No processes using memory right now")
                    )
                    .frame(maxWidth: .infinity)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // Thermal & Fan Control Expand Bar (only shown when not inspecting processes)
                if expandedMetric == nil {
                    Button(action: {
                        withAnimation(NotchPulseViewModel.notchSpring) {
                            isThermalExpanded.toggle()
                            if isThermalExpanded {
                                monitor.startThermalMonitoring()
                                vm.customOpenHeight = 285
                            } else {
                                monitor.stopThermalMonitoring()
                                vm.customOpenHeight = nil
                            }
                        }
                    }) {
                        HStack(spacing: 8) {
                            HStack(spacing: 5) {
                                Image(systemName: "thermometer.medium")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(monitor.temperatureLevel.color)

                                Text(loc("Temperature & Fan"))
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.9))

                                Text("·")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)

                                Text("\(Int(round(monitor.temperature)))°C")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundStyle(monitor.temperatureLevel.color)
                            }

                            Spacer()

                            HStack(spacing: 5) {
                                Image(systemName: "fanblades.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(monitor.currentFanSpeedPercent > 0 ? Color.cyan : Color.secondary)

                                Text(monitor.currentFanRPM > 0 ? "\(monitor.currentFanSpeedPercent)%" : loc("Auto"))
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.secondary)

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.secondary.opacity(0.85))
                                    .rotationEffect(.degrees(isThermalExpanded ? 90 : 0))
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if isThermalExpanded {
                        ThermalAndFanCard(monitor: monitor)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
            .padding(.horizontal, horizontalMargin)
            .padding(.top, 2)
            .padding(.bottom, 8)
            .animation(.smooth(duration: 0.25), value: expandedMetric)
            .animation(.smooth(duration: 0.25), value: isThermalExpanded)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .onAppear {
            monitor.startMonitoring()
            if isThermalExpanded || vm.featureTourTarget == "fan" {
                if vm.featureTourTarget == "fan" {
                    isThermalExpanded = true
                }
                monitor.startThermalMonitoring()
            }
        }
        .onChange(of: vm.featureTourTarget) { _, target in
            if target == "fan" {
                withAnimation(NotchPulseViewModel.notchSpring) {
                    isThermalExpanded = true
                    expandedMetric = nil
                    monitor.startThermalMonitoring()
                    vm.customOpenHeight = 285
                }
            } else if target == "stats" {
                withAnimation(NotchPulseViewModel.notchSpring) {
                    isThermalExpanded = false
                    monitor.stopThermalMonitoring()
                    vm.customOpenHeight = nil
                }
            }
        }
        .onDisappear {
            monitor.stopMonitoring()
            monitor.stopThermalMonitoring()
            if expandedMetric != nil || isThermalExpanded {
                expandedMetric = nil
                isThermalExpanded = false
                if NotchPulseViewCoordinator.shared.currentView != .audio {
                    withAnimation(NotchPulseViewModel.notchSpring) {
                        vm.customOpenHeight = nil
                    }
                }
            }
        }
    }

    private func toggleMetric(_ metric: ExpandedMetric) {
        guard showProcesses else { return }
        if expandedMetric == metric {
            expandedMetric = nil
            if isThermalExpanded {
                monitor.startThermalMonitoring()
                withAnimation(NotchPulseViewModel.notchSpring) {
                    vm.customOpenHeight = 285
                }
            } else {
                withAnimation(NotchPulseViewModel.notchSpring) {
                    vm.customOpenHeight = nil
                }
            }
        } else {
            expandedMetric = metric
            if isThermalExpanded {
                isThermalExpanded = false
                monitor.stopThermalMonitoring()
            }
            withAnimation(NotchPulseViewModel.notchSpring) {
                vm.customOpenHeight = 320
            }
        }
    }

    // MARK: - CPU Card
    private var cpuCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack(alignment: .center, spacing: 6) {
                Image(systemName: "cpu")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(Color.blue.opacity(0.35))
                    .clipShape(RoundedRectangle(cornerRadius: 5))

                Text("CPU")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)

                Spacer()

                Text(String(format: "%.0f%%", monitor.cpuTotal))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.blue)
            }

            // Apple Activity Monitor Graph (User stacked with System)
            AppleActivityGraphView(
                data: monitor.cpuHistory,
                secondaryData: monitor.cpuSystemHistory,
                color: .blue,
                secondaryColor: .orange,
                maxVal: 100.0
            )
            .frame(height: 28)

            // Segmented Bar (User | System | Idle)
            GeometryReader { geo in
                let w = geo.size.width
                let userW = w * CGFloat(monitor.cpuUser / 100.0)
                let sysW = w * CGFloat(monitor.cpuSystem / 100.0)
                let idleW = max(0, w - userW - sysW)

                HStack(spacing: 1.5) {
                    Rectangle().fill(Color.blue).frame(width: userW)
                    Rectangle().fill(Color.orange).frame(width: sysW)
                    Rectangle().fill(Color.gray.opacity(0.3)).frame(width: idleW)
                }
                .clipShape(Capsule())
            }
            .frame(height: 4)

            // Breakdown Labels
            HStack(spacing: 6) {
                HStack(spacing: 3) {
                    Circle().fill(Color.blue).frame(width: 5, height: 5)
                    Text(String(format: "U:%.0f%%", monitor.cpuUser))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 3) {
                    Circle().fill(Color.orange).frame(width: 5, height: 5)
                    Text(String(format: "S:%.0f%%", monitor.cpuSystem))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 3) {
                    Circle().fill(Color.gray).frame(width: 5, height: 5)
                    Text(String(format: "I:%.0f%%", monitor.cpuIdle))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            // Top Process
            if showProcesses, let topProc = monitor.topCpuProcesses.first {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.orange)
                    Text(topProc.name)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer()
                    Text(topProc.value)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.orange)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 5))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(expandedMetric == .cpu ? Color.blue.opacity(0.8) : Color.white.opacity(0.1), lineWidth: expandedMetric == .cpu ? 1.5 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture { toggleMetric(.cpu) }
    }

    // MARK: - RAM Card
    private var ramCard: some View {
        let pressureColor: Color = {
            switch monitor.ramPressure {
            case "Critical": return .red
            case "Warning": return .yellow
            default: return Color(red: 0.20, green: 0.72, blue: 0.28)
            }
        }()

        return VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack(alignment: .center, spacing: 6) {
                Image(systemName: "memorychip")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(Color.green.opacity(0.35))
                    .clipShape(RoundedRectangle(cornerRadius: 5))

                Text("RAM")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)

                // Pressure Pill
                HStack(spacing: 3) {
                    Circle()
                        .fill(pressureColor)
                        .frame(width: 4, height: 4)
                    Text(monitor.ramPressure)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(pressureColor)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 1.5)
                .background(Color.white.opacity(0.06))
                .clipShape(Capsule())

                Spacer()

                Text(String(format: "%.1f GB", monitor.ramUsedGB))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(pressureColor)
            }

            // Apple Activity Monitor Memory Pressure Graph
            AppleActivityGraphView(
                data: monitor.ramHistory,
                color: pressureColor,
                maxVal: 100.0,
                referenceFraction: 0.75,
                isSolidFill: true
            )
            .frame(height: 28)

            // Segmented Bar (App | Wired | Compressed | Free)
            GeometryReader { geo in
                let w = geo.size.width
                let total = max(1.0, monitor.ramTotalGB)
                let appW = w * CGFloat(monitor.ramAppGB / total)
                let wiredW = w * CGFloat(monitor.ramWiredGB / total)
                let compW = w * CGFloat(monitor.ramCompressedGB / total)
                let freeW = max(0, w - appW - wiredW - compW)

                HStack(spacing: 1.5) {
                    Rectangle().fill(Color.green).frame(width: appW)
                    Rectangle().fill(Color.orange).frame(width: wiredW)
                    Rectangle().fill(Color.purple).frame(width: compW)
                    Rectangle().fill(Color.gray.opacity(0.3)).frame(width: freeW)
                }
                .clipShape(Capsule())
            }
            .frame(height: 4)

            // Breakdown Labels
            HStack(spacing: 6) {
                HStack(spacing: 3) {
                    Circle().fill(Color.green).frame(width: 5, height: 5)
                    Text(String(format: "App:%.1fG", monitor.ramAppGB))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 3) {
                    Circle().fill(Color.orange).frame(width: 5, height: 5)
                    Text(String(format: "Wired:%.1fG", monitor.ramWiredGB))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 3) {
                    Circle().fill(monitor.swapUsedMB > 0 ? Color.purple : Color.gray.opacity(0.6)).frame(width: 5, height: 5)
                    Text("Swap:\(monitor.swapUsedFormatted)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(monitor.swapUsedMB > 500 ? Color.orange : .secondary)
                }
            }

            // Top Process
            if showProcesses, let topProc = monitor.topRamProcesses.first {
                HStack(spacing: 4) {
                    Image(systemName: "app.badge.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.green)
                    Text(topProc.name)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer()
                    Text(topProc.value)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.green)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 5))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(expandedMetric == .ram ? Color.green.opacity(0.8) : Color.white.opacity(0.1), lineWidth: expandedMetric == .ram ? 1.5 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture { toggleMetric(.ram) }
    }

    // MARK: - GPU Card
    private var gpuCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack(alignment: .center, spacing: 6) {
                Image(systemName: "display")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(Color.purple.opacity(0.35))
                    .clipShape(RoundedRectangle(cornerRadius: 5))

                Text("GPU")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)

                Spacer()

                Text(String(format: "%.0f%%", monitor.gpuUsage))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.purple)
            }

            // Apple Activity Monitor GPU Graph
            AppleActivityGraphView(
                data: monitor.gpuHistory,
                color: .purple,
                maxVal: 100.0
            )
            .frame(height: 28)

            // Progress Bar
            GeometryReader { geo in
                let w = geo.size.width
                let usageW = w * CGFloat(min(1.0, max(0.02, monitor.gpuUsage / 100.0)))

                ZStack(alignment: .leading) {
                    Capsule().fill(Color.gray.opacity(0.3))
                    Capsule().fill(
                        LinearGradient(
                            colors: [Color.purple, Color.pink],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: usageW)
                }
            }
            .frame(height: 4)

            // GPU Model & Status
            HStack {
                Text(monitor.gpuModel)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text("Metal 3")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.purple.opacity(0.8))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1.5)
                    .background(Color.purple.opacity(0.15))
                    .clipShape(Capsule())
            }

            // Additional Info
            HStack(spacing: 4) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.yellow)
                Text(loc("Hardware Acceleration"))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
                Text(loc("Active"))
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.green)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    StatsView()
        .environmentObject(NotchPulseViewModel())
        .frame(width: 640, height: 160)
        .background(Color.black)
}

/// Per-app list shown under the CPU/RAM cards when a card is tapped —
/// displays the top 8 processes consuming the most CPU or Memory (Activity Monitor style),
/// perfectly filling the expanded notch height without leaving empty space.
private struct StatsProcessList: View {
    let tint: Color
    let items: [MonitorProcessItem]
    let emptyText: String

    var body: some View {
        Group {
            if items.isEmpty {
                Text(emptyText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.vertical, 16)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 6) {
                    ForEach(Array(items.prefix(8).enumerated()), id: \.offset) { index, item in
                        HStack(spacing: 6) {
                            Text("\(index + 1).")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 18, alignment: .leading)
                            Text(item.name)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.92))
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer(minLength: 6)
                            Text(item.value)
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(tint)
                                .monospacedDigit()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6.5)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.06)))
                    }
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.42)))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}

/// Expandable Thermal & Fan Control card featuring a circular gradient ring gauge
/// and interactive fan speed controls with hardware baseline safety constraints.
private struct ThermalAndFanCard: View {
    @ObservedObject var monitor: SystemMonitorManager
    @State private var fanRotation: Double = 0

    var body: some View {
        HStack(spacing: 10) {
            // LEFT SIDE: Fan Speed Controller (56% width)
            VStack(alignment: .leading, spacing: 6) {
                // Header
                HStack(spacing: 6) {
                    Image(systemName: "fanblades.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(monitor.currentFanRPM > 0 ? Color.cyan : Color.secondary)
                        .rotationEffect(.degrees(fanRotation))
                        .onAppear {
                            withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                                fanRotation = 360
                            }
                        }

                    Text(loc("ĐIỀU KHIỂN QUẠT (FAN)"))
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)

                    Spacer()

                    // Live machine feedback badge
                    Text(fanFeedbackText)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())
                }

                // 5 Fan speed selection buttons
                HStack(spacing: 4) {
                    ForEach(FanSpeedOption.allCases) { option in
                        let isSelected = (monitor.selectedFanOption == option)
                        let isAllowed = isOptionAllowed(option)

                        Button(action: {
                            guard isAllowed else { return }
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                monitor.setFanOption(option)
                            }
                        }) {
                            VStack(spacing: 1.5) {
                                if !isAllowed {
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 7))
                                        .foregroundStyle(.secondary.opacity(0.8))
                                }
                                Text(option.label)
                                    .font(.system(size: 10, weight: isSelected ? .bold : .medium))
                                    .foregroundStyle(
                                        isSelected ? .white :
                                        (isAllowed ? .white.opacity(0.85) : .secondary.opacity(0.45))
                                    )
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 30)
                            .background(
                                isSelected ?
                                    Color.blue :
                                    (isAllowed ? Color.white.opacity(0.08) : Color.white.opacity(0.03))
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(isSelected ? Color.white.opacity(0.25) : Color.clear, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(!isAllowed)
                        .help(isAllowed ? option.description : loc("Máy đang yêu cầu mức tối thiểu \(monitor.hardwareBaselineFanPercent)%"))
                    }
                }

                // Status info line
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 8.5))
                        .foregroundStyle(.secondary)
                    Text(fanStatusNote)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )

            // RIGHT SIDE: Circular Temperature Gauge (44% width)
            HStack(spacing: 10) {
                // Circular Ring Gauge
                ZStack {
                    // Background track
                    Circle()
                        .stroke(Color.white.opacity(0.12), lineWidth: 6)

                    // Color Gradient Ring (Green -> Yellow -> Orange -> Red)
                    Circle()
                        .trim(from: 0.0, to: CGFloat(min(1.0, max(0.06, (monitor.temperature - 30.0) / 70.0))))
                        .stroke(
                            AngularGradient(
                                gradient: Gradient(colors: [
                                    Color(red: 0.20, green: 0.85, blue: 0.40), // Green
                                    Color(red: 1.00, green: 0.80, blue: 0.00), // Yellow
                                    Color(red: 1.00, green: 0.55, blue: 0.00), // Orange
                                    Color(red: 1.00, green: 0.20, blue: 0.20)  // Red
                                ]),
                                center: .center,
                                startAngle: .degrees(-90),
                                endAngle: .degrees(270)
                            ),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))

                    // Center Temperature Text
                    VStack(spacing: 0) {
                        Text("\(Int(round(monitor.temperature)))°C")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(monitor.temperatureLevel.color)

                        Text("SOC")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 54, height: 54)

                // Text Description
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(monitor.temperatureLevel.color)
                            .frame(width: 5, height: 5)

                        Text(monitor.temperatureLevel.title)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(monitor.temperatureLevel.color)
                    }

                    Text(tempAdviceText)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .frame(height: 74)
    }

    private func isOptionAllowed(_ option: FanSpeedOption) -> Bool {
        if option == .auto { return true }
        return option.rawValue >= monitor.hardwareBaselineFanPercent
    }

    private var fanFeedbackText: String {
        if monitor.currentFanRPM == 0 {
            return loc("0 RPM (Yên tĩnh)")
        }
        return "\(monitor.currentFanSpeedPercent)% · \(monitor.currentFanRPM) RPM"
    }

    private var fanStatusNote: String {
        if monitor.selectedFanOption == .auto {
            return loc("Hệ thống tự điều tiết theo nhiệt độ phần cứng")
        }
        return loc("Duy trì tối thiểu \(monitor.selectedFanOption.label) công suất")
    }

    private var tempAdviceText: String {
        switch monitor.temperatureLevel {
        case .cool:
            return loc("Nhiệt độ tối ưu, mát mẻ và tiết kiệm pin.")
        case .warm:
            return loc("Tải trung bình, quạt hoạt động êm ái.")
        case .hot:
            return loc("Nhiệt độ cao, nên tăng tốc quạt làm mát.")
        }
    }
}
