//
//  SystemMonitorManager.swift
//  NotchPulse
//
//  Created for NotchPulse - System Monitor Feature (Stats style)
//

import Combine
import Darwin
import Foundation
import IOKit
import MachO
import SwiftUI

public enum TemperatureLevel {
    case cool    // < 60°C (Green)
    case warm    // 60 - 79°C (Yellow / Orange)
    case hot     // >= 80°C (Red / Danger)

    public var title: String {
        switch self {
        case .cool: return "Mát mẻ"
        case .warm: return "Ấm áp"
        case .hot: return "Nhiệt cao / Cảnh báo"
        }
    }

    public var color: Color {
        switch self {
        case .cool: return Color(red: 0.20, green: 0.85, blue: 0.40)
        case .warm: return Color(red: 1.00, green: 0.75, blue: 0.00)
        case .hot: return Color(red: 1.00, green: 0.25, blue: 0.20)
        }
    }
}

public enum FanSpeedOption: Int, CaseIterable, Identifiable {
    case auto = 0
    case p25 = 25
    case p50 = 50
    case p75 = 75
    case p100 = 100

    public var id: Int { rawValue }

    public var label: String {
        switch self {
        case .auto: return "Auto"
        case .p25: return "25%"
        case .p50: return "50%"
        case .p75: return "75%"
        case .p100: return "100%"
        }
    }

    public var description: String {
        switch self {
        case .auto: return "Theo máy (Tự động)"
        case .p25: return "25% công suất quạt"
        case .p50: return "50% công suất quạt"
        case .p75: return "75% công suất quạt"
        case .p100: return "100% công suất tối đa"
        }
    }
}

public struct MonitorProcessItem: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let value: String
    
    public init(name: String, value: String) {
        self.id = name + value
        self.name = name
        self.value = value
    }
}

public class SystemMonitorManager: ObservableObject {
    public static let shared = SystemMonitorManager()

    // MARK: - CPU Properties
    @Published public var cpuTotal: Double = 0.0
    @Published public var cpuUser: Double = 0.0
    @Published public var cpuSystem: Double = 0.0
    @Published public var cpuIdle: Double = 100.0
    @Published public var cpuHistory: [Double] = Array(repeating: 5.0, count: 24)
    @Published public var cpuSystemHistory: [Double] = Array(repeating: 2.0, count: 24)

    // MARK: - RAM Properties
    @Published public var ramUsedGB: Double = 0.0
    @Published public var ramTotalGB: Double = 0.0
    @Published public var ramPercentage: Double = 0.0
    @Published public var ramAppGB: Double = 0.0
    @Published public var ramWiredGB: Double = 0.0
    @Published public var ramCompressedGB: Double = 0.0
    @Published public var ramFreeGB: Double = 0.0
    @Published public var ramPressure: String = "Normal"
    @Published public var ramHistory: [Double] = Array(repeating: 28.0, count: 24)
    @Published public var swapUsedMB: Double = 0.0
    @Published public var swapTotalMB: Double = 0.0

    public var swapUsedFormatted: String {
        if swapUsedMB >= 1024.0 {
            return String(format: "%.1f GB", swapUsedMB / 1024.0)
        } else {
            return String(format: "%.0f MB", swapUsedMB)
        }
    }

    // MARK: - GPU Properties
    @Published public var gpuUsage: Double = 0.0
    @Published public var gpuModel: String = "Apple Silicon GPU"
    @Published public var gpuHistory: [Double] = Array(repeating: 2.0, count: 24)

    // MARK: - Thermal & Fan Properties
    @Published public var temperature: Double = 42.0
    @Published public var temperatureLevel: TemperatureLevel = .cool
    @Published public var currentFanSpeedPercent: Int = 0
    @Published public var currentFanRPM: Int = 0
    @Published public var hardwareBaselineFanPercent: Int = 0
    @Published public var selectedFanOption: FanSpeedOption = .auto
    @Published public var isThermalMonitoring: Bool = false
    @Published public var isHardwareFanAvailable: Bool = false

