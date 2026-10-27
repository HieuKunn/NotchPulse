import AppKit
import Defaults
import SwiftUI

struct SystemMonitorSettingsPage: View {
    @Default(.enableSystemMonitor) var enableSystemMonitor
    @Default(.systemMonitorShowProcesses) var showProcesses
    @ObservedObject private var monitor = SystemMonitorManager.shared

    private enum MonitorMetric { case cpu, ram }
    @State private var expandedMetric: MonitorMetric?

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $enableSystemMonitor) {
                    Text(loc("System Monitor (Stats)"))
                        .font(.headline)
                    Text(loc("Monitor real-time CPU, RAM, and GPU load in a dedicated Notch tab inspired by the 'Stats' app."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .toggleStyle(.switch)

                HStack(spacing: 8) {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundStyle(.green)
                        .font(.subheadline)
                    Text(loc("System Monitoring Access: Active (Darwin Mach & IOKit native APIs)"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 2)
            }

            Section {
                Toggle(loc("Show top resource-consuming processes"), isOn: $showProcesses)
            } header: {
                Text(loc("Display Options"))
            }
            .disabled(!enableSystemMonitor)

            Section {
                VStack(spacing: 12) {
                    HStack(spacing: 16) {
                        MonitorTileButton(
                            icon: "cpu",
                            tint: .blue,
                            title: loc("CPU"),
                            value: String(format: "%.0f%%", monitor.cpuTotal),
                            subtitle: nil,
                            isExpanded: expandedMetric == .cpu,
                            action: { expandedMetric = (expandedMetric == .cpu) ? nil : .cpu }
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Divider()

                        MonitorTileButton(
                            icon: "memorychip",
                            tint: .green,
                            title: loc("RAM"),
                            value: String(format: "%.1f / %.0f GB", monitor.ramUsedGB, monitor.ramTotalGB),
                            subtitle: "\(loc("Swap")): \(monitor.swapUsedFormatted)",
                            isExpanded: expandedMetric == .ram,
                            action: { expandedMetric = (expandedMetric == .ram) ? nil : .ram }
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Divider()

                        MonitorTileButton(
                            icon: "display",
                            tint: .purple,
                            title: loc("GPU"),
                            value: String(format: "%.0f%%", monitor.gpuUsage),
                            subtitle: nil,
                            isExpanded: false,
                            action: {}
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 4)

                    if showProcesses, expandedMetric == .cpu {
                        MonitorProcessList(
                            title: loc("CPU"), icon: "cpu", tint: .blue,
                            items: monitor.topCpuProcesses,
                            emptyText: loc("No processes using CPU right now")
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    if showProcesses, expandedMetric == .ram {
                        MonitorProcessList(
                            title: loc("RAM"), icon: "memorychip", tint: .green,
                            items: monitor.topRamProcesses,
                            emptyText: loc("No processes using memory right now")
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .animation(.smooth(duration: 0.22), value: expandedMetric)
            } header: {
                Text(loc("Preview"))
            }
            .disabled(!enableSystemMonitor)

            Section {
                HardwareFanDiagnosticsView()
            } header: {
                Text(loc("Hardware Fan Control & Profiles"))
            } footer: {
                Text(loc("Apple Silicon SMC fan hardware controls & operational profiles guide."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            monitor.shouldFetchProcesses = (expandedMetric != nil)
            monitor.startMonitoring()
        }
        .onChange(of: expandedMetric) { _, metric in
            monitor.shouldFetchProcesses = (metric != nil)
            if monitor.shouldFetchProcesses {
                monitor.requestMetricsUpdate()
            }
        }
        .onDisappear {
            expandedMetric = nil
            monitor.shouldFetchProcesses = false
            monitor.stopMonitoring()
        }
    }
}

// MARK: - Hardware SMC Fan Guide
private struct HardwareFanDiagnosticsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(loc("Fan Profiles & Behavior"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(loc("Controlled via Notch"))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 6) {
                FanProfileRow(
                    title: loc("Auto (Apple Default)"),
                    summary: loc("macOS kernel handles fan speed automatically. Fans stay at minimum RPM or turn off completely during light tasks to save battery and maintain silence.")
                )

                FanProfileRow(
                    title: loc("Balanced"),
                    summary: loc("Maintains optimal thermal-to-noise balance, capping fan speed around ~60% (~4,400 RPM) to keep the system cool without excessive noise.")
                )

                FanProfileRow(
                    title: loc("Smart (Predictive)"),
                    summary: loc("Monitors SoC thermal acceleration to ramp up fans preemptively before sudden heat spikes, preventing thermal throttling.")
                )

                FanProfileRow(
                    title: loc("Max 100%"),
                    summary: loc("Locks fans to maximum hardware RPM (~6,550 RPM) for intensive rendering, video export, heavy compilation, or gaming.")
                )

                FanProfileRow(
                    title: loc("Custom (Manual)"),
                    summary: loc("Drag the fan slider directly from the Notch interface to lock fans at any specific percentage or RPM target.")
                )
            }

            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.top, 1)

                Text(loc("You can switch fan profiles or drag the custom speed slider directly inside the Notch / Dynamic Island without opening Settings."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 4)
    }
}

private struct FanProfileRow: View {
    let title: String
    let summary: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
            Text(summary)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct MonitorTileButton: View {
    let icon: String
    let tint: Color
    let title: String
    let value: String
    let subtitle: String?
    let isExpanded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                    .font(.headline)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 3) {
                        Text(title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    Text(value)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
    }
}

private struct MonitorProcessList: View {
    let title: String
    let icon: String
    let tint: Color
    let items: [MonitorProcessItem]
    let emptyText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundStyle(tint)
                Text(loc("Top apps by \(title)"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(loc("largest first"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if items.isEmpty {
                Text(emptyText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(spacing: 8) {
                        Text("\(index + 1).")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .frame(width: 22, alignment: .leading)
                        Text(item.name)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 12)
                        Text(item.value)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(tint)
                            .monospacedDigit()
                    }
                    .padding(.vertical, 1)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }
}
