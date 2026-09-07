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

    // MARK: - RAM Properties
    @Published public var ramUsedGB: Double = 0.0
    @Published public var ramTotalGB: Double = 0.0
    @Published public var ramPercentage: Double = 0.0
    @Published public var ramAppGB: Double = 0.0
    @Published public var ramWiredGB: Double = 0.0
    @Published public var ramCompressedGB: Double = 0.0
    @Published public var ramFreeGB: Double = 0.0
    @Published public var ramPressure: String = "Normal"
    @Published public var ramHistory: [Double] = Array(repeating: 50.0, count: 24)
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

    // MARK: - Top Processes
    @Published public var topCpuProcesses: [MonitorProcessItem] = []
    @Published public var topRamProcesses: [MonitorProcessItem] = []

    // MARK: - Internal State
    private var previousCpuLoadInfo: host_cpu_load_info?
    private var timer: Timer?
    private var activeSubscribers: Int = 0
    private let queue = DispatchQueue(label: "com.notchpulse.systemmonitor", qos: .utility)

    private init() {
        // Detect GPU Name once
        detectGPUModel()
        // Initialize total RAM
        ramTotalGB = Double(ProcessInfo.processInfo.physicalMemory) / (1024 * 1024 * 1024)
    }

    public func startMonitoring() {
        DispatchQueue.main.async {
            self.activeSubscribers += 1
            if self.timer == nil {
                self.updateMetrics() // Immediate update
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
            self.activeSubscribers = max(0, self.activeSubscribers - 1)
            if self.activeSubscribers == 0 {
                self.timer?.invalidate()
                self.timer = nil
            }
        }
    }

    // MARK: - Metrics Fetching
    private func updateMetrics() {
        let (totalCPU, userCPU, sysCPU, idleCPU) = fetchCPUUsage()
        let (usedRAM, totalRAM, percentRAM, appRAM, wiredRAM, compRAM, freeRAM, pressure) = fetchRAMUsage()
        let (usedSwap, totalSwap) = fetchSwapUsage()
        let gpu = fetchGPUUsage()
        let (topCpu, topRam) = fetchTopProcesses()

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
            self.ramHistory.append(percentRAM)
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
    private func fetchRAMUsage() -> (used: Double, total: Double, percent: Double, app: Double, wired: Double, comp: Double, free: Double, pressure: String) {
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
            return (0.0, totalGB, 0.0, 0.0, 0.0, 0.0, totalGB, "Normal")
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
        if percent > 85.0 || compGB > 3.0 {
            pressure = "Critical"
        } else if percent > 70.0 || compGB > 1.0 {
            pressure = "Warning"
        }

        return (usedGB, totalGB, percent, appGB, wiredGB, compGB, freeGB, pressure)
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
    private func fetchTopProcesses() -> (cpu: [MonitorProcessItem], ram: [MonitorProcessItem]) {
        let task = Process()
        task.launchPath = "/bin/ps"
        task.arguments = ["-Aceo", "%cpu,rss,comm", "-r"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                var lines = output.components(separatedBy: "\n")
                if !lines.isEmpty { lines.removeFirst() } // Remove header
                
                var cpuList: [MonitorProcessItem] = []
                var ramList: [(name: String, rssMB: Double)] = []

                for line in lines.prefix(20) {
                    let parts = line.trimmingCharacters(in: .whitespaces)
                        .components(separatedBy: .whitespaces)
                        .filter { !$0.isEmpty }
                    guard parts.count >= 3,
                          let cpuVal = Double(parts[0]),
                          let rssKB = Double(parts[1]) else { continue }
                    
                    let fullPath = parts[2...].joined(separator: " ")
                    let name = (fullPath as NSString).lastPathComponent

                    if cpuList.count < 3 && cpuVal > 0.1 {
                        cpuList.append(MonitorProcessItem(name: name, value: String(format: "%.1f%%", cpuVal)))
                    }

                    let mb = rssKB / 1024.0
                    ramList.append((name: name, rssMB: mb))
                }

                ramList.sort { $0.rssMB > $1.rssMB }
                let finalRam = ramList.prefix(3).map { item -> MonitorProcessItem in
                    let valStr = item.rssMB > 1024.0
                        ? String(format: "%.1f GB", item.rssMB / 1024.0)
                        : String(format: "%.0f MB", item.rssMB)
                    return MonitorProcessItem(name: item.name, value: valStr)
                }

                return (cpuList, finalRam)
            }
        } catch {
            // Fallback empty
        }

        return ([], [])
    }
}
