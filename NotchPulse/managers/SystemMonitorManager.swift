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

public enum NotchPulseFanProfile: String, CaseIterable, Identifiable {
    case auto = "auto"
    case balanced = "balanced"
    case smart = "smart"
    case max = "max"
    case custom = "custom"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .auto: return "Auto"
        case .balanced: return "Balanced"
        case .smart: return "Smart"
        case .max: return "Max"
        case .custom: return "Custom"
        }
    }

    public var description: String {
        switch self {
        case .auto: return "Theo máy (Apple Auto)"
        case .balanced: return "Cân bằng nhiệt - ồn (Tối đa 60%)"
        case .smart: return "Tự thích ứng & đón đầu nhiệt độ"
        case .max: return "Tản nhiệt tối đa 100%"
        case .custom: return "Tự chỉnh thủ công"
        }
    }
}

public typealias FanSpeedOption = NotchPulseFanProfile

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

@_silgen_name("memorystatus_get_level")
private func memorystatus_get_level(_ level: UnsafeMutablePointer<Int32>) -> Int32

public class SystemMonitorManager: ObservableObject {
    public static let shared = SystemMonitorManager()

    // MARK: - CPU Properties
    @Published public var cpuTotal: Double = 0.0
    @Published public var cpuUser: Double = 0.0
    @Published public var cpuSystem: Double = 0.0
    @Published public var cpuIdle: Double = 100.0
    @Published public var cpuHistory: [Double] = Array(repeating: 0.0, count: 32)
    @Published public var cpuSystemHistory: [Double] = Array(repeating: 0.0, count: 32)

    // MARK: - RAM Properties
    @Published public var ramUsedGB: Double = 0.0
    @Published public var ramTotalGB: Double = 0.0
    @Published public var ramPercentage: Double = 0.0
    @Published public var ramAppGB: Double = 0.0
    @Published public var ramWiredGB: Double = 0.0
    @Published public var ramCompressedGB: Double = 0.0
    @Published public var ramFreeGB: Double = 0.0
    @Published public var ramPressure: String = "Normal"
    @Published public var ramHistory: [Double] = Array(repeating: 0.0, count: 32)
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
    @Published public var gpuHistory: [Double] = Array(repeating: 0.0, count: 32)

    // MARK: - Thermal & Fan Properties
    @Published public var temperature: Double = 0.0
    @Published public var temperatureLevel: TemperatureLevel = .cool
    @Published public var currentFanSpeedPercent: Int = 0
    @Published public var currentFanRPM: Int = 0
    @Published public var currentFanMaxRPM: Int = 6550
    @Published public var hardwareBaselineFanPercent: Int = 0
    @Published public var selectedFanProfile: NotchPulseFanProfile = .auto
    @Published public var customFanPercent: Int = 50
    @Published public var isThermalMonitoring: Bool = false
    @Published public var isHardwareFanAvailable: Bool = false

    public static let fanProfileDefaultsKey = "notchpulse.fan_profile"
    public static let fanCustomPercentDefaultsKey = "notchpulse.fan_custom_percent"

    public var selectedFanOption: FanSpeedOption {
        get { selectedFanProfile }
        set { selectedFanProfile = newValue }
    }

    // Thermal regulation state
    private var temperatureHistory: [Double] = []
    private var lastRampPercent: Double = 0.0
    private var sustainedTicksCount: Int = 0
    private var fansCurrentlyRunning: Bool = false
    private var lastThermalTickTime: Date?
    private var backgroundProfileTimer: DispatchSourceTimer?
    private let backgroundEngineQueue = DispatchQueue(label: "com.notchpulse.fanprofile.engine", qos: .utility)

    // MARK: - Top Processes
    @Published public var topCpuProcesses: [MonitorProcessItem] = []
    @Published public var topRamProcesses: [MonitorProcessItem] = []
    public var shouldFetchProcesses: Bool = false

    // MARK: - Internal State
    private var previousCpuLoadInfo: host_cpu_load_info?
    private var previousProcessCPUTimes: [pid_t: (cpuNs: UInt64, time: UInt64)] = [:]
    private var processNameCache: [pid_t: String] = [:]
    private var timer: Timer?
    private var thermalTimer: Timer?
    private var isMonitoring: Bool = false
    private let queue = DispatchQueue(label: "com.notchpulse.systemmonitor", qos: .utility)

