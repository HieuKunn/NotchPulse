//
//  NotchPulseDDC.swift
//  NotchPulseXPCHelper
//
//  A lightweight, robust DDC/CI engine for controlling external display brightness & volume
//  Adapted for NotchPulse from MonitorControl & VESA DDC specifications.
//

import Foundation
import AppKit
import CoreGraphics
import IOKit
#if canImport(IOKit.i2c)
import IOKit.i2c
#endif

// MARK: - Dynamic Private Framework Bridge (No Compile-Time Linker Dependencies)

private enum DynamicBridge {
    static let coreDisplayHandle: UnsafeMutableRawPointer? = {
        let paths = [
            "/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay",
            "/System/Library/Frameworks/CoreDisplay.framework/Versions/Current/CoreDisplay"
        ]
        for p in paths {
            if let h = dlopen(p, RTLD_LAZY) { return h }
        }
        return nil
    }()

    static let ioKitHandle: UnsafeMutableRawPointer? = {
        dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY)
    }()

    static let skyLightHandle: UnsafeMutableRawPointer? = {
        let paths = [
            "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
            "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/Current/SkyLight"
        ]
        for p in paths {
            if let h = dlopen(p, RTLD_LAZY) { return h }
        }
        return nil
    }()

    static func coreDisplayInfoDictionary(_ displayID: CGDirectDisplayID) -> NSDictionary? {
        guard let handle = coreDisplayHandle,
              let sym = dlsym(handle, "CoreDisplay_DisplayCreateInfoDictionary") else { return nil }
        typealias Fn = @convention(c) (CGDirectDisplayID) -> Unmanaged<CFDictionary>?
        let fn = unsafeBitCast(sym, to: Fn.self)
        return fn(displayID)?.takeRetainedValue() as NSDictionary?
    }

    #if arch(arm64)
    static func createAVService(_ service: io_service_t) -> CFTypeRef? {
        guard let handle = ioKitHandle,
              let sym = dlsym(handle, "IOAVServiceCreateWithService") else { return nil }
        typealias Fn = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<CFTypeRef>?
        let fn = unsafeBitCast(sym, to: Fn.self)
        return fn(kCFAllocatorDefault, service)?.takeRetainedValue()
    }

    static func writeI2C(service: CFTypeRef, chipAddress: UInt32, dataAddress: UInt32, buffer: UnsafeMutableRawPointer?, length: UInt32) -> IOReturn {
        guard let handle = ioKitHandle,
              let sym = dlsym(handle, "IOAVServiceWriteI2C") else { return kIOReturnUnsupported }
        typealias Fn = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer?, UInt32) -> IOReturn
        let fn = unsafeBitCast(sym, to: Fn.self)
        return fn(service, chipAddress, dataAddress, buffer, length)
    }

    static func readI2C(service: CFTypeRef, chipAddress: UInt32, dataAddress: UInt32, buffer: UnsafeMutableRawPointer?, length: UInt32) -> IOReturn {
        guard let handle = ioKitHandle,
              let sym = dlsym(handle, "IOAVServiceReadI2C") else { return kIOReturnUnsupported }
        typealias Fn = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer?, UInt32) -> IOReturn
        let fn = unsafeBitCast(sym, to: Fn.self)
        return fn(service, chipAddress, dataAddress, buffer, length)
    }
    #endif

    #if arch(x86_64)
    static func serviceForDisplayNumber(_ displayID: CGDirectDisplayID) -> io_service_t {
        guard let handle = skyLightHandle,
              let sym = dlsym(handle, "CGSServiceForDisplayNumber") else { return 0 }
        typealias Fn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<io_service_t>) -> Void
        let fn = unsafeBitCast(sym, to: Fn.self)
        var s: io_service_t = 0
        fn(displayID, &s)
        return s
    }
    #endif
}

// MARK: - NotchPulseDDC Engine

final class NotchPulseDDC {
    static let shared = NotchPulseDDC()

    private let ddcQueue = DispatchQueue(label: "com.notchpulse.ddc", qos: .userInitiated)
    