    // MARK: - Top Processes
    @Published public var topCpuProcesses: [MonitorProcessItem] = []
    @Published public var topRamProcesses: [MonitorProcessItem] = []
    public var shouldFetchProcesses: Bool = false

    // MARK: - Internal State
    private var previousCpuLoadInfo: host_cpu_load_info?
    private var timer: Timer?
    private var thermalTimer: Timer?
    private var isMonitoring: Bool = false
    private let queue = DispatchQueue(label: "com.notchpulse.systemmonitor", qos: .utility)

    private init() {
        // Detect GPU Name once
        detectGPUModel()
        // Initialize total RAM
        ramTotalGB = Double(ProcessInfo.processInfo.physicalMemory) / (1024 * 1024 * 1024)
    }

    public func startMonitoring() {
        DispatchQueue.main.async {
            guard !self.isMonitoring else { return }
            self.isMonitoring = true
            
            if self.timer == nil {
                // The very first refresh must NOT run on the main thread: updateMetrics
                // forks /bin/ps -A and walks every pid via proc_pid_rusage, which can stall the main loop.
                // Kick it to the utility queue like every timer-driven refresh.
                self.queue.async {
                    self.updateMetrics()
                }
                self.timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
                    self?.queue.async {
                        self?.updateMetrics()
                    }
                }
            }
        }
    }

    public func stopMonitoring() {
        DispatchQueue.main.async {
            self.isMonitoring = false
            self.timer?.invalidate()
            self.timer = nil
            self.stopThermalMonitoring()
        }
    }

    // MARK: - Dedicated 1s Thermal & Fan Monitoring (Runs ONLY when expanded)
    public func startThermalMonitoring() {
        DispatchQueue.main.async {
            guard !self.isThermalMonitoring else { return }
            self.isThermalMonitoring = true
            self.queue.async {
                self.updateThermalMetrics()
            }
            self.thermalTimer?.invalidate()
            self.thermalTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.queue.async {
                    self?.updateThermalMetrics()
                }
            }
        }
    }

    public func stopThermalMonitoring() {
        DispatchQueue.main.async {
            self.isThermalMonitoring = false
            self.thermalTimer?.invalidate()
            self.thermalTimer = nil
        }
    }

    public func setFanOption(_ option: FanSpeedOption) {
        self.selectedFanOption = option
        self.queue.async {
            self.updateThermalMetrics()
        }
    }

    // MARK: - Metrics Fetching
    private func updateMetrics() {
        let (totalCPU, userCPU, sysCPU, idleCPU) = fetchCPUUsage()
        let (usedRAM, totalRAM, percentRAM, appRAM, wiredRAM, compRAM, freeRAM, pressure, pressurePercent) = fetchRAMUsage()
        let (usedSwap, totalSwap) = fetchSwapUsage()
        let gpu = fetchGPUUsage()
        let (topCpu, topRam): ([MonitorProcessItem], [MonitorProcessItem])
        if shouldFetchProcesses {
            (topCpu, topRam) = fetchTopProcesses()
        } else {
            (topCpu, topRam) = ([], [])
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Update CPU
            self.cpuTotal = totalCPU
            self.cpuUser = userCPU
            self.cpuSystem = sysCPU
            self.cpuIdle = idleCPU
            self.cpuHistory.append(totalCPU)
            if self.cpuHistory.count > 24 {
                self.cpuHistory.removeFirst()
            }
            self.cpuSystemHistory.append(sysCPU)
            if self.cpuSystemHistory.count > 24 {
                self.cpuSystemHistory.removeFirst()
            }

            // Update RAM
            self.ramUsedGB = usedRAM
            self.ramTotalGB = totalRAM
            self.ramPercentage = percentRAM
            self.ramAppGB = appRAM
            self.ramWiredGB = wiredRAM
            self.ramCompressedGB = compRAM
            self.ramFreeGB = freeRAM
            self.ramPressure = pressure
            self.swapUsedMB = usedSwap
            self.swapTotalMB = totalSwap
            self.ramHistory.append(pressurePercent)
            if self.ramHistory.count > 24 {
                self.ramHistory.removeFirst()
            }

            // Update GPU
            self.gpuUsage = gpu
            self.gpuHistory.append(gpu)
            if self.gpuHistory.count > 24 {
                self.gpuHistory.removeFirst()
            }

            // Update Processes
            self.topCpuProcesses = topCpu
            self.topRamProcesses = topRam
        }
    }

    // MARK: - CPU Fetch
    private func fetchCPUUsage() -> (total: Double, user: Double, system: Double, idle: Double) {
        var cpuLoadInfo = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &cpuLoadInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return (0.0, 0.0, 0.0, 100.0)
        }

        if let prev = previousCpuLoadInfo {
            let userTicks = Double(cpuLoadInfo.cpu_ticks.0 - prev.cpu_ticks.0)
            let sysTicks = Double(cpuLoadInfo.cpu_ticks.1 - prev.cpu_ticks.1)
            let idleTicks = Double(cpuLoadInfo.cpu_ticks.2 - prev.cpu_ticks.2)
            let niceTicks = Double(cpuLoadInfo.cpu_ticks.3 - prev.cpu_ticks.3)
            let totalTicks = userTicks + sysTicks + idleTicks + niceTicks

            previousCpuLoadInfo = cpuLoadInfo

            if totalTicks > 0 {
                let userPercent = max(0.0, min(100.0, ((userTicks + niceTicks) / totalTicks) * 100.0))
                let sysPercent = max(0.0, min(100.0, (sysTicks / totalTicks) * 100.0))
                let idlePercent = max(0.0, min(100.0, (idleTicks / totalTicks) * 100.0))
                let totalPercent = max(0.0, min(100.0, userPercent + sysPercent))
                return (totalPercent, userPercent, sysPercent, idlePercent)
            }
        } else {
            previousCpuLoadInfo = cpuLoadInfo
        }

        return (5.0, 3.0, 2.0, 95.0)
    }

    // MARK: - RAM Fetch
    private func fetchRAMUsage() -> (used: Double, total: Double, percent: Double, app: Double, wired: Double, comp: Double, free: Double, pressure: String, pressurePercent: Double) {
        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        let totalBytes = ProcessInfo.processInfo.physicalMemory
        let totalGB = Double(totalBytes) / (1024 * 1024 * 1024)
        guard result == KERN_SUCCESS else {
            return (0.0, totalGB, 0.0, 0.0, 0.0, 0.0, totalGB, "Normal", 0.0)
        }

        let pageSize = Double(vm_kernel_page_size)
        let appBytes = Double(vmStats.internal_page_count - vmStats.purgeable_count) * pageSize
        let wiredBytes = Double(vmStats.wire_count) * pageSize
        let compBytes = Double(vmStats.compressor_page_count) * pageSize
        let freeBytes = Double(vmStats.free_count + vmStats.inactive_count) * pageSize
        let usedBytes = appBytes + wiredBytes + compBytes

        let appGB = max(0.0, appBytes / (1024 * 1024 * 1024))
        let wiredGB = max(0.0, wiredBytes / (1024 * 1024 * 1024))
        let compGB = max(0.0, compBytes / (1024 * 1024 * 1024))
        let freeGB = max(0.0, freeBytes / (1024 * 1024 * 1024))
        let usedGB = max(0.0, usedBytes / (1024 * 1024 * 1024))
        let percent = min(100.0, max(0.0, (usedBytes / Double(totalBytes)) * 100.0))

        var pressure = "Normal"
        var pressureLevel: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &pressureLevel, &size, nil, 0) == 0 {
            switch pressureLevel {
            case 1:
                pressure = "Normal"
            case 2:
                pressure = "Warning"
            case 4:
                pressure = "Critical"
            default:
                pressure = "Normal"
            }
        } else {
            if percent > 90.0 {
                pressure = "Critical"
            } else if percent > 75.0 {
                pressure = "Warning"
            } else {
                pressure = "Normal"
            }
        }

        // True Memory Pressure percentage modeled after macOS Activity Monitor
        let pressurePercent: Double
        switch pressure {
        case "Critical":
            pressurePercent = min(100.0, 80.0 + (percent / 100.0) * 20.0)
        case "Warning":
            pressurePercent = min(75.0, 55.0 + (percent / 100.0) * 20.0)
        default: // Normal (Tốt)
            let baseRatio = (wiredBytes + compBytes) / Double(totalBytes)
            pressurePercent = min(45.0, max(18.0, baseRatio * 100.0 + 10.0))
        }

        return (usedGB, totalGB, percent, appGB, wiredGB, compGB, freeGB, pressure, pressurePercent)
    }

    // MARK: - Swap Fetch
    private func fetchSwapUsage() -> (usedMB: Double, totalMB: Double) {
        var mib: [Int32] = [CTL_VM, VM_SWAPUSAGE]
        var swapUsage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        if sysctl(&mib, 2, &swapUsage, &size, nil, 0) == 0 {
            let usedMB = Double(swapUsage.xsu_used) / (1024.0 * 1024.0)
            let totalMB = Double(swapUsage.xsu_total) / (1024.0 * 1024.0)
            return (usedMB, totalMB)
        }
        return (0.0, 0.0)
    }

    // MARK: - GPU Fetch
    private func fetchGPUUsage() -> Double {
        let matchDict = IOServiceMatching("IOAccelerator")
        var iterator: io_iterator_t = 0
        var usage: Double = 0.0

        if IOServiceGetMatchingServices(kIOMainPortDefault, matchDict, &iterator) == kIOReturnSuccess {
            while case let service = IOIteratorNext(iterator), service != 0 {
                defer { IOObjectRelease(service) }
                var props: Unmanaged<CFMutableDictionary>?
                if IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == kIOReturnSuccess,
                   let dict = props?.takeRetainedValue() as? [String: Any],
                   let perfStats = dict["PerformanceStatistics"] as? [String: Any] {
                    if let util = perfStats["Device Utilization %"] as? Int {
                        usage = max(usage, Double(util))
                    } else if let util = perfStats["GPU Core Utilization"] as? Double {
                        usage = max(usage, util * 100.0)
                    }
                }
            }
            IOObjectRelease(iterator)
        }
        return min(100.0, max(0.0, usage))
    }

    private func detectGPUModel() {
        let matchDict = IOServiceMatching("IOAccelerator")
        var iterator: io_iterator_t = 0
        if IOServiceGetMatchingServices(kIOMainPortDefault, matchDict, &iterator) == kIOReturnSuccess {
            if let service = IOIteratorNext(iterator) as io_object_t?, service != 0 {
                defer {
                    IOObjectRelease(service)
                    IOObjectRelease(iterator)
                }
                var props: Unmanaged<CFMutableDictionary>?
                if IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == kIOReturnSuccess,
                   let dict = props?.takeRetainedValue() as? [String: Any] {
                    if let model = dict["model"] as? String {
                        self.gpuModel = model
                    } else if let ioClass = dict["IOClass"] as? String {
                        self.gpuModel = ioClass.replacingOccurrences(of: "Accelerator", with: " ")
                    }
                }
            } else {
                IOObjectRelease(iterator)
            }
        }
    }

    // MARK: - Top Processes Fetch

    /// CPU list uses instantaneous per-process deltas via proc_pid_rusage — the same
    /// measurement Activity Monitor's "% CPU" column shows. `ps %cpu` is a LIFETIME
    /// decaying average: heavy usage weeks ago (e.g. the old 25ms poll bug) inflated
    /// the number forever ("NotchPulse 48%" next to a 21% system total), while
    /// Activity Monitor showed the truthful 1.4%. RSS (memory) is instantaneous in
    /// `ps`, so the RAM list stays ps-sorted.
    private struct CpuUsageSample {
        let cpuNs: UInt64
        let at: TimeInterval
    }
    private var cpuSamples: [pid_t: CpuUsageSample] = [:]

    private func fetchTopProcesses() -> (cpu: [MonitorProcessItem], ram: [MonitorProcessItem]) {
        let cpuList = fetchInstantaneousTopCPU(limit: 10)
        let ramList = fetchInstantaneousTopRAM(limit: 10)
        return (cpuList, ramList)
    }

    private func fetchInstantaneousTopRAM(limit: Int) -> [MonitorProcessItem] {
        let pidCount = Int(proc_listallpids(nil, 0))
        guard pidCount > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: pidCount + 64)
        let written = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size)))
        guard written > 0 else { return [] }

        var entries: [(name: String, rssMB: Double)] = []
        entries.reserveCapacity(written)
        var nameBuffer = [CChar](repeating: 0, count: 1024)

        for index in 0..<written {
            let pid = pids[index]
            guard pid > 0 else { continue }

            var taskInfo = proc_taskinfo()
            let size = Int32(MemoryLayout<proc_taskinfo>.stride)
            let result = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, size)
            guard result == size else { continue }

            let rssMB = Double(taskInfo.pti_resident_size) / (1024.0 * 1024.0)
            guard rssMB > 1.0 else { continue }

            nameBuffer[0] = 0
            proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
            let name = String(cString: nameBuffer)
            guard !name.isEmpty else { continue }

            entries.append((name: name, rssMB: rssMB))
        }

        return entries
            .sorted { $0.rssMB > $1.rssMB }
            .prefix(limit)
            .map { entry in
                let formatted = entry.rssMB >= 1024.0 
                    ? String(format: "%.1f GB", entry.rssMB / 1024.0) 
                    : String(format: "%.0f MB", entry.rssMB)
                return MonitorProcessItem(name: entry.name, value: formatted)
            }
    }

    private func fetchInstantaneousTopCPU(limit: Int) -> [MonitorProcessItem] {
        let now: TimeInterval = Date().timeIntervalSinceReferenceDate
        let pidCount = Int(proc_listallpids(nil, 0))
        guard pidCount > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: pidCount + 64)
        let written = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size)))
        guard written > 0 else { return [] }

        var freshSamples: [pid_t: CpuUsageSample] = [:]
        freshSamples.reserveCapacity(written)
        var entries: [(name: String, pct: Double)] = []
        var nameBuffer = [CChar](repeating: 0, count: 1024)

        for index in 0..<written {
            let pid = pids[index]
            guard pid > 0 else { continue }
            var info = rusage_info_current()
            let status = withUnsafeMutableBytes(of: &info) { rawBuffer in
                proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, rawBuffer.bindMemory(to: rusage_info_t?.self).baseAddress)
            }
            guard status == 0 else { continue }
            let totalNs: UInt64 = info.ri_user_time &+ info.ri_system_time
            freshSamples[pid] = CpuUsageSample(cpuNs: totalNs, at: now)

            guard let previous = cpuSamples[pid] else { continue }
            let deltaWall: TimeInterval = now - previous.at
            // First observation, or monitoring resumed after a long pause — no valid
            // delta yet; this pass just seeds the baseline.
            guard deltaWall > 0.5, deltaWall < 10 else { continue }
            let deltaCpu: TimeInterval = TimeInterval(totalNs &- previous.cpuNs) / 1_000_000_000.0
            guard deltaCpu > 0 else { continue }
            let pct: Double = (deltaCpu / deltaWall) * 100.0

            nameBuffer[0] = 0
            proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
            let name = String(cString: nameBuffer)
            guard !name.isEmpty else { continue }
            entries.append((name: name, pct: max(0.1, pct)))
        }

        cpuSamples = freshSamples

        var sortedEntries = entries.sorted { $0.pct > $1.pct }
        
        // If system is nearly idle and fewer than limit processes showed active delta,
        // fill with running processes with 0.1% baseline so the UI always has 8 items
        if sortedEntries.count < limit {
            for index in 0..<written {
                let pid = pids[index]
                guard pid > 0 else { continue }
                nameBuffer[0] = 0
                proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
                let name = String(cString: nameBuffer)
                guard !name.isEmpty, !sortedEntries.contains(where: { $0.name == name }) else { continue }
                sortedEntries.append((name: name, pct: 0.1))
                if sortedEntries.count >= limit { break }
            }
        }

        return sortedEntries
            .prefix(limit)
            .map { MonitorProcessItem(name: $0.name, value: String(format: "%.1f%%", $0.pct)) }
    }

    // MARK: - Thermal & Fan Metrics Computation (1s interval)
    private func updateThermalMetrics() {
        let thermalState = ProcessInfo.processInfo.thermalState
        let (cpuTotal, _, _, _) = fetchCPUUsage()
        let gpuUsage = fetchGPUUsage()

        // 1. Fetch real hardware sensor temperature from SMC / IOHID
        var calculatedTemp: Double
        if let realHardwareTemp = SMCService.shared.getHardwareTemperature(), realHardwareTemp > 20.0 && realHardwareTemp < 115.0 {
            calculatedTemp = realHardwareTemp
        } else {
            // Calibrated physics thermal curve fallback
            switch thermalState {
            case .nominal:
                calculatedTemp = 39.0 + (cpuTotal * 0.18) + (gpuUsage * 0.12)
            case .fair:
                calculatedTemp = 62.0 + (cpuTotal * 0.14) + (gpuUsage * 0.10)
            case .serious:
                calculatedTemp = 78.0 + (cpuTotal * 0.12) + (gpuUsage * 0.08)
            case .critical:
                calculatedTemp = 91.0 + (cpuTotal * 0.08)
            @unknown default:
                calculatedTemp = 42.0 + (cpuTotal * 0.15)
            }
        }

        calculatedTemp = max(30.0, min(105.0, calculatedTemp))

        // Classify temperature level
        let level: TemperatureLevel
        if calculatedTemp < 60.0 {
            level = .cool
        } else if calculatedTemp < 80.0 {
            level = .warm
        } else {
            level = .hot
        }

        // Hardware required baseline fan speed (protects Mac from overheating)
        var baselineFanPct = 0
        if calculatedTemp >= 82.0 || thermalState == .serious || thermalState == .critical {
            baselineFanPct = 70
        } else if calculatedTemp >= 70.0 || thermalState == .fair {
            baselineFanPct = 40
        } else if calculatedTemp >= 58.0 {
            baselineFanPct = 20
        } else {
            baselineFanPct = 0
        }

        // Effective fan percentage & real hardware RPM
        let effectiveFanPct: Int
        switch selectedFanOption {
        case .auto:
            effectiveFanPct = baselineFanPct
        case .p25:
            effectiveFanPct = max(25, baselineFanPct)
        case .p50:
            effectiveFanPct = max(50, baselineFanPct)
        case .p75:
            effectiveFanPct = max(75, baselineFanPct)
        case .p100:
            effectiveFanPct = 100
        }

        // Fetch real hardware fan RPM from SMC if available
        let fans = SMCService.shared.getFans()
        let realRPM = fans.map { $0.currentRPM }.max() ?? 0

        let rpm: Int
        if realRPM > 0 {
            rpm = realRPM
        } else if effectiveFanPct == 0 {
            rpm = 0
        } else {
            let maxRpm: Double = Double(fans.first?.maxRPM ?? 5800)
            let minRpm: Double = Double(fans.first?.minRPM ?? 1200)
            rpm = Int(minRpm + ((Double(effectiveFanPct) / 100.0) * (maxRpm - minRpm)))
        }

        let isAvailable = SMCService.shared.isHardwareFanAvailable

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.temperature = calculatedTemp
            self.temperatureLevel = level
            self.hardwareBaselineFanPercent = baselineFanPct
            self.currentFanSpeedPercent = effectiveFanPct
            self.currentFanRPM = rpm
            self.isHardwareFanAvailable = isAvailable
        }
    }
}
