import Foundation
import SwiftUI
import Combine
import IOKit
import IOKit.ps

@MainActor
final class NativeBatteryManager: ObservableObject {
    static let shared = NativeBatteryManager()
    
    // MARK: - Published Properties
    @Published var level: Int = 100
    @Published var isCharging: Bool = false
    @Published var isPluggedIn: Bool = false
    @Published var timeRemaining: Int = 0 // in minutes
    @Published var cycleCount: Int = 0
    @Published var healthPercent: Double = 100.0
    @Published var temperature: Double = 0.0 // in Celsius
    @Published var wattage: Double = 0.0 // Watts (+ charging, - discharging)
    @Published var voltage: Double = 0.0 // Volts
    @Published var amperage: Double = 0.0 // mA
    @Published var adapterWatts: Int = 0
    @Published var adapterName: String = "AC Power"
    @Published var isDesktopMode: Bool = false // Battery held, running on AC
    
    // MARK: - 3 Charging Modes (Matching BatteryToolkit)
    enum ChargingMode: String, CaseIterable, Identifiable {
        case toLimit = "toLimit"
        case toFull = "toFull"
        case inhibit = "inhibit"
        
        var id: String { rawValue }
        var title: String {
            switch self {
            case .toLimit: return "Charge to Limit"
            case .toFull: return "Charge to 100%"
            case .inhibit: return "Disable Charging"
            }
        }
        var icon: String {
            switch self {
            case .toLimit: return "battery.75"
            case .toFull: return "battery.100.bolt"
            case .inhibit: return "powerplug.fill"
            }
        }
        var subtitle: String {
            switch self {
            case .toLimit: return "Stops charging at limit & preserves battery"
            case .toFull: return "Continuously charges to 100%"
            case .inhibit: return "Direct AC power; charging is paused"
            }
        }
    }
    
    @Published var chargingMode: ChargingMode = .toLimit

    // Charge Limit Settings
    @Published var chargeLimitEnabled: Bool {
        didSet {
            UserDefaults.standard.set(chargeLimitEnabled, forKey: "NP_ChargeLimitEnabled")
            if isHelperInstalled {
                syncSettingsToDaemon()
            }
        }
    }
    
    @Published var chargeLimit: Int {
        didSet {
            UserDefaults.standard.set(chargeLimit, forKey: "NP_ChargeLimit")
            if isHelperInstalled {
                syncSettingsToDaemon()
            }
        }
    }
    
    @Published var isHelperInstalled: Bool = false
    @Published var isBusy: Bool = false
    @Published var helperStatusMessage: String = ""
    
    private var forceFullCharge: Bool = false
    private var cancellables = Set<AnyCancellable>()
    private var powerRunLoopSource: CFRunLoopSource?
    
    private var isMonitoring: Bool = false
    private var monitoringTimer: AnyCancellable?
    
    // Daemon health tracking
    private var enforcementFailCount: Int = 0
    private let maxEnforcementFailsBeforeRestart = 3
    private var lastHealthCheckDate: Date = .distantPast
    private let healthCheckInterval: TimeInterval = 30.0
    private var isReconnecting: Bool = false
    
    private init() {
        let savedMode = UserDefaults.standard.string(forKey: "NP_ChargingMode") ?? ChargingMode.toLimit.rawValue
        self.chargingMode = ChargingMode(rawValue: savedMode) ?? .toLimit
        self.chargeLimitEnabled = UserDefaults.standard.object(forKey: "NP_ChargeLimitEnabled") as? Bool ?? true
        self.chargeLimit = UserDefaults.standard.object(forKey: "NP_ChargeLimit") as? Int ?? 80
        
        updateBatteryStatus()
        setupPowerNotification()
        checkHelperInstalled()
    }
    