    // VCP Codes (VESA MCCS standard)
    enum VCP: UInt8 {
        case brightness = 0x10
        case contrast   = 0x12
        case volume     = 0x62
        case mute       = 0x8D
    }
    
    private let ddc7BitAddress: UInt32 = 0x37
    private let ddcDataAddress: UInt32 = 0x51
    
    #if arch(arm64)
    private var serviceCache: [CGDirectDisplayID: CFTypeRef] = [:]
    #endif

    private init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.invalidateCache()
        }
    }

    func invalidateCache() {
        ddcQueue.async {
            #if arch(arm64)
            self.serviceCache.removeAll()
            #endif
        }
    }

    // MARK: - Public High-Level Controls

    static func setBrightness(_ value: Float, for displayID: CGDirectDisplayID) -> Bool {
        let clamped = max(0.0, min(1.0, value))
        let vcpValue = UInt16(round(clamped * 100.0))
        return shared.write(vcp: .brightness, value: vcpValue, displayID: displayID)
    }

    static func getBrightness(for displayID: CGDirectDisplayID) -> Float? {
        guard let (current, maxVal) = shared.read(vcp: .brightness, displayID: displayID), maxVal > 0 else {
            return nil
        }
        return Float(current) / Float(maxVal)
    }

    static func setVolume(_ value: Float, for displayID: CGDirectDisplayID) -> Bool {
        let clamped = max(0.0, min(1.0, value))
        let vcpValue = UInt16(round(clamped * 100.0))
        return shared.write(vcp: .volume, value: vcpValue, displayID: displayID)
    }

    static func getVolume(for displayID: CGDirectDisplayID) -> Float? {
        guard let (current, maxVal) = shared.read(vcp: .volume, displayID: displayID), maxVal > 0 else {
            return nil
        }
        return Float(current) / Float(maxVal)
    }

    // MARK: - Internal Read / Write Dispatcher

    func write(vcp: VCP, value: UInt16, displayID: CGDirectDisplayID) -> Bool {
        if CGDisplayIsBuiltin(displayID) != 0 {
            return false
        }
        return ddcQueue.sync {
            #if arch(arm64)
            return writeArm64(command: vcp.rawValue, value: value, displayID: displayID)
            #elseif arch(x86_64)
            return writeIntel(command: vcp.rawValue, value: value, displayID: displayID)
            #else
            return false
            #endif
        }
    }

    func read(vcp: VCP, displayID: CGDirectDisplayID) -> (current: UInt16, max: UInt16)? {
        if CGDisplayIsBuiltin(displayID) != 0 {
            return nil
        }
        return ddcQueue.sync {
            #if arch(arm64)
            return readArm64(command: vcp.rawValue, displayID: displayID)
            #elseif arch(x86_64)
            return readIntel(command: vcp.rawValue, displayID: displayID)
            #else
            return nil
            #endif
        }
    }

    // MARK: - Apple Silicon (ARM64) DDC Implementation

    #if arch(arm64)
    private func serviceForDisplay(displayID: CGDirectDisplayID) -> CFTypeRef? {
        if let cached = serviceCache[displayID] {
            return cached
        }

        let candidates = findArm64Services()
        guard !candidates.isEmpty else { return nil }

        // If only 1 external display and 1 external service, pair directly
        if candidates.count == 1 {
            let matched = candidates[0].service
            serviceCache[displayID] = matched
            return matched
        }

        // Multiple external displays: Match by score (Vendor, Product ID, EDID, Name)
        var bestService: CFTypeRef? = nil
        var bestScore = -1

        let displayDict = DynamicBridge.coreDisplayInfoDictionary(displayID)
        let targetVendor = (displayDict?[kDisplayVendorID] as? Int64) ?? Int64(CGDisplayVendorNumber(displayID))
        let targetProduct = (displayDict?[kDisplayProductID] as? Int64) ?? Int64(CGDisplayModelNumber(displayID))
        let targetSerial = (displayDict?[kDisplaySerialNumber] as? Int64) ?? Int64(CGDisplaySerialNumber(displayID))
        let targetName = (displayDict?["DisplayProductName"] as? [String: String])?["en_US"]?.lowercased()

        for candidate in candidates {
            var score = 0
            if candidate.location == "External" { score += 5 }
            if targetVendor > 0, let mfg = candidate.manufacturerID, !mfg.isEmpty {
                let vendorHex = String(format: "%04X", targetVendor)
                if mfg.uppercased().contains(vendorHex) { score += 10 }
            }
            if targetProduct > 0, let prod = candidate.productName, !prod.isEmpty {
                let prodHex = String(format: "%04X", targetProduct)
                if prod.uppercased().contains(prodHex) { score += 10 }
            }
            if let targetName = targetName, let prod = candidate.productName, prod.lowercased().contains(targetName) {
                score += 15
            }
            if targetSerial > 0, candidate.serialNumber == targetSerial {
                score += 20
            }

            if score > bestScore {
                bestScore = score
                bestService = candidate.service
            }
        }

        let result = bestService ?? candidates.first?.service
        if let result = result {
            serviceCache[displayID] = result
        }
        return result
    }

    private struct DiscoveredService {
        let service: CFTypeRef
        let location: String
        let edidUUID: String?
        let manufacturerID: String?
        let productName: String?
        let serialNumber: Int64?
    }

    private func findArm64Services() -> [DiscoveredService] {
        var results: [DiscoveredService] = []
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        defer { IOObjectRelease(root) }

        var iterator: io_iterator_t = 0
        guard IORegistryEntryCreateIterator(root, "IOService", IOOptionBits(kIORegistryIterateRecursively), &iterator) == KERN_SUCCESS else {
            return results
        }
        defer { IOObjectRelease(iterator) }

        let namePtr = UnsafeMutablePointer<CChar>.allocate(capacity: MemoryLayout<io_name_t>.size)
        defer { namePtr.deallocate() }

        var currentEDID: String? = nil
        var currentMfg: String? = nil
        var currentProd: String? = nil
        var currentSerial: Int64? = nil

        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            guard IORegistryEntryGetName(entry, namePtr) == KERN_SUCCESS else { continue }
            let name = String(cString: namePtr)

            if name.contains("AppleCLCD2") || name.contains("IOMobileFramebufferShim") {
                if let unmanagedEdid = IORegistryEntryCreateCFProperty(entry, "EDID UUID" as CFString, kCFAllocatorDefault, 0),
                   let edid = unmanagedEdid.takeRetainedValue() as? String {
                    currentEDID = edid
                }
                if let unmanagedAttrs = IORegistryEntryCreateCFProperty(entry, "DisplayAttributes" as CFString, kCFAllocatorDefault, 0),
                   let attrs = unmanagedAttrs.takeRetainedValue() as? NSDictionary,
                   let prodAttrs = attrs["ProductAttributes"] as? NSDictionary {
                    currentMfg = prodAttrs["ManufacturerID"] as? String
                    currentProd = prodAttrs["ProductName"] as? String
                    currentSerial = prodAttrs["SerialNumber"] as? Int64
                }
            } else if name.contains("DCPAVServiceProxy") {
                if let unmanagedLoc = IORegistryEntryCreateCFProperty(entry, "Location" as CFString, kCFAllocatorDefault, 0),
                   let loc = unmanagedLoc.takeRetainedValue() as? String, loc == "External" {
                    if let avService = DynamicBridge.createAVService(entry) {
                        results.append(DiscoveredService(
                            service: avService,
                            location: loc,
                            edidUUID: currentEDID,
                            manufacturerID: currentMfg,
                            productName: currentProd,
                            serialNumber: currentSerial
                        ))
                    }
                }
            }
        }
        return results
    }

    private func writeArm64(command: UInt8, value: UInt16, displayID: CGDirectDisplayID) -> Bool {
        guard let service = serviceForDisplay(displayID: displayID) else { return false }

        let send: [UInt8] = [command, UInt8(value >> 8), UInt8(value & 0xFF)]
        var packet: [UInt8] = [UInt8(0x80 | (send.count + 1)), UInt8(send.count)] + send + [0]
        var chkd: UInt8 = (UInt8(ddc7BitAddress) << 1) ^ UInt8(ddcDataAddress)
        for byte in packet.dropLast() {
            chkd ^= byte
        }
        packet[packet.count - 1] = chkd

        var success = false
        for _ in 1...3 {
            usleep(10000)
            let res = DynamicBridge.writeI2C(service: service, chipAddress: ddc7BitAddress, dataAddress: ddcDataAddress, buffer: &packet, length: UInt32(packet.count))
            if res == 0 {
                success = true
                break
            }
            usleep(20000)
        }
        return success
    }

    private func readArm64(command: UInt8, displayID: CGDirectDisplayID) -> (UInt16, UInt16)? {
        guard let service = serviceForDisplay(displayID: displayID) else { return nil }

        let send: [UInt8] = [command]
        var reply = [UInt8](repeating: 0, count: 11)

        var packet: [UInt8] = [UInt8(0x80 | (send.count + 1)), UInt8(send.count)] + send + [0]
        var chkd: UInt8 = (UInt8(ddc7BitAddress) << 1)
        for byte in packet.dropLast() {
            chkd ^= byte
        }
        packet[packet.count - 1] = chkd

        for _ in 1...4 {
            usleep(10000)
            if DynamicBridge.writeI2C(service: service, chipAddress: ddc7BitAddress, dataAddress: ddcDataAddress, buffer: &packet, length: UInt32(packet.count)) != 0 {
                continue
            }
            usleep(50000)
            if DynamicBridge.readI2C(service: service, chipAddress: ddc7BitAddress, dataAddress: 0, buffer: &reply, length: UInt32(reply.count)) == 0 {
                var replyChk: UInt8 = 0x50
                for b in reply.dropLast() {
                    replyChk ^= b
                }
                if replyChk == reply.last {
                    let max = UInt16(reply[6]) * 256 + UInt16(reply[7])
                    let cur = UInt16(reply[8]) * 256 + UInt16(reply[9])
                    return (cur, max)
                }
            }
            usleep(20000)
        }
        return nil
    }
    #endif

    // MARK: - Intel (x86_64) DDC Implementation

    #if arch(x86_64)
    private func framebufferForDisplay(displayID: CGDirectDisplayID) -> io_service_t? {
        let service = DynamicBridge.serviceForDisplayNumber(displayID)
        if service != 0 {
            return service
        }

        var portIterator = io_iterator_t()
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOFramebuffer"), &portIterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(portIterator) }

        while case let port = IOIteratorNext(portIterator), port != 0 {
            let dict = IODisplayCreateInfoDictionary(port, IOOptionBits(kIODisplayOnlyPreferredName)).takeRetainedValue() as NSDictionary
            let portVendor = (dict[kDisplayVendorID] as? CFIndex).flatMap { UInt32(bitPattern: Int32(exactly: $0) ?? 0) } ?? 0
            let portProduct = (dict[kDisplayProductID] as? CFIndex).flatMap { UInt32(bitPattern: Int32(exactly: $0) ?? 0) } ?? 0

            if portVendor == CGDisplayVendorNumber(displayID) && portProduct == CGDisplayModelNumber(displayID) {
                return port
            }
            IOObjectRelease(port)
        }
        return nil
    }

    private func writeIntel(command: UInt8, value: UInt16, displayID: CGDirectDisplayID) -> Bool {
        guard let fb = framebufferForDisplay(displayID: displayID) else { return false }
        defer { IOObjectRelease(fb) }

        var data = [UInt8](repeating: 0, count: 7)
        data[0] = 0x51
        data[1] = 0x84
        data[2] = 0x03
        data[3] = command
        data[4] = UInt8(value >> 8)
        data[5] = UInt8(value & 0xFF)
        data[6] = 0x6E ^ data[0] ^ data[1] ^ data[2] ^ data[3] ^ data[4] ^ data[5]

        var success = false
        for _ in 1...2 {
            usleep(10000)
            var request = IOI2CRequest()
            request.commFlags = 0
            request.sendAddress = 0x6E
            request.sendTransactionType = IOOptionBits(kIOI2CSimpleTransactionType)
            request.sendBuffer = withUnsafePointer(to: &data[0]) { vm_address_t(bitPattern: $0) }
            request.sendBytes = UInt32(data.count)
            request.replyTransactionType = IOOptionBits(kIOI2CNoTransactionType)
            request.replyBytes = 0

            var busCount: IOItemCount = 0
            if IOFBGetI2CInterfaceCount(fb, &busCount) == KERN_SUCCESS, busCount > 0 {
                for bus: IOOptionBits in 0..<busCount {
                    var interface: io_service_t = 0
                    if IOFBCopyI2CInterfaceForBus(fb, bus, &interface) == KERN_SUCCESS {
                        var connect: IOI2CConnectRef?
                        if IOI2CInterfaceOpen(interface, IOOptionBits(), &connect) == KERN_SUCCESS, let connect = connect {
                            if IOI2CSendRequest(connect, IOOptionBits(), &request) == KERN_SUCCESS, request.result == KERN_SUCCESS {
                                success = true
                            }
                            IOI2CInterfaceClose(connect, IOOptionBits())
                        }
                        IOObjectRelease(interface)
                    }
                    if success { break }
                }
            }
            if success { break }
        }
        return success
    }

    private func readIntel(command: UInt8, displayID: CGDirectDisplayID) -> (UInt16, UInt16)? {
        guard let fb = framebufferForDisplay(displayID: displayID) else { return nil }
        defer { IOObjectRelease(fb) }

        var data: [UInt8] = [0x51, 0x82, 0x01, command, 0]
        data[4] = 0x6E ^ data[0] ^ data[1] ^ data[2] ^ data[3]
        var reply = [UInt8](repeating: 0, count: 11)

        for _ in 1...3 {
            usleep(10000)
            var request = IOI2CRequest()
            request.commFlags = 0
            request.sendAddress = 0x6E
            request.sendTransactionType = IOOptionBits(kIOI2CSimpleTransactionType)
            request.sendBuffer = withUnsafePointer(to: &data[0]) { vm_address_t(bitPattern: $0) }
            request.sendBytes = UInt32(data.count)
            request.minReplyDelay = 10
            request.replyAddress = 0x6F
            request.replySubAddress = 0x51
            request.replyTransactionType = IOOptionBits(kIOI2CDDCciReplyTransactionType)
            request.replyBytes = UInt32(reply.count)
            request.replyBuffer = withUnsafePointer(to: &reply[0]) { vm_address_t(bitPattern: $0) }

            var busCount: IOItemCount = 0
            if IOFBGetI2CInterfaceCount(fb, &busCount) == KERN_SUCCESS, busCount > 0 {
                for bus: IOOptionBits in 0..<busCount {
                    var interface: io_service_t = 0
                    if IOFBCopyI2CInterfaceForBus(fb, bus, &interface) == KERN_SUCCESS {
                        var connect: IOI2CConnectRef?
                        if IOI2CInterfaceOpen(interface, IOOptionBits(), &connect) == KERN_SUCCESS, let connect = connect {
                            let sendRes = IOI2CSendRequest(connect, IOOptionBits(), &request)
                            IOI2CInterfaceClose(connect, IOOptionBits())
                            if sendRes == KERN_SUCCESS, request.result == KERN_SUCCESS {
                                let (mh, ml, sh, sl) = (reply[6], reply[7], reply[8], reply[9])
                                let maxVal = UInt16(mh << 8) + UInt16(ml)
                                let curVal = UInt16(sh << 8) + UInt16(sl)
                                IOObjectRelease(interface)
                                return (curVal, maxVal)
                            }
                        }
                        IOObjectRelease(interface)
                    }
                }
            }
            usleep(20000)
        }
        return nil
    }
    #endif
}
