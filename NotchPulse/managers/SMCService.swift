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

    private struct SMCKeyData_vers_t {
        var major: UInt8 = 0
        var minor: UInt8 = 0
        var build: UInt8 = 0
        var reserved: UInt8 = 0
        var release: UInt16 = 0
    }

    private struct SMCKeyData_pLimitData_t {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }

    private struct SMCKeyData_keyInfo_t {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    private struct SMCParamStruct {
        var key: UInt32 = 0
        var vers = SMCKeyData_vers_t()
        var _pad0: UInt16 = 0
        var pLimitData = SMCKeyData_pLimitData_t()
        var keyInfo = SMCKeyData_keyInfo_t()
        var _pad1: (UInt8, UInt8, UInt8) = (0, 0, 0)
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var _pad2: UInt8 = 0
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

    // ThermalForge hardware adaptation
    private var modeKeyTemplate: String = "F%dMd"
    private var hasFtst: Bool = false
    private var isUnlocked: Bool = false

    // MARK: - Universal Hardware Sensor Matrix (All Mac Generations)
    public static let universalThermalKeys: [String] = [
        // CPU — aggregate (Apple Silicon M1-M5 Max)
        "TCDX", "TCHP", "TCMb",
        // CPU — per-core cluster (Tp prefix across M1-M5)
        "Tp01", "Tp02", "Tp03", "Tp04", "Tp05", "Tp06", "Tp07", "Tp08",
        "Tp09", "Tp0A", "Tp0B", "Tp0C", "Tp0D", "Tp0F", "Tp0G", "Tp0H",
        "Tp0J", "Tp0L", "Tp0P", "Tp0S", "Tp0T", "Tp0W", "Tp0X", "Tp0b", "Tp1h",
        // GPU clusters (flt on M1-M4, ioft 8-byte on M3/M4/M5 Max)
        "Tg05", "Tg0D", "Tg0L", "Tg0T", "Tg0f", "Tg0j",
        "TG0B", "TG0H", "TG0V",
        // Intel legacy CPU die / proximity sensors
        "TC0D", "TC0P", "TC0E", "TC0F", "TC1C", "TC2C", "TC3C", "TC4C", "TCAH", "TCBH",
        // Unified Memory / RAM
        "Tm02", "Tm06", "Tm08", "Tm09", "TRDX", "TMVR",
        // Power Delivery & PMU
        "TPDX",
        // SSD NAND Flash Storage
        "TH0x", "TH0A", "TH0B",
        // Ambient & System Proximity
        "TAOL", "TA0P", "TS0P",
        // Battery
        "TB0T"
    ]

    private init() {
        _ = openConnection()
        let fans = getFans()
        self.fanCount = fans.count
        self.isHardwareFanAvailable = (fans.count > 0 && (fans.first?.maxRPM ?? 0) > 0)

        // ThermalForge hardware detection:
        // M5 Max uses F%dmd (lowercase), M1-M4 use F%dMd (uppercase)
        if readKeyInfo("F0md") != nil {
            self.modeKeyTemplate = "F%dmd"
        } else {
            self.modeKeyTemplate = "F%dMd"
        }

        // Check if Ftst exists (M1-M4 unlock mechanism)
        if let info = readKeyInfo("Ftst"), info.size > 0 {
            self.hasFtst = true
        } else {
            self.hasFtst = false
        }
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
        input.keyInfo.dataType = info.type
        input.data8 = kSMCReadKey

        let status = callSMC(input: &input, output: &output)
        guard status == kIOReturnSuccess, output.result == 0 else {
            return nil
        }

        var resultBytes = [UInt8]()
        withUnsafePointer(to: &output.bytes) { ptr in
            let rawPtr = UnsafeRawPointer(ptr).assumingMemoryBound(to: UInt8.self)
            for i in 0..<Int(info.size) {
                resultBytes.append(rawPtr[i])
            }
        }
        return (resultBytes, info.type)
    }

    private func writeSMCBytes(_ key: String, bytes: [UInt8], type: UInt32? = nil) -> Bool {
        guard let info = readKeyInfo(key) else { return false }

        var input = SMCParamStruct()
        var output = SMCParamStruct()

        input.key = fourCCToUInt32(key)
        input.keyInfo.dataSize = info.size
        input.keyInfo.dataType = type ?? info.type
        input.data8 = kSMCWriteKey

        withUnsafeMutablePointer(to: &input.bytes) { ptr in
            let rawPtr = UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: UInt8.self)
            for i in 0..<min(bytes.count, Int(info.size)) {
                rawPtr[i] = bytes[i]
            }
        }

        let status = callSMC(input: &input, output: &output)
        return status == kIOReturnSuccess && output.result == 0
    }

    // MARK: - Multi-Format Byte Decoding (Apple Silicon & Intel)

    /// Decodes 16.16 fixed-point 8-byte `ioft` format (Apple Silicon M3/M4/M5 Max GPU & SoC sensors).
    private func ioftBytesToDouble(_ bytes: [UInt8]) -> Double {
        guard bytes.count >= 4 else { return 0.0 }
        var raw: UInt32 = 0
        memcpy(&raw, bytes, 4)
        let integer = Double(raw >> 16)
        let fraction = Double(raw & 0xFFFF) / 65536.0
        return integer + fraction
    }

    // MARK: - Hardware Temperature Reading (Intel & Apple Silicon M1-M5 Max)

    public func getHardwareTemperature() -> Double? {
        // 1. Apple Silicon & Intel Universal Multi-Sensor Sweep
        let typeFlt = fourCCToUInt32("flt ")
        let typeIoft = fourCCToUInt32("ioft")
        let typeSp78 = fourCCToUInt32("sp78")
        let typeSp87 = fourCCToUInt32("sp87")

        var cpuGpuTemps: [Double] = []
        var otherTemps: [Double] = []

        for key in Self.universalThermalKeys {
            guard let (bytes, type) = readSMCBytes(key), !bytes.isEmpty else { continue }
            var val: Double? = nil

            if type == typeFlt && bytes.count >= 4 {
                // IEEE 754 32-bit Float
                var f: Float32 = 0
                memcpy(&f, bytes, 4)
                val = Double(f)
            } else if (type == typeIoft || bytes.count >= 8) && bytes.count >= 4 {
                // Apple Silicon 16.16 fixed-point (M3/M4/M5 Max)
                val = ioftBytesToDouble(bytes)
            } else if (type == typeSp78 || type == typeSp87) && bytes.count >= 2 {
                // Intel fixed-point format
                val = Double(Int8(bitPattern: bytes[0])) + (Double(bytes[1]) / 256.0)
            }

            if let v = val, v > 20.0 && v < 115.0 {
                if key.hasPrefix("TC") || key.hasPrefix("Tp") || key.hasPrefix("TG") || key.hasPrefix("Tg") {
                    cpuGpuTemps.append(v)
                } else {
                    otherTemps.append(v)
                }
            }
        }

        // Return peak hardware thermal reading (Peak Core temperature represents true silicon thermal load)
        if let peakCpuGpu = cpuGpuTemps.max() {
            return peakCpuGpu
        }
        if let peakOther = otherTemps.max() {
            return peakOther
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

    // MARK: - Fan Reading & Direct Control (ThermalForge Direct Port)

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
        let modeKey = String(format: modeKeyTemplate, index)
        if let (bytes, _) = readSMCBytes(modeKey), let first = bytes.first {
            return first != 0
        }
        if let (bytes, _) = readSMCBytes("FS! "), bytes.count >= 2 {
            let mask = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
            return (mask & (1 << index)) != 0
        }
        return false
    }

    /// ThermalForge Unlock Sequence:
    /// On M1-M4: Writes Ftst=1 to suppress thermalmonitord, sleeps 0.3s, then writes mode=1.
    /// On M5+: Ftst doesn't exist; directly attempts mode write.
    @discardableResult
    public func unlockFans(count: Int? = nil) -> Bool {
        let n = count ?? max(1, fanCount)
        if hasFtst {
            _ = writeSMCBytes("Ftst", bytes: [1])
            Thread.sleep(forTimeInterval: 0.5)
        }

        var successCount = 0
        for i in 0..<n {
            let modeKey = String(format: modeKeyTemplate, i)
            let deadline = Date().addingTimeInterval(5.0)
            while Date() < deadline {
                if writeSMCBytes(modeKey, bytes: [1]) {
                    successCount += 1
                    break
                }
                Thread.sleep(forTimeInterval: 0.05)
            }
        }

        self.isUnlocked = (successCount > 0)
        return self.isUnlocked
    }

    /// ThermalForge Float to SMC Bytes encoding (flt 4-byte or fpe2 fixed-point)
    private func floatToSMCBytes(_ value: Float, for key: String) -> [UInt8] {
        let info = readKeyInfo(key)
        if let info = info, info.type == fourCCToUInt32("fpe2") {
            let raw = UInt16(min(65535.0, max(0.0, Double(value) * 4.0)))
            return [UInt8((raw >> 8) & 0xFF), UInt8(raw & 0xFF)]
        } else {
            var v = value
            return withUnsafeBytes(of: &v) { Array($0) }
        }
    }

    /// Sets target RPM for a specific fan (ThermalForge setSpeed port)
    @discardableResult
    public func setFanSpeed(index: Int, rpm: Double) -> Bool {
        guard isHardwareFanAvailable || fanCount > 0 else { return false }
        if !isUnlocked {
            _ = unlockFans()
        }

        let targetKey = "F\(index)Tg"
        let bytes = floatToSMCBytes(Float(rpm), for: targetKey)
        return writeSMCBytes(targetKey, bytes: bytes)
    }

    /// Sets target RPM for all fans (ThermalForge setAllFans port)
    @discardableResult
    public func setAllFans(rpm: Double) -> Bool {
        let fans = getFans()
        guard !fans.isEmpty else { return false }

        if !isUnlocked {
            _ = unlockFans(count: fans.count)
        }

        var anySuccess = false
        for fan in fans {
            let clamped = min(Double(fan.maxRPM), max(Double(fan.minRPM), rpm))
            let targetKey = "F\(fan.id)Tg"
            let bytes = floatToSMCBytes(Float(clamped), for: targetKey)
            if writeSMCBytes(targetKey, bytes: bytes) {
                anySuccess = true
            }
        }
        return anySuccess
    }

    /// Restores all fans to macOS default automatic control (ThermalForge resetAuto port)
    @discardableResult
    public func restoreAutoFanControl() -> Bool {
        let fans = getFans()
        var allRestored = true

        for i in 0..<max(1, fans.count) {
            let modeKey = String(format: modeKeyTemplate, i)
            if !writeSMCBytes(modeKey, bytes: [0]) {
                allRestored = false
            }
            let targetKey = "F\(i)Tg"
            _ = writeSMCBytes(targetKey, bytes: floatToSMCBytes(0, for: targetKey))
        }

        if hasFtst {
            _ = writeSMCBytes("Ftst", bytes: [0])
        }
        _ = writeSMCBytes("FS! ", bytes: [0, 0])
        self.isUnlocked = false
        return allRestored
    }
}
