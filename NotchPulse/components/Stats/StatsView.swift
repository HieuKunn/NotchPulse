import Defaults
import Metal
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

                // Stacked chart if secondaryData is provided (e.g. Total CPU vs System CPU)
                if let sec = secondaryData, sec.count == data.count {
                    let totalPoints = points(from: data, width: w, height: h)
                    let secPoints = points(from: sec, width: w, height: h)

                    // Total CPU fill in primary color
                    smoothAreaPath(points: totalPoints, bottomY: h)
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.56), color.opacity(0.28)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    // System CPU fill in secondary color
                    smoothAreaPath(points: secPoints, bottomY: h)
                        .fill(
                            LinearGradient(
                                colors: [secondaryColor.opacity(0.65), secondaryColor.opacity(0.35)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    // System stroke line
                    smoothStrokePath(points: secPoints)
                        .stroke(secondaryColor.opacity(0.95), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))

                    // Total CPU stroke line
                    smoothStrokePath(points: totalPoints)
                        .stroke(color, style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
                } else {
                    // Single series (RAM Memory Pressure or GPU)
                    let seriesPoints = points(from: data, width: w, height: h)

                    // Apple Activity Monitor smooth organic area fill
                    smoothAreaPath(points: seriesPoints, bottomY: h)
                        .fill(
                            isSolidFill
                                ? LinearGradient(colors: [color.opacity(0.85), color.opacity(0.65)], startPoint: .top, endPoint: .bottom)
                                : LinearGradient(colors: [color.opacity(0.58), color.opacity(0.30)], startPoint: .top, endPoint: .bottom)
                        )

                    // Crisp Apple-style contour stroke along top wave
                    smoothStrokePath(points: seriesPoints)
                        .stroke(color, style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
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

    private func points(from values: [Double], width: CGFloat, height: CGFloat) -> [CGPoint] {
        guard !values.isEmpty else { return [] }
        let count = values.count
        let step = count > 1 ? width / CGFloat(count - 1) : width
        return values.enumerated().map { i, val in
            let clamped = max(0.0, min(maxVal, val))
            let x = CGFloat(i) * step
            let y = height - (CGFloat(clamped / maxVal) * (height - 2.5))
            return CGPoint(x: x, y: y)
        }
    }

    private func smoothAreaPath(points: [CGPoint], bottomY: CGFloat) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        guard points.count > 1 else {
            path.move(to: CGPoint(x: 0, y: bottomY))
            path.addLine(to: first)
            path.addLine(to: CGPoint(x: first.x, y: bottomY))
            path.closeSubpath()
            return path
        }

        path.move(to: CGPoint(x: 0, y: bottomY))
        path.addLine(to: first)

        for i in 0..<(points.count - 1) {
            let p0 = i > 0 ? points[i - 1] : points[i]
            let p1 = points[i]
            let p2 = points[i + 1]
            let p3 = (i + 2 < points.count) ? points[i + 2] : p2

            let cp1 = CGPoint(
                x: p1.x + (p2.x - p0.x) / 6.0,
                y: p1.y + (p2.y - p0.y) / 6.0
            )
            let cp2 = CGPoint(
                x: p2.x - (p3.x - p1.x) / 6.0,
                y: p2.y - (p3.y - p1.y) / 6.0
            )
            path.addCurve(to: p2, control1: cp1, control2: cp2)
        }

        path.addLine(to: CGPoint(x: points.last!.x, y: bottomY))
        path.closeSubpath()
        return path
    }

    private func smoothStrokePath(points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        guard points.count > 1 else {
            path.move(to: first)
            path.addLine(to: first)
            return path
        }

        path.move(to: first)

        for i in 0..<(points.count - 1) {
            let p0 = i > 0 ? points[i - 1] : points[i]
            let p1 = points[i]
            let p2 = points[i + 1]
            let p3 = (i + 2 < points.count) ? points[i + 2] : p2

            let cp1 = CGPoint(
                x: p1.x + (p2.x - p0.x) / 6.0,
                y: p1.y + (p2.y - p0.y) / 6.0
            )
            let cp2 = CGPoint(
                x: p2.x - (p3.x - p1.x) / 6.0,
                y: p2.y - (p3.y - p1.y) / 6.0
            )
            path.addCurve(to: p2, control1: cp1, control2: cp2)
        }
        return path
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
            // RAM: shortened by 10% on the right (50% of 2/3 = 33.33% of total) to give GPU room
            let ramWidth = ramGpuWidth * 0.50
            // GPU: expanded to the left by 10% (50% of 2/3 = 33.33% of total)
            let gpuWidth = ramGpuWidth * 0.50

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
                                vm.customOpenHeight = 300
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

                                Text(monitor.selectedFanProfile.title)
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
            monitor.shouldFetchProcesses = showProcesses
            monitor.startMonitoring()
            if isThermalExpanded || vm.featureTourTarget == "fan" {
                if vm.featureTourTarget == "fan" {
                    isThermalExpanded = true
                }
                monitor.startThermalMonitoring()
            }
        }
        .onChange(of: showProcesses) { _, enabled in
            monitor.shouldFetchProcesses = enabled
        }
        .onChange(of: vm.featureTourTarget) { _, target in
            if target == "fan" {
                withAnimation(NotchPulseViewModel.notchSpring) {
                    isThermalExpanded = true
                    expandedMetric = nil
                    monitor.shouldFetchProcesses = false
                    monitor.startThermalMonitoring()
                    vm.customOpenHeight = 300
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
            monitor.shouldFetchProcesses = false
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
                    vm.customOpenHeight = 300
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
            default: return Color(red: 0.35, green: 0.85, blue: 0.45)
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

                Spacer(minLength: 4)

                Text(String(format: "%.1f GB", monitor.ramUsedGB))
                    .font(.system(size: 13.5, weight: .bold, design: .rounded))
                    .foregroundStyle(pressureColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
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
                HStack(spacing: 2.5) {
                    Circle().fill(Color.green).frame(width: 4.5, height: 4.5)
                    Text(String(format: "App:%.1fG", monitor.ramAppGB))
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                HStack(spacing: 2.5) {
                    Circle().fill(Color.orange).frame(width: 4.5, height: 4.5)
                    Text(String(format: "Wired:%.1fG", monitor.ramWiredGB))
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                HStack(spacing: 2.5) {
                    Circle().fill(monitor.swapUsedMB > 0 ? Color.purple : Color.gray.opacity(0.6)).frame(width: 4.5, height: 4.5)
                    Text("Swap:\(monitor.swapUsedFormatted)")
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(monitor.swapUsedMB > 500 ? Color.orange : .secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
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
    private var metalVersionText: String {
        guard let dev = MTLCreateSystemDefaultDevice() else { return "Metal" }
        if #available(macOS 13.0, *), dev.supportsFamily(.metal3) {
            return "Metal 3"
        }
        if dev.supportsFamily(.apple7) || dev.supportsFamily(.mac2) {
            return "Metal 2"
        }
        return "Metal"
    }

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

                Spacer(minLength: 4)

                Text(String(format: "%.0f%%", monitor.gpuUsage))
                    .font(.system(size: 14.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.purple)
                    .lineLimit(1)
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
                Text(metalVersionText)
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

/// Expandable Thermal & Fan Control card featuring a 70/30 split:
/// Left (70%): Interactive fan slider and clean text profile buttons (Auto, Balanced, Smart, Max, Custom). Zero icons.
/// Right (30%): Compact SoC circular temperature gauge and status label.
private struct CoolingHeaderView: View {
    let feedbackText: String

    var body: some View {
        HStack(spacing: 6) {
            Text(loc("COOLING & FAN SPEED"))
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)

            Spacer()

            Text(feedbackText)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.88))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.08))
                .clipShape(Capsule())
        }
    }
}

private struct CoolingSliderView: View {
    @ObservedObject var monitor: SystemMonitorManager
    @State private var dragPercent: Double? = nil

    var body: some View {
        VStack(spacing: 2) {
            GeometryReader { sliderGeo in
                let sw: CGFloat = sliderGeo.size.width
                let activeFraction: Double = {
                    if let drag = dragPercent {
                        return drag
                    }
                    if monitor.selectedFanProfile == .custom {
                        return Double(monitor.customFanPercent) / 100.0
                    }
                    return Double(monitor.currentFanSpeedPercent) / 100.0
                }()
                let progress: CGFloat = CGFloat(min(1.0, max(0.0, activeFraction)))
                let barWidth: CGFloat = max(0, sw * progress)
                let knobOffset: CGFloat = max(0, min(sw - 11, sw * progress - 5.5))

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.09))
                        .frame(height: 7)

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.cyan.opacity(0.85), Color.blue],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: barWidth, height: 7)

                    Circle()
                        .fill(Color.white)
                        .frame(width: 11, height: 11)
                        .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                        .offset(x: knobOffset)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { val in
                            let clampedX = max(0, min(sw, val.location.x))
                            let fraction = Double(clampedX / max(1.0, sw))
                            dragPercent = fraction
                            let pct = Int(round(fraction * 100.0))
                            monitor.setCustomFanPercent(pct)
                        }
                        .onEnded { _ in
                            dragPercent = nil
                            FanHelperManager.shared.promptInstallIfNeeded {
                                monitor.reapplyActiveProfileOnWake()
                            }
                        }
                )
            }
            .frame(height: 11)

            HStack {
                Text("0 RPM")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary.opacity(0.7))
                Spacer()
                let maxRpmVal = monitor.currentFanMaxRPM > 0 ? monitor.currentFanMaxRPM : 6550
                Text(monitor.isHardwareFanAvailable ? loc("Max ~\(maxRpmVal.formatted()) RPM") : loc("Passive cooling (Fanless)"))
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary.opacity(0.7))
            }
        }
    }
}

