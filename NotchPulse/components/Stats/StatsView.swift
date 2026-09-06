//
//  StatsView.swift
//  NotchPulse
//
//  Created for NotchPulse - System Monitor Feature (Stats App Style)
//

import Defaults
import SwiftUI

struct SparklineView: View {
    let data: [Double]
    let color: Color
    var maxVal: Double = 100.0

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let count = max(1, data.count)
            let step = count > 1 ? w / CGFloat(count - 1) : w

            ZStack {
                // Gradient Fill
                Path { path in
                    guard !data.isEmpty else { return }
                    path.move(to: CGPoint(x: 0, y: h))
                    for (i, val) in data.enumerated() {
                        let clamped = max(0.0, min(maxVal, val))
                        let x = CGFloat(i) * step
                        let y = h - (CGFloat(clamped / maxVal) * (h - 4) + 2)
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                    path.addLine(to: CGPoint(x: CGFloat(data.count - 1) * step, y: h))
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [color.opacity(0.35), color.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                // Line Stroke
                Path { path in
                    guard !data.isEmpty else { return }
                    for (i, val) in data.enumerated() {
                        let clamped = max(0.0, min(maxVal, val))
                        let x = CGFloat(i) * step
                        let y = h - (CGFloat(clamped / maxVal) * (h - 4) + 2)
                        if i == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

struct StatsView: View {
    @ObservedObject var monitor = SystemMonitorManager.shared
    @Default(.systemMonitorShowProcesses) var showProcesses

    var body: some View {
        HStack(spacing: 10) {
            // MARK: - CPU Card
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

                // Sparkline Graph
                SparklineView(data: monitor.cpuHistory, color: .blue, maxVal: 100.0)
                    .frame(height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .background(Color.black.opacity(0.25))

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

            // MARK: - RAM Card
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

                    Spacer()

                    Text(String(format: "%.1f GB", monitor.ramUsedGB))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.green)
                }

                // Sparkline Graph
                SparklineView(data: monitor.ramHistory, color: .green, maxVal: 100.0)
                    .frame(height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .background(Color.black.opacity(0.25))

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

                // Breakdown Labels & Pressure
                HStack(spacing: 5) {
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
                    // Pressure Pill
                    HStack(spacing: 3) {
                        Circle()
                            .fill(monitor.ramPressure == "Normal" ? Color.green : (monitor.ramPressure == "Warning" ? Color.yellow : Color.red))
                            .frame(width: 5, height: 5)
                        Text(monitor.ramPressure)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.secondary)
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

            // MARK: - GPU Card
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

                // Sparkline Graph
                SparklineView(data: monitor.gpuHistory, color: .purple, maxVal: 100.0)
                    .frame(height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .background(Color.black.opacity(0.25))

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
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .onAppear {
            monitor.startMonitoring()
        }
        .onDisappear {
            monitor.stopMonitoring()
        }
    }
}

#Preview {
    StatsView()
        .frame(width: 640, height: 160)
        .background(Color.black)
}