    deinit {
        monitoringTimer?.cancel()
        if let source = powerRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .defaultMode)
        }
    }
    
    // MARK: - On-Demand Polling (App Nap friendly)
    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        updateBatteryStatus()
        
        monitoringTimer = Timer.publish(every: 1.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateBatteryStatus()
            }
    }
    
    func stopMonitoring() {
        isMonitoring = false
        monitoringTimer?.cancel()
        monitoringTimer = nil
    }
    
    // MARK: - Native Battery Status Reader
    func updateBatteryStatus() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != IO_OBJECT_NULL else { return }
        defer { IOObjectRelease(service) }
        
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == kIOReturnSuccess,
              let dict = props?.takeRetainedValue() as? [String: Any] else {
            return
        }
        
        let currentCap = dict["CurrentCapacity"] as? Int ?? self.level
        let charging = (dict["IsCharging"] as? Bool) ?? false
        let extConnected = (dict["ExternalConnected"] as? Bool) ?? false
        let cycles = dict["CycleCount"] as? Int ?? self.cycleCount
        let designCap = dict["DesignCapacity"] as? Int ?? 1
        let nominalCap = dict["NominalChargeCapacity"] as? Int ?? designCap
        let health = min(100.0, (Double(nominalCap) / Double(max(designCap, 1))) * 100.0)
        
        let volt = Double(dict["Voltage"] as? Int ?? 0) / 1000.0
        let amp = Double(dict["Amperage"] as? Int ?? 0)
        let watts = (volt * amp) / 1000.0
        
        var temp: Double = self.temperature
        if let virtualTemp = dict["VirtualTemperature"] as? Double {
            temp = virtualTemp / 100.0
        } else if let rawTemp = dict["Temperature"] as? Double {
            temp = (rawTemp - 2731.5) / 10.0
        }
        
        var adWatts: Int = 0
        var adDesc: String = "AC Power"
        if let adapter = dict["AdapterDetails"] as? [String: Any] {
            adWatts = adapter["Watts"] as? Int ?? 0
            adDesc = adapter["Description"] as? String ?? "AC Power"
        }
        
        let timeRem = dict["TimeRemaining"] as? Int ?? 0
        
        // Charger inhibit check
        var isInhibited = false
        if let chargerData = dict["ChargerData"] as? [String: Any],
           let inhibitReason = chargerData["ChargerInhibitReason"] as? Int {
            isInhibited = (inhibitReason != 0)
        }
        
        self.level = currentCap
        self.isCharging = charging
        self.isPluggedIn = extConnected
        self.cycleCount = cycles
        self.healthPercent = health
        self.voltage = volt
        self.amperage = amp
        self.wattage = watts
        self.temperature = temp
        self.adapterWatts = adWatts
        self.adapterName = adDesc
        self.timeRemaining = timeRem
        self.isDesktopMode = extConnected && (!charging || isInhibited || (chargingMode == .toLimit && currentCap >= chargeLimit) || chargingMode == .inhibit)
        
        // Enforce charging limits if connected to power
        if extConnected && isHelperInstalled {
            if chargingMode == .toLimit && currentCap >= chargeLimit && charging {
                Task { [weak self] in
                    await self?.enforceDisableCharging(reason: "level \(currentCap)% >= limit \(self?.chargeLimit ?? 80)%")
                }
            } else if chargingMode == .inhibit && charging {
                Task { [weak self] in
                    await self?.enforceDisableCharging(reason: "inhibit mode active")
                }
            }
        }
        
        // Periodic daemon health check
        if isHelperInstalled && Date().timeIntervalSince(lastHealthCheckDate) >= healthCheckInterval {
            lastHealthCheckDate = Date()
            Task { [weak self] in
                await self?.performDaemonHealthCheck()
            }
        }
    }
    
    private func setupPowerNotification() {
        let callback: IOPowerSourceCallbackType = { context in
            guard let context = context else { return }
            let manager = Unmanaged<NativeBatteryManager>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in
                manager.updateBatteryStatus()
            }
        }
        
        if let source = IOPSNotificationCreateRunLoopSource(callback, Unmanaged.passUnretained(self).toOpaque())?.takeRetainedValue() {
            powerRunLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .defaultMode)
        }
    }
    
    func setMode(_ mode: ChargingMode) {
        self.chargingMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "NP_ChargingMode")
        
        guard isHelperInstalled else {
            installHelper { success in
                if success {
                    self.setMode(mode)
                }
            }
            return
        }
        
        switch mode {
        case .toLimit:
            forceFullCharge = false
            chargeLimitEnabled = true
            syncSettingsToDaemon()
            Task { [weak self] in
                guard let self else { return }
                guard await self.ensureDaemonConnection() else { return }
                do {
                    if self.level >= self.chargeLimit {
                        try await BTActions.disableCharging()
                        print("[Battery] Mode .toLimit: disabled charging (level \(self.level)% >= limit \(self.chargeLimit)%)")
                    } else {
                        try await BTActions.chargeToLimit()
                        print("[Battery] Mode .toLimit: charging to limit \(self.chargeLimit)%")
                    }
                } catch {
                    print("[Battery] Mode .toLimit action failed: \(error)")
                }
                self.updateBatteryStatus()
            }
        case .toFull:
            forceFullCharge = true
            chargeLimitEnabled = false
            Task { [weak self] in
                guard let self else { return }
                guard await self.ensureDaemonConnection() else { return }
                do {
                    try await BTActions.chargeToFull()
                    print("[Battery] Mode .toFull: charging to 100%")
                } catch {
                    print("[Battery] Mode .toFull action failed: \(error)")
                }
                self.updateBatteryStatus()
            }
        case .inhibit:
            forceFullCharge = false
            chargeLimitEnabled = false
            Task { [weak self] in
                guard let self else { return }
                guard await self.ensureDaemonConnection() else { return }
                do {
                    try await BTActions.disableCharging()
                    print("[Battery] Mode .inhibit: charging disabled")
                } catch {
                    print("[Battery] Mode .inhibit action failed: \(error)")
                }
                self.updateBatteryStatus()
            }
        }
    }
    
    func requestFullCharge() {
        setMode(.toFull)
    }
    
    func toggleChargeLimit() {
        chargeLimitEnabled.toggle()
        if chargeLimitEnabled {
            setMode(.toLimit)
        } else {
            setMode(.toFull)
        }
    }
    
    func setChargeLimit(percent: Int) {
        self.chargeLimit = max(50, min(100, percent))
        if isHelperInstalled {
            syncSettingsToDaemon()
            if chargingMode == .toLimit {
                Task {
                    if self.level >= self.chargeLimit {
                        try? await BTActions.disableCharging()
                    } else {
                        try? await BTActions.chargeToLimit()
                    }
                    self.updateBatteryStatus()
                }
            }
        }
    }
    
    // MARK: - Hardware Charging Control (BatteryToolkit Daemon)
    func checkHelperInstalled() {
        Task {
            do {
                _ = try await BTActions.getState()
                await MainActor.run {
                    self.isHelperInstalled = true
                    self.enforcementFailCount = 0
                }
            } catch {
                await MainActor.run {
                    self.isHelperInstalled = false
                }
            }
        }
    }
    
    /// Ensures daemon XPC connection is alive, auto-reconnects if needed
    private func ensureDaemonConnection() async -> Bool {
        guard !isReconnecting else { return false }
        
        do {
            _ = try await BTActions.getState()
            return true
        } catch {
            print("[Battery] Daemon connection lost, attempting reconnect...")
            isReconnecting = true
            defer { isReconnecting = false }
            
            // Try to re-install/re-register the daemon silently
            let status = await BTDaemonManagement.installHelperDirect()
            let reconnected = (status == .enabled)
            
            if reconnected {
                print("[Battery] Daemon reconnected successfully")
                isHelperInstalled = true
                enforcementFailCount = 0
            } else {
                print("[Battery] Daemon reconnection failed")
                isHelperInstalled = false
            }
            return reconnected
        }
    }
    
    /// Enforce disable charging with failure tracking and auto-restart
    private func enforceDisableCharging(reason: String) async {
        do {
            try await BTActions.disableCharging()
            enforcementFailCount = 0
            print("[Battery] Enforcement success: disabled charging (\(reason))")
        } catch {
            enforcementFailCount += 1
            print("[Battery] Enforcement FAILED (\(enforcementFailCount)/\(maxEnforcementFailsBeforeRestart)): \(error)")
            
            if enforcementFailCount >= maxEnforcementFailsBeforeRestart {
                print("[Battery] Too many enforcement failures, restarting daemon...")
                enforcementFailCount = 0
                let reconnected = await ensureDaemonConnection()
                if reconnected {
                    // Retry enforcement once after reconnect
                    do {
                        try await BTActions.disableCharging()
                        print("[Battery] Post-reconnect enforcement success")
                    } catch {
                        print("[Battery] Post-reconnect enforcement still failed: \(error)")
                    }
                }
            }
        }
    }
    
    /// Periodic daemon health check — runs every 30s from updateBatteryStatus
    private func performDaemonHealthCheck() async {
        do {
            _ = try await BTActions.getState()
            if !isHelperInstalled {
                await MainActor.run {
                    self.isHelperInstalled = true
                    print("[Battery] Health check: daemon recovered")
                }
            }
        } catch {
            print("[Battery] Health check: daemon unreachable — \(error)")
            await MainActor.run {
                self.isHelperInstalled = false
            }
            // Attempt silent re-install
            _ = await ensureDaemonConnection()
        }
    }
    
    func syncSettingsToDaemon() {
        let minVal = max(BTSettingsInfo.Bounds.minChargeMin, UInt8(max(20, chargeLimit - 5)))
        let maxVal = min(100, max(BTSettingsInfo.Bounds.maxChargeMin, UInt8(chargeLimit)))
        let settings: [String: NSObject & Sendable] = [
            BTSettingsInfo.Keys.maxCharge: NSNumber(value: maxVal),
            BTSettingsInfo.Keys.minCharge: NSNumber(value: minVal),
            BTSettingsInfo.Keys.magSafeSync: NSNumber(value: true)
        ]
        Task { [weak self] in
            guard let self else { return }
            do {
                try await BTActions.setSettings(settings: settings)
                print("[Battery] Settings synced: min=\(minVal) max=\(maxVal)")
            } catch {
                print("[Battery] Failed to sync settings: \(error)")
            }
            if self.chargingMode == .toLimit {
                if self.level >= self.chargeLimit {
                    await self.enforceDisableCharging(reason: "sync: level \(self.level)% >= limit \(self.chargeLimit)%")
                } else {
                    do {
                        try await BTActions.chargeToLimit()
                        print("[Battery] Sync: charging to limit")
                    } catch {
                        print("[Battery] Sync chargeToLimit failed: \(error)")
                    }
                }
            }
        }
    }
    
    // MARK: - 1-Click Daemon Installation / Activation
    func installHelper(completion: @escaping (Bool) -> Void) {
        isBusy = true
        helperStatusMessage = "Activating Battery Control Service..."
        
        Task {
            var status = await BTDaemonManagement.installHelperDirect()
            
            if status == .requiresApproval {
                await MainActor.run {
                    self.helperStatusMessage = "Please approve in System Settings..."
                }
                try? await BTActions.approveDaemon(timeout: 60)
                // Re-check status after approval window
                status = await BTDaemonManagement.installHelperDirect()
            }
            
            let success = (status == .enabled)
            await MainActor.run {
                self.isBusy = false
                self.isHelperInstalled = success
                self.enforcementFailCount = 0
                self.helperStatusMessage = success ? "Battery service active!" : "Could not activate battery service."
                if success {
                    self.syncSettingsToDaemon()
                }
                completion(success)
            }
        }
    }
}