private struct CoolingProfileButtonsView: View {
    @ObservedObject var monitor: SystemMonitorManager

    var body: some View {
        HStack(spacing: 4) {
            ForEach(NotchPulseFanProfile.allCases) { profile in
                let isSelected: Bool = monitor.selectedFanProfile == profile
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        monitor.setFanProfile(profile)
                    }
                    if profile != .auto {
                        FanHelperManager.shared.promptInstallIfNeeded {
                            monitor.reapplyActiveProfileOnWake()
                        }
                    }
                }) {
                    Text(profile.title)
                        .font(.system(size: 9, weight: isSelected ? .bold : .medium))
                        .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.65))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 3.5)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(isSelected ? Color.cyan.opacity(0.26) : Color.white.opacity(0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .stroke(isSelected ? Color.cyan.opacity(0.65) : Color.white.opacity(0.08), lineWidth: 0.8)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct SocGaugeView: View {
    @ObservedObject var monitor: SystemMonitorManager

    private var gaugeTrim: CGFloat {
        CGFloat(min(1.0, max(0.06, (monitor.temperature - 30.0) / 70.0)))
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.12), lineWidth: 5)

                Circle()
                    .trim(from: 0.0, to: gaugeTrim)
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [
                                Color(red: 0.20, green: 0.85, blue: 0.40),
                                Color(red: 1.00, green: 0.80, blue: 0.00),
                                Color(red: 1.00, green: 0.55, blue: 0.00),
                                Color(red: 1.00, green: 0.20, blue: 0.20)
                            ]),
                            center: .center,
                            startAngle: .degrees(-90),
                            endAngle: .degrees(270)
                        ),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 0) {
                    Text(monitor.temperature > 0 ? "\(Int(round(monitor.temperature)))°C" : "--°C")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(monitor.temperatureLevel.color)

                    Text("SOC")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 46, height: 46)

            HStack(spacing: 3) {
                Circle()
                    .fill(monitor.temperatureLevel.color)
                    .frame(width: 4, height: 4)

                Text(monitor.temperatureLevel.title)
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(monitor.temperatureLevel.color)
                    .lineLimit(1)
            }
        }
    }
}

