//
//  BluetoothHeadphoneManager.swift
//  NotchPulse
//
//  Created by Antigravity on 2026-09-28.
//

import AppKit
import CoreAudio
import Defaults
import Foundation
import IOBluetooth
import IOKit.ps

final class BluetoothHeadphoneManager: NSObject {
    static let shared = BluetoothHeadphoneManager()

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
        
        guard isAudio else { return }

        // Debounce if same device triggered within 3 seconds
        if address == lastConnectedDeviceAddress && Date().timeIntervalSince(lastTriggerTime) < 3.0 {
            return
        }

        lastConnectedDeviceAddress = address
        lastTriggerTime = Date()

        // Allow ~0.4s for macOS to finalize battery telemetry handshake
        Task {
            try? await Task.sleep(for: .milliseconds(400))
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
                        Task {
                            try? await Task.sleep(for: .milliseconds(300))
                            await self.checkAndDisplayBatteryHUD(forDeviceNamed: deviceName, address: "")
                        }
                    }
                }
            }
        }
    }

    @MainActor
    func checkAndDisplayBatteryHUD(forDeviceNamed targetName: String, address: String) async {
        guard Defaults[.hudReplacement] else { return }
        let (batteryPercent, icon) = await fetchBatteryInfo(forDeviceNamed: targetName, targetAddress: address)
        let batteryVal = batteryPercent ?? 100

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

    /// Fetches the battery percentage and matching icon for the connected Bluetooth device
    private func fetchBatteryInfo(forDeviceNamed name: String, targetAddress: String) async -> (Int?, String) {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                // Determine icon
                let lowerName = name.lowercased()
                let icon: String
                if lowerName.contains("pro") {
                    icon = "airpodspro"
                } else if lowerName.contains("max") {
                    icon = "airpodsmax"
                } else if lowerName.contains("airpods") {
                    icon = "airpods"
                } else {
                    icon = "headphones"
                }

                // 1. First check IOKit Power Sources
                if let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
                   let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] {
                    for source in sources {
                        if let desc = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
                           let psName = desc["Name"] as? String,
                           let currentCap = desc["Current Capacity"] as? Int {
                            if psName.lowercased().contains(lowerName) || lowerName.contains(psName.lowercased()) {
                                continuation.resume(returning: (currentCap, icon))
                                return
                            }
                        }
                    }
                }

                // 2. Query system_profiler SPBluetoothDataType
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
                process.arguments = ["SPBluetoothDataType", "-json"]
                let pipe = Pipe()
                process.standardOutput = pipe
                try? process.run()
                process.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let spList = json["SPBluetoothDataType"] as? [[String: Any]],
                      let first = spList.first,
                      let connected = first["device_connected"] as? [[String: [String: Any]]] else {
                    continuation.resume(returning: (nil, icon))
                    return
                }

                for deviceDict in connected {
                    for (devName, props) in deviceDict {
                        let matchesName = name.isEmpty || devName.lowercased().contains(lowerName) || lowerName.contains(devName.lowercased())
                        let matchesAddr = !targetAddress.isEmpty && ((props["device_address"] as? String)?.lowercased() == targetAddress.lowercased())

                        if matchesName || matchesAddr {
                            var batteryVal: Int?
                            if let mainStr = props["device_batteryLevelMain"] as? String,
                               let val = Int(mainStr.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)) {
                                batteryVal = val
                            } else if let leftStr = props["device_batteryLevelLeft"] as? String,
                                      let rightStr = props["device_batteryLevelRight"] as? String,
                                      let lVal = Int(leftStr.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)),
                                      let rVal = Int(rightStr.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)) {
                                batteryVal = min(lVal, rVal)
                            } else if let leftStr = props["device_batteryLevelLeft"] as? String,
                                      let lVal = Int(leftStr.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)) {
                                batteryVal = lVal
                            } else if let rightStr = props["device_batteryLevelRight"] as? String,
                                      let rVal = Int(rightStr.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)) {
                                batteryVal = rVal
                            }

                            if let battery = batteryVal {
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
