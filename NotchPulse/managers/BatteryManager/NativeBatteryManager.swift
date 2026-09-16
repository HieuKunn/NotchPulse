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
            case .toLimit: return "Tới giới hạn"
            case .toFull: return "Sạc đầy 100%"
            case .inhibit: return "Dùng nguồn AC"
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
            checkAndEnforceLimit()
        }
    }
    
    @Published var chargeLimit: Int {
        didSet {
            UserDefaults.standard.set(chargeLimit, forKey: "NP_ChargeLimit")
            checkAndEnforceLimit()
        }
    }
    
    @Published var isHelperInstalled: Bool = false
    @Published var isBusy: Bool = false
    @Published var helperStatusMessage: String = ""
    
    private var forceFullCharge: Bool = false
    private var cancellables = Set<AnyCancellable>()
    private var powerRunLoopSource: CFRunLoopSource?
    
    private let helperPath = "/usr/local/bin/notchpulse-battery"
    
    private var isMonitoring: Bool = false
    private var monitoringTimer: AnyCancellable?
    
    private init() {
        let savedMode = UserDefaults.standard.string(forKey: "NP_ChargingMode") ?? ChargingMode.toLimit.rawValue
        self.chargingMode = ChargingMode(rawValue: savedMode) ?? .toLimit
        self.chargeLimitEnabled = UserDefaults.standard.object(forKey: "NP_ChargeLimitEnabled") as? Bool ?? true
        self.chargeLimit = UserDefaults.standard.object(forKey: "NP_ChargeLimit") as? Int ?? 80
        
        checkHelperInstalled()
        updateBatteryStatus()
        setupPowerNotification()
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
        
        monitoringTimer = Timer.publish(every: 3.0, on: .main, in: .common)
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
        
        checkAndEnforceLimit()
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
    
    // MARK: - Charge Limit Automation
    private func checkAndEnforceLimit() {
        guard isPluggedIn else {
            forceFullCharge = false
            return
        }
        
        if forceFullCharge {
            if level >= 100 {
                forceFullCharge = false
            } else {
                return
            }
        }
        
        guard chargeLimitEnabled else { return }
        
        if level >= chargeLimit && isCharging {
            // Reached limit: pause charging
            inhibitCharging()
        } else if level <= (chargeLimit - 3) && !isCharging && isPluggedIn {
            // Dropped below limit: resume charging
            allowCharging()
        }
    }
    
    func setMode(_ mode: ChargingMode) {
        self.chargingMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "NP_ChargingMode")
        switch mode {
        case .toLimit:
            forceFullCharge = false
            chargeLimitEnabled = true
            allowCharging()
            checkAndEnforceLimit()
        case .toFull:
            requestFullCharge()
        case .inhibit:
            forceFullCharge = false
            chargeLimitEnabled = false
            inhibitCharging()
        }
    }
    
    func requestFullCharge() {
        self.chargingMode = .toFull
        forceFullCharge = true
        allowCharging()
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
    }
    
    // MARK: - Hardware Charging Control
    func checkHelperInstalled() {
        isHelperInstalled = FileManager.default.fileExists(atPath: helperPath)
    }
    
    func inhibitCharging() {
        guard isHelperInstalled else { return }
        runHelper(command: "inhibit")
    }
    
    func allowCharging() {
        guard isHelperInstalled else { return }
        runHelper(command: "allow")
    }
    
    private func runHelper(command: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process()
            task.launchPath = self.helperPath
            task.arguments = [command]
            task.standardOutput = Pipe()
            task.standardError = Pipe()
            try? task.run()
            task.waitUntilExit()
            
            Task { @MainActor in
                self.updateBatteryStatus()
            }
        }
    }
    
    // MARK: - 1-Click Helper Installation
    func installHelper(completion: @escaping (Bool) -> Void) {
        isBusy = true
        helperStatusMessage = "Đang cài đặt quyền điều khiển pin..."
        
        DispatchQueue.global(qos: .userInitiated).async {
            // Script to create the lightweight SMC battery helper at /usr/local/bin/notchpulse-battery
            let helperSource = """
            cat << 'EOF' > /tmp/notchpulse-battery.swift
            import Foundation
            import IOKit

            let smc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
            guard smc != IO_OBJECT_NULL else { exit(1) }
            var connect: io_connect_t = IO_OBJECT_NULL
            guard IOServiceOpen(smc, mach_task_self_, 1, &connect) == kIOReturnSuccess else { exit(1) }
            IOConnectCallMethod(connect, 0, nil, 0, nil, 0, nil, nil, nil, nil)

            struct P {
                var k: UInt32 = 0; var v: (UInt8,UInt8,UInt8,UInt8,UInt16) = (0,0,0,0,0); var p1: UInt16 = 0
                var l: (UInt16,UInt16,UInt32,UInt32,UInt32) = (0,0,0,0,0); var i: (UInt32,UInt32,UInt8) = (0,0,0)
                var p2: (UInt8,UInt16) = (0,0); var r: UInt8 = 0; var s: UInt8 = 0; var d8: UInt8 = 0; var p3: UInt8 = 0
                var d32: UInt32 = 0; var b = (UInt8(0),UInt8(0),UInt8(0),UInt8(0),UInt8(0),UInt8(0),UInt8(0),UInt8(0),UInt8(0),UInt8(0),UInt8(0),UInt8(0),UInt8(0),UInt8(0),UInt8(0),UInt8(0),UInt8(0),UInt8(0),UInt8(0),UInt8(0),UInt8(0),UInt8(0),UInt8(0),UInt8(0),UInt8(0),UInt8(0),UInt8(0),UInt8(0),UInt8(0),UInt8(0),UInt8(0),UInt8(0))
            }

            func writeKey(_ key: String, _ byte: UInt8) {
                var val: UInt32 = 0
                for c in key.utf8 { val = (val << 8) | UInt32(c) }
                var inp = P()
                inp.k = val; inp.i.0 = 1; inp.d8 = 6; inp.b.0 = byte
                var out = P(); var sz = MemoryLayout<P>.stride
                _ = IOConnectCallStructMethod(connect, 2, &inp, sz, &out, &sz)
            }

            let cmd = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ""
            if cmd == "inhibit" {
                writeKey("CHIE", 0x08)
                writeKey("CH0J", 0x20)
            } else if cmd == "allow" {
                writeKey("CHIE", 0x00)
                writeKey("CH0J", 0x00)
            }
            IOConnectCallMethod(connect, 1, nil, 0, nil, 0, nil, nil, nil, nil)
            IOServiceClose(connect)
            EOF
            mkdir -p /usr/local/bin
            swiftc /tmp/notchpulse-battery.swift -O -o /usr/local/bin/notchpulse-battery
            chown root:wheel /usr/local/bin/notchpulse-battery
            chmod u+s /usr/local/bin/notchpulse-battery
            rm -f /tmp/notchpulse-battery.swift
            """
            
            let appleScript = "do shell script \"\(helperSource.replacingOccurrences(of: "\"", with: "\\\""))\" with administrator privileges"
            var error: NSDictionary?
            if let scriptObject = NSAppleScript(source: appleScript) {
                scriptObject.executeAndReturnError(&error)
            }
            
            let success = (error == nil) && FileManager.default.fileExists(atPath: self.helperPath)
            
            Task { @MainActor in
                self.isBusy = false
                self.isHelperInstalled = success
                self.helperStatusMessage = success ? "Cài đặt thành công!" : "Không thể cài đặt quyền quản trị."
                completion(success)
            }
        }
    }
}