/// Expandable Thermal & Fan Control card featuring a 70/30 split:
/// Left (70%): Interactive fan slider and clean text profile buttons (Auto, Balanced, Smart, Max, Custom). Zero icons.
/// Right (30%): Compact SoC circular temperature gauge and status label.
private struct ThermalAndFanCard: View {
    @ObservedObject var monitor: SystemMonitorManager

    var body: some View {
        GeometryReader { geo in
            let totalW = geo.size.width
            let spacing: CGFloat = 8
            let leftW = max(100, (totalW - spacing) * 0.70)
            let rightW = max(60, (totalW - spacing) * 0.30)

            HStack(spacing: spacing) {
                VStack(alignment: .leading, spacing: 6) {
                    CoolingHeaderView(feedbackText: fanFeedbackText)
                    CoolingSliderView(monitor: monitor)
                    CoolingProfileButtonsView(monitor: monitor)
                }
                .padding(8)
                .frame(width: leftW, height: 86)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )

                SocGaugeView(monitor: monitor)
                    .padding(8)
                    .frame(width: rightW, height: 86)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 86)
    }

    private var fanFeedbackText: String {
        if monitor.currentFanRPM == 0 {
            return loc("0 RPM (Silent)")
        }
        return "\(monitor.currentFanRPM) RPM"
    }
}
