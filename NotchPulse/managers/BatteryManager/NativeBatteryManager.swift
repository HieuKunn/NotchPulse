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
            case .toLimit: return "To Limit"
            case .toFull: return "Charge to 100%"
            case .inhibit: return "AC Power"
            }
        }
        var icon: String {
            switch self {
            case .toLimit: return "battery.75"
            case .toFull: return "battery.100.bolt"
            case .inhibit: return "powerplug.fill"
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
        self.isDesktopMode = extConnected && (!charging || isInhibited) && currentCap >= (chargeLimit - 2)
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
            return
        }
        
        switch mode {
        case .toLimit:
            forceFullCharge = false
            chargeLimitEnabled = true
            syncSettingsToDaemon()
            Task {
                if self.level >= self.chargeLimit {
                    try? await BTActions.disableCharging()
                } else {
                    try? await BTActions.chargeToLimit()
                }
                self.updateBatteryStatus()
            }
        case .toFull:
            forceFullCharge = true
            chargeLimitEnabled = false
            Task {
                try? await BTActions.chargeToFull()
                self.updateBatteryStatus()
            }
        case .inhibit:
            forceFullCharge = false
            chargeLimitEnabled = false
            Task {
                try? await BTActions.disableCharging()
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
                }
            } catch {
                await MainActor.run {
                    self.isHelperInstalled = false
                }
            }
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
        Task {
            try? await BTActions.setSettings(settings: settings)
            if self.chargingMode == .toLimit {
                if self.level >= self.chargeLimit {
                    try? await BTActions.disableCharging()
                } else {
                    try? await BTActions.chargeToLimit()
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
                self.helperStatusMessage = success ? "Battery service active!" : "Could not activate battery service."
                if success {
                    self.syncSettingsToDaemon()
                }
                completion(success)
            }
        }
    }
}
