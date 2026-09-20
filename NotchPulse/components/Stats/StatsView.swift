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

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let count = max(1, data.count)
            let step = count > 1 ? w / CGFloat(count - 1) : w

            ZStack {
                // macOS Activity Monitor dark container background
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.black.opacity(0.36))

                // Apple-style horizontal reference grid lines (50% and top guide)
                Path { path in
                    path.move(to: CGPoint(x: 0, y: h * 0.5))
                    path.addLine(to: CGPoint(x: w, y: h * 0.5))
                }
                .stroke(Color.white.opacity(0.09), lineWidth: 0.75)

                Path { path in
                    path.move(to: CGPoint(x: 0, y: 1.5))
                    path.addLine(to: CGPoint(x: w, y: 1.5))
                }
                .stroke(Color.white.opacity(0.07), lineWidth: 0.75)

                // If secondaryData is provided (e.g. System CPU load) -> Stacked chart like Activity Monitor
                if let sec = secondaryData, sec.count == data.count {
                    // Total CPU fill (User + System) in primary color (Blue)
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
                            colors: [color.opacity(0.56), color.opacity(0.30)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    // System CPU fill in secondary color (Red/Orange) at the bottom
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
                            colors: [secondaryColor.opacity(0.65), secondaryColor.opacity(0.38)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    // System stroke line (Orange/Red)
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

                    // Total CPU stroke line (Blue)
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
                    // Single series (RAM Memory Pressure or GPU) - Solid Activity Monitor aesthetic
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
                            colors: [color.opacity(0.58), color.opacity(0.32)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
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
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
    }
}

typealias SparklineView = AppleActivityGraphView

struct StatsView: View {
    @ObservedObject var monitor = SystemMonitorManager.shared
    @Default(.systemMonitorShowProcesses) var showProcesses

    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 10
            let availableWidth = max(0, geo.size.width - (spacing * 2))
            // CPU: 1/3 (33.33%)
            let cpuWidth = availableWidth * (1.0 / 3.0)
            // RAM + GPU: 2/3 (66.67%)
            let ramGpuWidth = availableWidth * (2.0 / 3.0)
            // RAM: 60% of 2/3 (= 40% of total)
            let ramWidth = ramGpuWidth * 0.60
            // GPU: 40% of 2/3 (= 26.67% of total)
            let gpuWidth = ramGpuWidth * 0.40

            HStack(spacing: spacing) {
                cpuCard
                    .frame(width: cpuWidth)

                ramCard
                    .frame(width: ramWidth)

                gpuCard
                    .frame(width: gpuWidth)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .onAppear {
            monitor.startMonitoring()
        }
        .onDisappear {
            monitor.stopMonitoring()
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
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - RAM Card
    private var ramCard: some View {
        VStack(alignment: .leading, spacing: 6) {
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
                        .fill(monitor.ramPressure == "Normal" ? Color.green : (monitor.ramPressure == "Warning" ? Color.yellow : Color.red))
                        .frame(width: 4, height: 4)
                    Text(monitor.ramPressure)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 1.5)
                .background(Color.white.opacity(0.06))
                .clipShape(Capsule())

                Spacer()

                Text(String(format: "%.1f GB", monitor.ramUsedGB))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.green)
            }

            // Apple Activity Monitor Memory Pressure Graph
            AppleActivityGraphView(
                data: monitor.ramHistory,
                color: monitor.ramPressure == "Normal" ? .green : (monitor.ramPressure == "Warning" ? .yellow : .red),
                maxVal: 100.0
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

            // Breakdown Labels (App | Wired | Swap)
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
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
                Text("Hardware Acceleration")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
                Text("Active")
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
        .frame(width: 640, height: 160)
        .background(Color.black)
}
