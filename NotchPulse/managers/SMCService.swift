//
//  SMCService.swift
//  NotchPulse
//
//  Created for NotchPulse - Direct Hardware SMC & Thermal/Fan Controller
//

import Darwin
import Foundation
import IOKit

public struct FanInfo: Identifiable, Equatable {
    public let id: Int
    public let name: String
    public var currentRPM: Int
    public var minRPM: Int
    public var maxRPM: Int
    public var targetRPM: Int
    public var isManual: Bool
}

public final class SMCService {
    public static let shared = SMCService()

    private var connection: io_connect_t = 0
    private let lock = NSLock()

    private let kSMCUserClientOpen: UInt32 = 0
    private let kSMCUserClientClose: UInt32 = 1
    private let kSMCHandleYPCEvent: UInt32 = 2
    private let kSMCReadKey: UInt8 = 5
    private let kSMCWriteKey: UInt8 = 6
    private let kSMCGetKeyInfo: UInt8 = 9

    private struct SMCVersion {
        var major: UInt8 = 0
        var minor: UInt8 = 0
        var build: UInt8 = 0
        var reserved: UInt8 = 0
        var release: UInt16 = 0
    }

    private struct SMCPLimitData {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }

    private struct SMCKeyInfoData {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    private struct SMCParamStruct {
        var key: UInt32 = 0
        var vers = SMCVersion()
        var pLimitData = SMCPLimitData()
        var keyInfo = SMCKeyInfoData()
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: (
            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
        ) = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
    }

    public var isHardwareFanAvailable: Bool = false
    public private(set) var fanCount: Int = 0

    private init() {
        _ = openConnection()
        let fans = getFans()
        self.fanCount = fans.count
        self.isHardwareFanAvailable = (fans.count > 0 && (fans.first?.maxRPM ?? 0) > 0)
    }

    deinit {
        restoreAutoFanControl()
        closeConnection()
    }

    // MARK: - Connection Management

    @discardableResult
    private func openConnection() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard connection == 0 else { return true }

