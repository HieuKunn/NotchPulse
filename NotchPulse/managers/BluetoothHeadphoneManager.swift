import AppKit
import CoreAudio
import Defaults
import Foundation
import IOBluetooth
import IOKit.ps

final class BluetoothHeadphoneManager: NSObject {
    static let shared = BluetoothHeadphoneManager()

    private typealias BatteryGetter = @convention(c) (AnyObject, Selector) -> UInt8

    private static var cachedProfilerData: [[String: [String: Any]]]? = nil
    private static var lastProfilerQuery: Date = .distantPast

    private var connectNotification: IOBluetoothUserNotification?
    private var lastTriggerTime: Date = .distantPast
    private var lastConnectedDeviceAddress: String = ""
    private var isAudioListenerSetup = false

    override init() {
        super.init()
        DispatchQueue.main.async { [weak self] in
            self?.setupListeners()
        }
    }

    func setupListeners() {
        // 1. Listen for IOBluetooth device connection events (safely guarded)
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(deviceConnectedNotification(_:device:))
        )

        // 2. Listen for CoreAudio default output device changes
        setupCoreAudioOutputListener()
    }

    @objc private func deviceConnectedNotification(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        let name = device.nameOrAddress ?? "Headphones"
        let address = device.addressString ?? ""

        // Reset stale profiler cache on fresh device connection
        Self.cachedProfilerData = nil
        
        // Only trigger if device is audio / headphones
        let minor = device.deviceClassMinor
        let major = device.deviceClassMajor
        // Audio major class is 4 (Audio/Video), minor 1 (Wearable Headset), 2 (Handsfree), 6 (Headphones)
        let lower = name.lowercased()
        let isAudio = major == 4 || minor == 1 || minor == 2 || minor == 6
            || lower.contains("airpod") || lower.contains("bud") || lower.contains("headphone")
            || lower.contains("headset") || lower.contains("beat") || lower.contains("bose")
            || lower.contains("sony") || lower.contains("jbl") || lower.contains("sennheiser")
            || lower.contains("marshall") || lower.contains("audio") || lower.contains("speaker")
            || lower.contains("airplus")
        
        guard isAudio else { return }

        // Debounce if same device triggered within 3 seconds
        if address == lastConnectedDeviceAddress && Date().timeIntervalSince(lastTriggerTime) < 3.0 {
            return
        }

        lastConnectedDeviceAddress = address
        lastTriggerTime = Date()

        Task {
            await self.checkAndDisplayBatteryHUD(forDeviceNamed: name, address: address)
        }
    }

    private func setupCoreAudioOutputListener() {
        guard !isAudioListenerSetup else { return }
        isAudioListenerSetup = true

        var defaultOutputDevicePropertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultOutputDevicePropertyAddress,
            DispatchQueue.main
        ) { [weak self] _, _ in
            self?.handleDefaultOutputDeviceChanged()
        }
    }

    private func handleDefaultOutputDeviceChanged() {
        // Query active output device
        var defaultDeviceID = AudioObjectID(0)
        var propertySize = UInt32(MemoryLayout<AudioObjectID>.size)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &defaultDeviceID
        ) == noErr, defaultDeviceID != 0 else { return }

        // Check if transport type is Bluetooth
        var transportType: UInt32 = 0
        var transportSize = UInt32(MemoryLayout<UInt32>.size)
        var transportAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        if AudioObjectGetPropertyData(
            defaultDeviceID,
            &transportAddress,
            0,
            nil,
            &transportSize,
            &transportType
        ) == noErr {
            // kAudioDeviceTransportTypeBluetooth = 0x626c7565 ('blue'), kAudioDeviceTransportTypeBluetoothLE = 0x626c6520 ('ble ')
            if transportType == 0x626c7565 || transportType == 0x626c6520 {
                // Get device name
                var nameCF: CFString = "" as CFString
                var nameSize = UInt32(MemoryLayout<CFString>.size)
                var nameAddress = AudioObjectPropertyAddress(
                    mSelector: kAudioObjectPropertyName,
                    mScope: kAudioObjectPropertyScopeGlobal,
                    mElement: kAudioObjectPropertyElementMain
                )
                if AudioObjectGetPropertyData(
                    defaultDeviceID,
                    &nameAddress,
                    0,
                    nil,
                    &nameSize,
                    &nameCF
                ) == noErr {
                    let deviceName = nameCF as String
                    if Date().timeIntervalSince(self.lastTriggerTime) >= 3.0 {
                        self.lastTriggerTime = Date()
                        Self.cachedProfilerData = nil
                        Task {
                            await self.checkAndDisplayBatteryHUD(forDeviceNamed: deviceName, address: "")
                        }
                    }
                }
            }
        }
    }

    @MainActor
    func checkAndDisplayBatteryHUD(forDeviceNamed targetName: String, address: String) async {
        guard Defaults[.hudReplacement] || Defaults[.inlineHUD] else { return }

        // Retry up to 4 times over ~1.2s to accommodate Bluetooth driver telemetry sync
        var batteryPercent: Int? = nil
        var icon: String = "headphones"

        for delay in [150, 250, 350, 450] {
            let (bat, ic) = fetchLiveBattery(forDeviceNamed: targetName, targetAddress: address)
            icon = ic
            if let b = bat {
                batteryPercent = b
                break
            }
            try? await Task.sleep(for: .milliseconds(delay))
        }

        // Secondary fallback to system_profiler if IOBluetooth selector is not populated yet
        if batteryPercent == nil {
            let (bat, ic) = await fetchSystemProfilerBattery(forDeviceNamed: targetName, targetAddress: address)
            if let b = bat {
                batteryPercent = b
                icon = ic
            }
        }

        // CRITICAL FIX: If battery telemetry is unavailable, NEVER display fake 100%!
        guard let batteryVal = batteryPercent else { return }

        let normalizedValue = max(0.01, min(1.0, CGFloat(batteryVal) / 100.0))
        NotchPulseViewCoordinator.shared.toggleSneakPeek(
            status: true,
            type: .battery,
            duration: 3.0,
            value: normalizedValue,
            icon: icon
        )

        if Defaults[.enableHaptics] {
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        }
    }

    /// Public synchronous battery percentage query for UI display (e.g., Audio Hub list)
    func getBatteryPercentage(forDeviceNamed targetName: String, targetAddress: String = "") -> Int? {
        let (bat, _) = fetchLiveBattery(forDeviceNamed: targetName, targetAddress: targetAddress)
        return bat
    }

    /// Fast synchronous live battery fetching via IOBluetooth in-memory selectors and IOKit
    func fetchLiveBattery(forDeviceNamed name: String, targetAddress: String = "") -> (battery: Int?, icon: String) {
        let lowerName = name.lowercased()
        let icon: String
        if lowerName.contains("pro") {
            icon = "airpodspro"
        } else if lowerName.contains("max") {
            icon = "airpodsmax"
        } else if lowerName.contains("airpod") || lowerName.contains("airplus") {
            icon = "airpods"
        } else {
            icon = "headphones"
        }

        // 1. Direct IOBluetoothDevice selectors (0ms latency, true hardware reading)
        var matchedDevice: IOBluetoothDevice? = nil
        if !targetAddress.isEmpty, let dev = IOBluetoothDevice(addressString: targetAddress) {
            matchedDevice = dev
        }
        if matchedDevice == nil, let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] {
            matchedDevice = paired.first { dev in
                let devName = (dev.nameOrAddress ?? "").lowercased()
                let devAddr = (dev.addressString ?? "").lowercased()
                if !targetAddress.isEmpty && devAddr == targetAddress.lowercased() {
                    return true
                }
                return !lowerName.isEmpty && (devName.contains(lowerName) || lowerName.contains(devName))
            }
        }

        if let device = matchedDevice {
            func readSelector(_ selName: String) -> Int? {
                let sel = Selector(selName)
                guard let method = class_getInstanceMethod(object_getClass(device), sel) else { return nil }
                let imp = method_getImplementation(method)
                let getter = unsafeBitCast(imp, to: BatteryGetter.self)
                let val = getter(device, sel)
                return (val > 0 && val <= 100) ? Int(val) : nil
            }

            let left = readSelector("batteryPercentLeft")
            let right = readSelector("batteryPercentRight")
            let single = readSelector("batteryPercentSingle")
            let combined = readSelector("batteryPercentCombined")
            let caseBat = readSelector("batteryPercentCase")

            // Dual earbuds logic:
            // If both earbuds are active, use min(left, right) so user is warned of lower pod
            if let l = left, let r = right {
                return (min(l, r), icon)
            }
            // If only one earbud is active in ear, return its exact percentage (never 0%!)
            if let l = left {
                return (l, icon)
            }
            if let r = right {
                return (r, icon)
            }
            // Single battery devices (AirPods Max, Beats Solo, Sony WH, etc.)
            if let s = single {
                return (s, icon)
            }
            if let c = combined {
                return (c, icon)
            }
            // If earbuds are idle in case, case battery can serve as fallback
            if let cb = caseBat {
                return (cb, icon)
            }
        }

        // 2. IOKit Power Sources
        if let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] {
            for source in sources {
                if let desc = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
                   let psName = desc["Name"] as? String,
                   let currentCap = desc["Current Capacity"] as? Int {
                    let lowerPS = psName.lowercased()
                    if (lowerPS.contains(lowerName) || lowerName.contains(lowerPS)) && currentCap > 0 && currentCap <= 100 {
                        return (currentCap, icon)
                    }
                }
            }
        }

        return (nil, icon)
    }

    /// Asynchronous system_profiler fallback parser
    private func fetchSystemProfilerBattery(forDeviceNamed name: String, targetAddress: String) async -> (Int?, String) {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let lowerName = name.lowercased()
                let icon: String
                if lowerName.contains("pro") {
                    icon = "airpodspro"
                } else if lowerName.contains("max") {
                    icon = "airpodsmax"
                } else if lowerName.contains("airpod") || lowerName.contains("airplus") {
                    icon = "airpods"
                } else {
                    icon = "headphones"
                }

                let now = Date()
                var connectedDevices: [[String: [String: Any]]]? = nil

                if let cached = Self.cachedProfilerData, now.timeIntervalSince(Self.lastProfilerQuery) < 30.0 {
                    connectedDevices = cached
                } else {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
                    process.arguments = ["SPBluetoothDataType", "-json"]
                    let pipe = Pipe()
                    process.standardOutput = pipe
                    try? process.run()
                    process.waitUntilExit()

                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let spList = json["SPBluetoothDataType"] as? [[String: Any]],
                       let first = spList.first,
                       let connected = first["device_connected"] as? [[String: [String: Any]]] {
                        connectedDevices = connected
                        Self.cachedProfilerData = connected
                        Self.lastProfilerQuery = now
                    }
                }

                guard let connected = connectedDevices else {
                    continuation.resume(returning: (nil, icon))
                    return
                }

                for deviceDict in connected {
                    for (devName, props) in deviceDict {
                        let matchesName = name.isEmpty || devName.lowercased().contains(lowerName) || lowerName.contains(devName.lowercased())
                        let matchesAddr = !targetAddress.isEmpty && ((props["device_address"] as? String)?.lowercased() == targetAddress.lowercased())

                        if matchesName || matchesAddr {
                            var batteryVal: Int?
                            let leftVal = (props["device_batteryLevelLeft"] as? String).flatMap { Int($0.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)) }
                            let rightVal = (props["device_batteryLevelRight"] as? String).flatMap { Int($0.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)) }
                            let mainVal = (props["device_batteryLevelMain"] as? String).flatMap { Int($0.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)) }

                            if let l = leftVal, let r = rightVal, l > 0, r > 0 {
                                batteryVal = min(l, r)
                            } else if let l = leftVal, l > 0 {
                                batteryVal = l
                            } else if let r = rightVal, r > 0 {
                                batteryVal = r
                            } else if let m = mainVal, m > 0 {
                                batteryVal = m
                            }

                            if let battery = batteryVal, battery > 0 && battery <= 100 {
                                continuation.resume(returning: (battery, icon))
                                return
                            }
                        }
                    }
                }

                continuation.resume(returning: (nil, icon))
            }
        }
    }
}