    private init() {
        // Detect GPU Name once
        detectGPUModel()
        // Initialize total RAM
        let total = Double(ProcessInfo.processInfo.physicalMemory) / (1024 * 1024 * 1024)
        ramTotalGB = total

        // Pre-seed baseline metrics so the initial view reflects the user's real hardware state
        let (usedRAM, _, percentRAM, appRAM, wiredRAM, compRAM, freeRAM, pressure, pressurePercent) = fetchRAMUsage()
        self.ramUsedGB = usedRAM
        self.ramPercentage = percentRAM
        self.ramAppGB = appRAM
        self.ramWiredGB = wiredRAM
        self.ramCompressedGB = compRAM
        self.ramFreeGB = freeRAM
        self.ramPressure = pressure
        self.ramHistory = Array(repeating: pressurePercent, count: 32)

        // Seed initial CPU load info for delta computation
        _ = fetchCPUUsage()
        let initialGpu = fetchGPUUsage()
        self.gpuUsage = initialGpu
        self.gpuHistory = Array(repeating: initialGpu, count: 32)

        if let initialTemp = SMCService.shared.getHardwareTemperature(), initialTemp > 20.0 && initialTemp < 115.0 {
            self.temperature = initialTemp
            if initialTemp < 60.0 {
                self.temperatureLevel = .cool
            } else if initialTemp < 80.0 {
                self.temperatureLevel = .warm
            } else {
                self.temperatureLevel = .hot
            }
        }

        // Restore fan profile and custom percentage from persistent storage
        if let savedRaw = UserDefaults.standard.string(forKey: Self.fanProfileDefaultsKey),
           let savedProfile = NotchPulseFanProfile(rawValue: savedRaw) {
            self.selectedFanProfile = savedProfile
        }
        if UserDefaults.standard.object(forKey: Self.fanCustomPercentDefaultsKey) != nil {
            self.customFanPercent = max(0, min(100, UserDefaults.standard.integer(forKey: Self.fanCustomPercentDefaultsKey)))
        }
        if self.selectedFanProfile != .auto {
            FanHelperManager.shared.startBackgroundHeartbeat()
            startBackgroundProfileEngine()
        }
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
                self.timer?.tolerance = 0.2
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
            self.thermalTimer?.tolerance = 0.15
        }
    }

    public func stopThermalMonitoring() {
        DispatchQueue.main.async {
            self.isThermalMonitoring = false
            self.thermalTimer?.invalidate()
            self.thermalTimer = nil
        }
    }

    public func setFanProfile(_ profile: NotchPulseFanProfile) {
        self.selectedFanProfile = profile
        UserDefaults.standard.set(profile.rawValue, forKey: Self.fanProfileDefaultsKey)
        if profile != .auto {
            FanHelperManager.shared.ensureHelperUpToDate()
            FanHelperManager.shared.startBackgroundHeartbeat()
            startBackgroundProfileEngine()
        } else {
            FanHelperManager.shared.stopBackgroundHeartbeat()
            FanHelperManager.shared.sendCommand("auto")
            stopBackgroundProfileEngine()
        }
        self.queue.async { [weak self] in
            guard let self = self else { return }
            self.sustainedTicksCount = 0
            self.lastRampPercent = 0
            self.fansCurrentlyRunning = false
            self.temperatureHistory.removeAll()
            self.updateThermalMetrics()
        }
    }

    public func setFanOption(_ option: FanSpeedOption) {
        setFanProfile(option)
    }

    public func setCustomFanPercent(_ percent: Int) {
        let clamped = max(0, min(100, percent))
        self.customFanPercent = clamped
        UserDefaults.standard.set(clamped, forKey: Self.fanCustomPercentDefaultsKey)
        self.selectedFanProfile = .custom
        UserDefaults.standard.set(NotchPulseFanProfile.custom.rawValue, forKey: Self.fanProfileDefaultsKey)
        FanHelperManager.shared.ensureHelperUpToDate()
        FanHelperManager.shared.startBackgroundHeartbeat()
        startBackgroundProfileEngine()
        self.queue.async { [weak self] in
            guard let self = self else { return }
            self.sustainedTicksCount = 0
            self.fansCurrentlyRunning = false
            self.lastRampPercent = 0
            self.updateThermalMetrics()
        }
    }

    public func reapplyActiveProfileOnWake() {
        guard selectedFanProfile != .auto else { return }
        self.queue.async { [weak self] in
            guard let self = self else { return }
            self.sustainedTicksCount = 0
            self.fansCurrentlyRunning = false
            self.lastRampPercent = 0
            self.updateThermalMetrics()
        }
    }

    private func startBackgroundProfileEngine() {
        backgroundEngineQueue.async { [weak self] in
            guard let self = self else { return }
            self.backgroundProfileTimer?.cancel()
            let timer = DispatchSource.makeTimerSource(queue: self.backgroundEngineQueue)
            timer.schedule(deadline: .now() + 2.0, repeating: 2.0)
            timer.setEventHandler { [weak self] in
                guard let self = self else { return }
                guard !self.isThermalMonitoring else { return }
                self.queue.async {
                    self.updateThermalMetrics()
                }
            }
            timer.resume()
            self.backgroundProfileTimer = timer
        }
    }

    private func stopBackgroundProfileEngine() {
        backgroundEngineQueue.async { [weak self] in
            self?.backgroundProfileTimer?.cancel()
            self?.backgroundProfileTimer = nil
        }
    }

    public func requestMetricsUpdate() {
        queue.async { [weak self] in
            self?.updateMetrics()
        }
    }

    // MARK: - Metrics Fetching
    private func updateMetrics() {
        let (totalCPU, userCPU, sysCPU, idleCPU) = fetchCPUUsage()
        let (usedRAM, totalRAM, percentRAM, appRAM, wiredRAM, compRAM, freeRAM, pressure, pressurePercent) = fetchRAMUsage()
        let (usedSwap, totalSwap) = fetchSwapUsage()
        let gpu = fetchGPUUsage()

        // Read real hardware temperature sensor from SMC / IOHID for compact live display
        var hwTemp: Double? = nil
        var hwTempLevel: TemperatureLevel = .cool
        if let realTemp = SMCService.shared.getHardwareTemperature(), realTemp > 20.0 && realTemp < 115.0 {
            let clamped = min(115.0, max(20.0, realTemp))
            hwTemp = clamped
            if clamped < 60.0 {
                hwTempLevel = .cool
            } else if clamped < 80.0 {
                hwTempLevel = .warm
            } else {
                hwTempLevel = .hot
            }
        }

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
            if self.cpuHistory.count > 32 {
                self.cpuHistory.removeFirst()
            }
            self.cpuSystemHistory.append(sysCPU)
            if self.cpuSystemHistory.count > 32 {
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
            if self.ramHistory.count > 32 {
                self.ramHistory.removeFirst()
            }

            // Update GPU
            self.gpuUsage = gpu
            self.gpuHistory.append(gpu)
            if self.gpuHistory.count > 32 {
                self.gpuHistory.removeFirst()
            }

            // Update Temperature
            if let temp = hwTemp {
                self.temperature = temp
                self.temperatureLevel = hwTempLevel
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

        return (0.0, 0.0, 0.0, 100.0)
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

        // Apple Darwin Memorystatus Level API (same kernel API utilized by macOS /usr/bin/memory_pressure)
        var kernelFreePercent: Int32 = 0
        var kernelPressure: Double? = nil
        if memorystatus_get_level(&kernelFreePercent) == 0 && kernelFreePercent > 0 && kernelFreePercent <= 100 {
            kernelPressure = Double(100 - kernelFreePercent)
        }

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
        let baseline: Double
        if let kp = kernelPressure {
            baseline = kp
        } else {
            switch pressure {
            case "Critical":
                baseline = min(100.0, 80.0 + (percent / 100.0) * 20.0)
            case "Warning":
                baseline = min(75.0, 55.0 + (percent / 100.0) * 20.0)
            default:
                let baseRatio = (wiredBytes + compBytes) / Double(totalBytes)
                baseline = min(45.0, max(18.0, baseRatio * 100.0 + 10.0))
            }
        }

        // Real-time VM page dynamics (active page load & compression ratio)
        // This produces Apple Activity Monitor's organic micro-fluctuations over time
        let totalPages = max(1.0, Double(ProcessInfo.processInfo.physicalMemory / UInt64(vm_kernel_page_size)))
        let activeRatio = Double(vmStats.active_count) / totalPages
        let dynamicOffset = (activeRatio - 0.27) * 28.0
        let pressurePercent = min(100.0, max(5.0, baseline + dynamicOffset))

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

    // MARK: - Top Processes Fetch (Zero-Process-Spawn In-Memory Darwin Kernel Architecture)

    private struct RawProcessEntry {
        let pid: pid_t
        let ppid: pid_t
        let cpu: Double
        let memoryBytes: UInt64
        let comm: String
    }

    private func fetchTopProcesses() -> (cpu: [MonitorProcessItem], ram: [MonitorProcessItem]) {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else {
            return ([], [])
        }

        let count = size / MemoryLayout<kinfo_proc>.stride
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: count)
        guard sysctl(&mib, 4, &procs, &size, nil, 0) == 0 else {
            return ([], [])
        }

        let actualCount = size / MemoryLayout<kinfo_proc>.stride
        let now = mach_absolute_time()
        var timebase = mach_timebase_info()
        mach_timebase_info(&timebase)

        var entries: [RawProcessEntry] = []
        entries.reserveCapacity(actualCount)
        var currentPids = Set<pid_t>()

        for i in 0..<actualCount {
            let proc = procs[i]
            let pid = proc.kp_proc.p_pid
            let ppid = proc.kp_eproc.e_ppid
            guard pid > 0 else { continue }
            currentPids.insert(pid)

            let comm = withUnsafePointer(to: proc.kp_proc.p_comm) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN)) {
                    String(cString: $0)
                }
            }
            guard !comm.isEmpty, comm != "kernel_task" else { continue }

            var taskInfo = proc_taskinfo()
            let infoSize = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, Int32(MemoryLayout<proc_taskinfo>.stride))
            guard infoSize > 0 else { continue }

            let totalCpuNs = taskInfo.pti_total_user + taskInfo.pti_total_system

            // 1. Physical Footprint query (Activity Monitor standard) via Darwin libproc
            // OPTIMIZATION: Only call proc_pid_rusage for processes with > 15MB resident memory.
            // Tiny background daemons (<15MB) never qualify for top 8 RAM on macOS, eliminating 95% of syscalls.
            var memoryBytes = taskInfo.pti_resident_size
            if memoryBytes > 15 * 1024 * 1024 {
                var rusage = rusage_info_v4()
                let rusageRes = withUnsafeMutablePointer(to: &rusage) { ptr in
                    proc_pid_rusage(pid, RUSAGE_INFO_V4, UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: (rusage_info_t?).self))
                }
                if rusageRes == 0 && rusage.ri_phys_footprint > 0 {
                    memoryBytes = rusage.ri_phys_footprint
                }
            }

            var cpuPct = 0.0
            if let (prevCpuNs, prevTime) = previousProcessCPUTimes[pid] {
                let cpuDelta = Double(totalCpuNs > prevCpuNs ? totalCpuNs - prevCpuNs : 0)
                let timeDeltaNs = Double(now - prevTime) * Double(timebase.numer) / Double(timebase.denom)
                // Filter out stale intervals (> 3.5s) to guarantee instantaneous rate
                if timeDeltaNs > 0 && timeDeltaNs < 3.5 * 1_000_000_000 {
                    cpuPct = (cpuDelta / timeDeltaNs) * 100.0
                }
            }
            previousProcessCPUTimes[pid] = (totalCpuNs, now)

            entries.append(RawProcessEntry(pid: pid, ppid: ppid, cpu: cpuPct, memoryBytes: memoryBytes, comm: comm))
        }

        // Periodically purge terminated PIDs from cache to prevent unbounded growth
        if previousProcessCPUTimes.count > 1500 {
            previousProcessCPUTimes = previousProcessCPUTimes.filter { currentPids.contains($0.key) }
            processNameCache = processNameCache.filter { currentPids.contains($0.key) }
        }

        func resolveFriendlyName(_ p: RawProcessEntry) -> String {
            if let cached = processNameCache[p.pid] {
                return cached
            }

            if let app = NSRunningApplication(processIdentifier: p.pid), let name = app.localizedName, !name.isEmpty {
                processNameCache[p.pid] = name
                return name
            }

            // Fallback: resolve binary name via proc_pidpath only for top candidates
            var resolvedName = p.comm
            var pathBuffer = [CChar](repeating: 0, count: 1024)
            let pathLen = proc_pidpath(p.pid, &pathBuffer, 1024)
            if pathLen > 0 {
                let fullPath = String(cString: pathBuffer)
                let lastComp = (fullPath as NSString).lastPathComponent
                if !lastComp.isEmpty {
                    resolvedName = lastComp
                }
            } else {
                var nameBuffer = [CChar](repeating: 0, count: 256)
                let nameLen = proc_name(p.pid, &nameBuffer, 256)
                if nameLen > 0 {
                    let name = String(cString: nameBuffer)
                    if !name.isEmpty {
                        resolvedName = name
                    }
                }
            }

            if p.ppid > 1, let parentApp = NSRunningApplication(processIdentifier: p.ppid), let parentName = parentApp.localizedName, !parentName.isEmpty {
                if resolvedName.contains("Renderer") {
                    resolvedName = "\(parentName) (Renderer)"
                } else if resolvedName.contains("GPU") {
                    resolvedName = "\(parentName) (GPU)"
                } else if resolvedName.contains("Plugin") {
                    resolvedName = "\(parentName) (Plugin)"
                } else if resolvedName.contains("Helper") {
                    resolvedName = "\(parentName) Helper"
                }
            }
            if resolvedName.hasPrefix("com.apple.") {
                resolvedName = resolvedName.replacingOccurrences(of: "com.apple.", with: "")
            }

            processNameCache[p.pid] = resolvedName
            return resolvedName
        }

        let topCpu = entries
            .sorted { $0.cpu > $1.cpu }
            .prefix(8)
            .map { p in
                MonitorProcessItem(
                    name: resolveFriendlyName(p),
                    value: String(format: "%.1f%%", p.cpu)
                )
            }

        let topRam = entries
            .sorted { $0.memoryBytes > $1.memoryBytes }
            .prefix(8)
            .map { p in
                let mb = Double(p.memoryBytes) / (1024.0 * 1024.0)
                let formatted = mb >= 1024.0
                    ? String(format: "%.1f GB", mb / 1024.0)
                    : String(format: "%.0f MB", mb)
                return MonitorProcessItem(
                    name: resolveFriendlyName(p),
                    value: formatted
                )
            }

        return (Array(topCpu), Array(topRam))
    }

    // MARK: - Thermal & Fan Metrics Computation (1s interval)
    private func updateThermalMetrics() {
        let thermalState = ProcessInfo.processInfo.thermalState
        _ = fetchCPUUsage()
        _ = fetchGPUUsage()

        // 1. Fetch real hardware sensor temperature from SMC / IOHID
        guard let realHardwareTemp = SMCService.shared.getHardwareTemperature(), realHardwareTemp > 20.0 && realHardwareTemp < 115.0 else {
            // No real hardware temperature sensors found on this machine — strictly refuse to fabricate fake readings
            DispatchQueue.main.async { [weak self] in
                self?.temperature = 0.0
                self?.temperatureLevel = .cool
            }
            return
        }
        let calculatedTemp = min(115.0, max(20.0, realHardwareTemp))

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

        // ═══════════════════════════════════════════════════════════════════
        // Hardware Thermal Regulation Engine
        // ═══════════════════════════════════════════════════════════════════

        // Compute elapsed time since last tick for time-based ramp governor
        let now = Date()
        let elapsed: Double
        if let lastTime = lastThermalTickTime {
            elapsed = min(5.0, max(0.1, now.timeIntervalSince(lastTime)))
        } else {
            elapsed = 1.0
        }
        lastThermalTickTime = now

        // Fetch real hardware fan data from SMC
        let fans = SMCService.shared.getFans()
        let realRPM = fans.map { $0.currentRPM }.max() ?? 0
        let maxRpm: Double = Double(fans.first?.maxRPM ?? 6550)
        let minRpm: Double = Double(fans.first?.minRPM ?? 2000)
        let minPct = minRpm / maxRpm
        let isAvailable = SMCService.shared.isHardwareFanAvailable || (fans.count > 0 && maxRpm > 0)

        // Temperature history for rate-of-change (Smart profile)
        temperatureHistory.append(calculatedTemp)
        if temperatureHistory.count > 8 {
            temperatureHistory.removeFirst()
        }

        // Rate of change in °C/s: sampled at monitor cadence
        let rateOfChange: Double
        if temperatureHistory.count >= 2 {
            let seconds = Double(temperatureHistory.count - 1) * elapsed
            rateOfChange = (temperatureHistory.last! - temperatureHistory.first!) / max(1.0, seconds)
        } else {
            rateOfChange = 0.0
        }

        // Safety override: any sensor > 95°C → force max safety threshold
        let safetyThreshold = 95.0
        let safetyHysteresis = 5.0
        if calculatedTemp >= safetyThreshold {
            if !fansCurrentlyRunning || lastRampPercent < 1.0 {
                FanHelperManager.shared.sendCommand("max")
                fansCurrentlyRunning = true
                lastRampPercent = 1.0
            }
            FanHelperManager.shared.sendHeartbeat()
            let effectiveFanPct = 100
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.temperature = calculatedTemp
                self.temperatureLevel = level
                self.hardwareBaselineFanPercent = baselineFanPct
                self.currentFanSpeedPercent = effectiveFanPct
                self.currentFanRPM = realRPM
                self.currentFanMaxRPM = Int(maxRpm)
                self.isHardwareFanAvailable = isAvailable
            }
            return
        }
        // Clear safety with hysteresis band
        if lastRampPercent >= 1.0 && calculatedTemp >= (safetyThreshold - safetyHysteresis) && fansCurrentlyRunning {
            // Still in safety hysteresis band — maintain max
            FanHelperManager.shared.sendHeartbeat()
            let effectiveFanPct = 100
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.temperature = calculatedTemp
                self.temperatureLevel = level
                self.hardwareBaselineFanPercent = baselineFanPct
                self.currentFanSpeedPercent = effectiveFanPct
                self.currentFanRPM = realRPM
                self.currentFanMaxRPM = Int(maxRpm)
                self.isHardwareFanAvailable = isAvailable
            }
            return
        }

        // Per-profile thermal constants
        let stopTemp: Double    // Below this: fans off
        let startTemp: Double   // Above this: fans engage (after sustained)
        let ceilingTemp: Double // Fans at maxPercent
        let maxPercent: Double  // Max fan fraction for this profile
        let rampUpPerSec: Double
        let rampDownPerSec: Double
        let sustainedTriggerSec: Double

        switch selectedFanProfile {
        case .balanced:
            stopTemp = 50.0; startTemp = 55.0; ceilingTemp = 70.0; maxPercent = 0.60
            rampUpPerSec = 0.05; rampDownPerSec = 0.025; sustainedTriggerSec = 8.0
        case .smart:
            stopTemp = 50.0; startTemp = 53.0; ceilingTemp = 85.0; maxPercent = 1.0
            rampUpPerSec = 0.05; rampDownPerSec = 0.025; sustainedTriggerSec = 6.0
        case .max:
            stopTemp = 50.0; startTemp = 0.0; ceilingTemp = 65.0; maxPercent = 1.0
            rampUpPerSec = 1.0; rampDownPerSec = 0.025; sustainedTriggerSec = 0.0
        case .custom:
            stopTemp = 0.0; startTemp = 0.0; ceilingTemp = 0.0; maxPercent = Double(customFanPercent) / 100.0
            rampUpPerSec = 1.0; rampDownPerSec = 1.0; sustainedTriggerSec = 0.0
        case .auto:
            stopTemp = 0.0; startTemp = 0.0; ceilingTemp = 0.0; maxPercent = 0.0
            rampUpPerSec = 0.0; rampDownPerSec = 0.0; sustainedTriggerSec = 0.0
        }

        // Sustained trigger: track consecutive ticks above start threshold
        if selectedFanProfile != .auto {
            if calculatedTemp >= startTemp {
                sustainedTicksCount += 1
            } else {
                sustainedTicksCount = 0
            }
        }

        // ── Auto profile: hand control to Apple, no manual fan commands ──
        if selectedFanProfile == .auto {
            if fansCurrentlyRunning {
                FanHelperManager.shared.sendCommand("auto")
                fansCurrentlyRunning = false
                lastRampPercent = 0
            }
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.temperature = calculatedTemp
                self.temperatureLevel = level
                self.hardwareBaselineFanPercent = baselineFanPct
                self.currentFanSpeedPercent = 0
                self.currentFanRPM = realRPM
                self.currentFanMaxRPM = Int(maxRpm)
                self.isHardwareFanAvailable = isAvailable
            }
            return
        }

        // ── Max profile: instant 100% always ──
        if selectedFanProfile == .max {
            if !fansCurrentlyRunning || realRPM == 0 {
                let success = FanHelperManager.shared.sendCommand("max")
                if success {
                    fansCurrentlyRunning = true
                    lastRampPercent = 1.0
                } else {
                    fansCurrentlyRunning = false
                }
            }
            FanHelperManager.shared.sendHeartbeat()
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.temperature = calculatedTemp
                self.temperatureLevel = level
                self.hardwareBaselineFanPercent = baselineFanPct
                self.currentFanSpeedPercent = 100
                self.currentFanRPM = realRPM
                self.currentFanMaxRPM = Int(maxRpm)
                self.isHardwareFanAvailable = isAvailable
            }
            return
        }

        // ── Custom profile: fixed percentage, direct set ──
        if selectedFanProfile == .custom {
            let targetPct = maxPercent
            let targetRPM = Int(minRpm + (targetPct * (maxRpm - minRpm)))
            let changed = abs(targetPct - lastRampPercent) > 0.002 || !fansCurrentlyRunning || (targetPct > 0.05 && realRPM == 0)
            if changed {
                let success = FanHelperManager.shared.sendCommand("set \(targetRPM)")
                if success {
                    lastRampPercent = targetPct
                    fansCurrentlyRunning = true
                } else {
                    fansCurrentlyRunning = false
                }
            }
            FanHelperManager.shared.sendHeartbeat()
            let effectiveFanPct = Int(round(lastRampPercent * 100.0))
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.temperature = calculatedTemp
                self.temperatureLevel = level
                self.hardwareBaselineFanPercent = baselineFanPct
                self.currentFanSpeedPercent = effectiveFanPct
                self.currentFanRPM = realRPM
                self.currentFanMaxRPM = Int(maxRpm)
                self.isHardwareFanAvailable = isAvailable
            }
            return
        }

        // ═══════════════════════════════════════════════════════════════
        // Balanced / Smart — curve-based thermal regulation
        // ═══════════════════════════════════════════════════════════════

        var targetPct: Double = 0.0
        var shouldTurnOff = false

        if selectedFanProfile == .smart {
            // ── Smart Profile ──

            // Below stop threshold AND fans running AND temp falling → turn off
            if calculatedTemp < stopTemp && fansCurrentlyRunning && rateOfChange <= 0 {
                shouldTurnOff = true
            }
            // Below start threshold AND not running → stay off
            else if calculatedTemp < startTemp && !fansCurrentlyRunning {
                // Do nothing, targetPct stays 0
            }
            // In hysteresis band (50-53°C) AND not running → stay off
            else if calculatedTemp >= stopTemp && calculatedTemp < startTemp && !fansCurrentlyRunning {
                // Do nothing
            }
            // Above start threshold: compute S-curve
            else {
                // Sustained trigger check
                let sustainedTicksNeeded = Int(sustainedTriggerSec / elapsed)
                if !fansCurrentlyRunning && sustainedTicksCount < sustainedTicksNeeded {
                    // Not enough sustained time yet — wait
                    targetPct = 0.0
                } else {
                    // S-curve: pos²(3-2pos) path
                    let range = ceilingTemp - startTemp  // 85 - 53 = 32
                    let position = min(max((calculatedTemp - startTemp) / range, 0), 1)
                    targetPct = position * position * (3.0 - 2.0 * position)

                    // Velocity booster: if temp rising, boost proportionally
                    if rateOfChange > 0 {
                        targetPct = min(targetPct + rateOfChange * 0.2, 1.0)
                    }

                    // Above ceiling → 100%
                    if calculatedTemp > ceilingTemp {
                        targetPct = 1.0
                    }

                    // Clamp and enforce minimum RPM fraction
                    targetPct = min(max(targetPct, 0), 1.0)
                    if targetPct > 0 && targetPct < minPct {
                        targetPct = minPct
                    }
                }
            }
        } else {
            // ── Balanced Profile ──

            // Step 1: Get raw target from curve
            var rawTarget: Double? = nil

            if calculatedTemp <= stopTemp && !fansCurrentlyRunning {
                rawTarget = nil  // Below stop, not running → stay off
            } else if calculatedTemp <= stopTemp && fansCurrentlyRunning {
                rawTarget = nil  // Below stop, was running → turn off
            } else if calculatedTemp > stopTemp && calculatedTemp < startTemp {
                // Hysteresis band: keep at minimum if running, stay off if not
                rawTarget = fansCurrentlyRunning ? 0.001 : nil
            } else if calculatedTemp >= ceilingTemp {
                rawTarget = maxPercent  // At/above ceiling → maxPercent (60%)
            } else if calculatedTemp >= startTemp {
                // easeIn curve: pos² × maxPercent
                let position = (calculatedTemp - startTemp) / (ceilingTemp - startTemp)
                rawTarget = position * position * maxPercent
            }

            // Step 2: Handle nil (fans should be off)
            if rawTarget == nil {
                if fansCurrentlyRunning {
                    shouldTurnOff = true
                }
                targetPct = 0.0
            } else {
                // Sustained trigger check
                let sustainedTicksNeeded = Int(sustainedTriggerSec / elapsed)
                if !fansCurrentlyRunning && sustainedTicksCount < sustainedTicksNeeded {
                    targetPct = 0.0
                } else {
                    // 0.001 signals "keep at minimum RPM" (hysteresis band)
                    targetPct = rawTarget! <= 0.001 ? minPct : rawTarget!
                    // Clamp to valid range
                    targetPct = min(max(targetPct, minPct), maxPercent)
                }
            }
        }

        // ── Handle fans-off transition (one-shot, not every tick) ──
        if shouldTurnOff {
            FanHelperManager.shared.sendCommand("auto")
            fansCurrentlyRunning = false
            lastRampPercent = 0
            let effectiveFanPct = 0
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.temperature = calculatedTemp
                self.temperatureLevel = level
                self.hardwareBaselineFanPercent = baselineFanPct
                self.currentFanSpeedPercent = effectiveFanPct
                self.currentFanRPM = realRPM
                self.currentFanMaxRPM = Int(maxRpm)
                self.isHardwareFanAvailable = isAvailable
            }
            return
        }

        // If targetPct is 0 and fans not running → nothing to do
        if targetPct <= 0 && !fansCurrentlyRunning {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.temperature = calculatedTemp
                self.temperatureLevel = level
                self.hardwareBaselineFanPercent = baselineFanPct
                self.currentFanSpeedPercent = 0
                self.currentFanRPM = realRPM
                self.currentFanMaxRPM = Int(maxRpm)
                self.isHardwareFanAvailable = isAvailable
            }
            return
        }

        // ── Ramp governor: per-profile rates × elapsed time ──
        let rampUp = rampUpPerSec * elapsed
        let rampDown = rampDownPerSec * elapsed

        if targetPct > lastRampPercent {
            targetPct = min(targetPct, lastRampPercent + rampUp)
        } else if targetPct < lastRampPercent {
            targetPct = max(targetPct, lastRampPercent - rampDown)
        }

        // Apply if changed meaningfully (threshold: 0.002)
        if abs(targetPct - lastRampPercent) > 0.002 || !fansCurrentlyRunning || (targetPct > 0.05 && realRPM == 0) {
            let targetRPM = max(Int(maxRpm * targetPct), Int(minRpm))
            let success = FanHelperManager.shared.sendCommand("set \(targetRPM)")
            if success {
                lastRampPercent = targetPct
                fansCurrentlyRunning = true
            } else {
                fansCurrentlyRunning = false
            }
        }

        // Keepalive heartbeat
        FanHelperManager.shared.sendHeartbeat()

        let effectiveFanPct = Int(round(lastRampPercent * 100.0))

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.temperature = calculatedTemp
            self.temperatureLevel = level
            self.hardwareBaselineFanPercent = baselineFanPct
            self.currentFanSpeedPercent = effectiveFanPct
            self.currentFanRPM = realRPM
            self.currentFanMaxRPM = Int(maxRpm)
            self.isHardwareFanAvailable = isAvailable
        }
    }
}