        let matchingDict = IOServiceMatching("AppleSMC")
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matchingDict)
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }

        let result = IOServiceOpen(service, mach_task_self_, kSMCUserClientOpen, &connection)
        return result == kIOReturnSuccess
    }

    private func closeConnection() {
        lock.lock()
        defer { lock.unlock() }

        if connection != 0 {
            IOServiceClose(connection)
            connection = 0
        }
    }

    // MARK: - Low Level SMC Call

    private func callSMC(input: inout SMCParamStruct, output: inout SMCParamStruct) -> kern_return_t {
        if connection == 0 {
            _ = openConnection()
        }
        guard connection != 0 else { return kIOReturnNotOpen }

        let inputSize = MemoryLayout<SMCParamStruct>.stride
        var outputSize = MemoryLayout<SMCParamStruct>.stride

        return IOConnectCallStructMethod(
            connection,
            kSMCHandleYPCEvent,
            &input,
            inputSize,
            &output,
            &outputSize
        )
    }

    private func fourCCToUInt32(_ key: String) -> UInt32 {
        var ans: UInt32 = 0
        for char in key.utf8.prefix(4) {
            ans = (ans << 8) | UInt32(char)
        }
        return ans
    }

    private func readKeyInfo(_ key: String) -> (size: UInt32, type: UInt32)? {
        var input = SMCParamStruct()
        var output = SMCParamStruct()

        input.key = fourCCToUInt32(key)
        input.data8 = kSMCGetKeyInfo

        let status = callSMC(input: &input, output: &output)
        guard status == kIOReturnSuccess, output.result == 0 else {
            return nil
        }

        return (output.keyInfo.dataSize, output.keyInfo.dataType)
    }

    private func readSMCBytes(_ key: String) -> (bytes: [UInt8], type: UInt32)? {
        guard let info = readKeyInfo(key) else { return nil }

        var input = SMCParamStruct()
        var output = SMCParamStruct()

        input.key = fourCCToUInt32(key)
        input.keyInfo.dataSize = info.size
        input.data8 = kSMCReadKey

        let status = callSMC(input: &input, output: &output)
        guard status == kIOReturnSuccess, output.result == 0 else {
            return nil
        }

        var resultBytes = [UInt8]()
        withUnsafeBytes(of: output.bytes) { rawBuffer in
            let count = min(Int(info.size), rawBuffer.count)
            for i in 0..<count {
                resultBytes.append(rawBuffer[i])
            }
        }
        return (resultBytes, info.type)
    }

    private func writeSMCBytes(_ key: String, bytes: [UInt8]) -> Bool {
        guard let info = readKeyInfo(key) else { return false }

        var input = SMCParamStruct()
        var output = SMCParamStruct()

        input.key = fourCCToUInt32(key)
        input.keyInfo.dataSize = info.size
        input.keyInfo.dataType = info.type
        input.data8 = kSMCWriteKey

        withUnsafeMutableBytes(of: &input.bytes) { rawBuffer in
            for i in 0..<min(bytes.count, rawBuffer.count) {
                rawBuffer[i] = bytes[i]
            }
        }

        let status = callSMC(input: &input, output: &output)
        return status == kIOReturnSuccess && output.result == 0
    }

    // MARK: - Hardware Temperature Reading (Intel & Apple Silicon M1/M2/M3/M4)

    public func getHardwareTemperature() -> Double? {
        // 1. Apple Silicon & Intel common temperature keys
        let tempKeys = [
            // Apple Silicon SoC / PMU / Core keys
            "Tp09", "Tp0T", "Tp1h", "Tp05", "Tg05", "Tg0D", "Te05", "Tf05", "Tf0D",
            // Intel CPU die/proximity keys
            "TC0D", "TC0P", "TC0E", "TC0F", "TC1C", "TC2C", "TC3C", "TC4C", "TCAH", "TCBH"
        ]

        var validTemps: [Double] = []

        for key in tempKeys {
            if let (bytes, type) = readSMCBytes(key), !bytes.isEmpty {
                if type == fourCCToUInt32("flt ") && bytes.count >= 4 {
                    var f: Float32 = 0
                    memcpy(&f, bytes, 4)
                    let val = Double(f)
                    if val > 20.0 && val < 115.0 {
                        validTemps.append(val)
                    }
                } else if (type == fourCCToUInt32("sp78") || type == fourCCToUInt32("sp87")) && bytes.count >= 2 {
                    let val = Double(Int8(bitPattern: bytes[0])) + (Double(bytes[1]) / 256.0)
                    if val > 20.0 && val < 115.0 {
                        validTemps.append(val)
                    }
                }
            }
        }

        if !validTemps.isEmpty {
            // Return the highest core/SoC thermal reading
            return validTemps.max()
        }

        // 2. IOHIDEventSystemClient Fallback (Reads hardware thermal sensors directly on macOS without root)
        if let hidTemp = readHIDTemperature() {
            return hidTemp
        }

        return nil
    }

    private func readHIDTemperature() -> Double? {
        typealias IOHIDEventSystemClientCreateType = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
        typealias IOHIDEventSystemClientSetMatchingType = @convention(c) (AnyObject, CFDictionary) -> Void
        typealias IOHIDEventSystemClientCopyServicesType = @convention(c) (AnyObject) -> Unmanaged<CFArray>?
        typealias IOHIDServiceClientCopyEventType = @convention(c) (AnyObject, Int64, Int32, Int64) -> Unmanaged<AnyObject>?
        typealias IOHIDEventGetFloatValueType = @convention(c) (AnyObject, UInt32) -> Double

        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW) else { return nil }
        defer { dlclose(handle) }

        guard let clientCreateSym = dlsym(handle, "IOHIDEventSystemClientCreate"),
              let setMatchingSym = dlsym(handle, "IOHIDEventSystemClientSetMatching"),
              let copyServicesSym = dlsym(handle, "IOHIDEventSystemClientCopyServices"),
              let copyEventSym = dlsym(handle, "IOHIDServiceClientCopyEvent"),
              let getFloatSym = dlsym(handle, "IOHIDEventGetFloatValue") else {
            return nil
        }

        let clientCreate = unsafeBitCast(clientCreateSym, to: IOHIDEventSystemClientCreateType.self)
        let setMatching = unsafeBitCast(setMatchingSym, to: IOHIDEventSystemClientSetMatchingType.self)
        let copyServices = unsafeBitCast(copyServicesSym, to: IOHIDEventSystemClientCopyServicesType.self)
        let copyEvent = unsafeBitCast(copyEventSym, to: IOHIDServiceClientCopyEventType.self)
        let getFloat = unsafeBitCast(getFloatSym, to: IOHIDEventGetFloatValueType.self)

        guard let clientObj = clientCreate(kCFAllocatorDefault)?.takeRetainedValue() else { return nil }

        let matching: [String: Any] = [
            "PrimaryUsagePage": 0xFF00,
            "PrimaryUsage": 0x05
        ]
        setMatching(clientObj, matching as CFDictionary)

        guard let servicesArray = copyServices(clientObj)?.takeRetainedValue() as? [AnyObject] else { return nil }

        var temps: [Double] = []
        for service in servicesArray {
            if let eventObj = copyEvent(service, 0x0F, 0, 0)?.takeRetainedValue() {
                let temp = getFloat(eventObj, 0x0F << 16)
                if temp > 20.0 && temp < 115.0 {
                    temps.append(temp)
                }
            }
        }

        return temps.isEmpty ? nil : temps.max()
    }

    // MARK: - Fan Reading & Direct Control

    public func getFans() -> [FanInfo] {
        var count = 0
        if let (bytes, _) = readSMCBytes("FNum"), let first = bytes.first {
            count = Int(first)
        }

        if count == 0 {
            // Check if fan 0 exists
            if readKeyInfo("F0Ac") != nil {
                count = 1
                if readKeyInfo("F1Ac") != nil {
                    count = 2
                }
            }
        }

        var fans: [FanInfo] = []
        for i in 0..<count {
            let actual = readFanRPM("F\(i)Ac") ?? 0
            let minRPM = readFanRPM("F\(i)Mn") ?? 1200
            let maxRPM = readFanRPM("F\(i)Mx") ?? 5800
            let target = readFanRPM("F\(i)Tg") ?? minRPM
            let isManual = readFanManualMode(index: i)

            let name = count == 1 ? "Fan" : (i == 0 ? "Left Fan" : "Right Fan")
            fans.append(FanInfo(
                id: i,
                name: name,
                currentRPM: actual,
                minRPM: minRPM,
                maxRPM: maxRPM,
                targetRPM: target,
                isManual: isManual
            ))
        }

        return fans
    }

    private func readFanRPM(_ key: String) -> Int? {
        guard let (bytes, type) = readSMCBytes(key), !bytes.isEmpty else { return nil }

        if type == fourCCToUInt32("fpe2") && bytes.count >= 2 {
            let raw = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
            return Int(Double(raw) / 4.0)
        } else if type == fourCCToUInt32("flt ") && bytes.count >= 4 {
            var f: Float32 = 0
            memcpy(&f, bytes, 4)
            return Int(f)
        }
        return nil
    }

    private func readFanManualMode(index: Int) -> Bool {
        if let (bytes, _) = readSMCBytes("F\(index)Md"), let first = bytes.first {
            return first != 0
        }
        if let (bytes, _) = readSMCBytes("FS! "), bytes.count >= 2 {
            let mask = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
            return (mask & (1 << index)) != 0
        }
        return false
    }

    @discardableResult
    public func setFanSpeed(targetRPM: Int, fanIndex: Int = 0) -> Bool {
        let fans = getFans()
        guard fanIndex < fans.count else { return false }
        let fan = fans[fanIndex]
        let clampedRPM = max(fan.minRPM, min(fan.maxRPM, targetRPM))

        var success = false

        // 1. Enable Manual Mode on fan
        var modeBytes: [UInt8] = [1]
        _ = writeSMCBytes("F\(fanIndex)Md", bytes: modeBytes)

        // Force bitmask FS!
        var forceMask: UInt16 = 1 << fanIndex
        var forceBytes: [UInt8] = [UInt8((forceMask >> 8) & 0xFF), UInt8(forceMask & 0xFF)]
        _ = writeSMCBytes("FS! ", bytes: forceBytes)

        // 2. Write Target RPM
        if let info = readKeyInfo("F\(fanIndex)Tg") {
            if info.type == fourCCToUInt32("fpe2") {
                let raw = UInt16(clampedRPM * 4)
                let bytes: [UInt8] = [UInt8((raw >> 8) & 0xFF), UInt8(raw & 0xFF)]
                success = writeSMCBytes("F\(fanIndex)Tg", bytes: bytes)
            } else if info.type == fourCCToUInt32("flt ") {
                var f = Float32(clampedRPM)
                var bytes = [UInt8](repeating: 0, count: 4)
                memcpy(&bytes, &f, 4)
                success = writeSMCBytes("F\(fanIndex)Tg", bytes: bytes)
            }
        }

        // 3. If direct IOKit write is restricted without root, invoke privileged helper or smc tool
        if !success {
            success = executePrivilegedFanCommand(fanIndex: fanIndex, targetRPM: clampedRPM, isManual: true)
        }

        return success
    }

    @discardableResult
    public func restoreAutoFanControl() -> Bool {
        let fans = getFans()
        var allRestored = true

        for i in 0..<fans.count {
            // Write Mode 0 (Auto)
            _ = writeSMCBytes("F\(i)Md", bytes: [0])
            // Clear Force bitmask
            _ = writeSMCBytes("FS! ", bytes: [0, 0])
        }

        // Also ensure fallback command is dispatched
        _ = executePrivilegedFanCommand(fanIndex: 0, targetRPM: 0, isManual: false)
        return allRestored
    }

    private func executePrivilegedFanCommand(fanIndex: Int, targetRPM: Int, isManual: Bool) -> Bool {
        // Execute SMC override via background helper task if available
        let script: String
        if isManual {
            script = "do shell script \"/usr/bin/smc -k F\(fanIndex)Md -w 01 && /usr/bin/smc -k F\(fanIndex)Tg -w $(printf '%04x' $(( \(targetRPM) * 4 )))\" with administrator privileges"
        } else {
            script = "do shell script \"/usr/bin/smc -k F\(fanIndex)Md -w 00 && /usr/bin/smc -k 'FS! ' -w 0000\" with administrator privileges"
        }

        // We run background non-blocking dispatch
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            if let appleScript = NSAppleScript(source: script) {
                appleScript.executeAndReturnError(&error)
            }
        }
        return true
    }
}
