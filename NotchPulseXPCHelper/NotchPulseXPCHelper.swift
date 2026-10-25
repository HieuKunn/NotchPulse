//
//  NotchPulseXPCHelper.swift
//  NotchPulseXPCHelper
//
//  Created by Alexander on 2025-11-16.
//

import Foundation
import ApplicationServices
import IOKit
import CoreGraphics

class NotchPulseXPCHelper: NSObject, NotchPulseXPCHelperProtocol {
    
    @objc func isAccessibilityAuthorized(with reply: @escaping (Bool) -> Void) {
        reply(AXIsProcessTrusted())
    }

    @objc func requestAccessibilityAuthorization() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    @objc func ensureAccessibilityAuthorization(_ promptIfNeeded: Bool, with reply: @escaping (Bool) -> Void) {
        if AXIsProcessTrusted() {
            reply(true)
            return
        }

        if promptIfNeeded {
            requestAccessibilityAuthorization()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            reply(AXIsProcessTrusted())
        }
    }
    
    private class KeyboardBrightnessClient {
        private static let keyboardID: UInt64 = 1
        private var clientInstance: NSObject?
        private let getSelector = NSSelectorFromString("brightnessForKeyboard:")
        private let setSelector = NSSelectorFromString("setBrightness:forKeyboard:")

        init() {
            var loaded = false
            let bundlePaths = [
                "/System/Library/PrivateFrameworks/CoreBrightness.framework",
                "/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness"
            ]
            for path in bundlePaths where !loaded {
                if let bundle = Bundle(path: path) {
                    loaded = bundle.load()
                }
            }
            if loaded, let cls = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type {
                clientInstance = cls.init()
            }
        }

        var isAvailable: Bool { clientInstance != nil }

        func currentBrightness() -> Float? {
            guard let clientInstance,
                  let fn: BrightnessGetter = methodIMP(on: clientInstance, selector: getSelector, as: BrightnessGetter.self)
            else { return nil }
            return fn(clientInstance, getSelector, Self.keyboardID)
        }

        func setBrightness(_ value: Float) -> Bool {
            guard let clientInstance,
                  let fn: BrightnessSetter = methodIMP(on: clientInstance, selector: setSelector, as: BrightnessSetter.self)
            else { return false }
            return fn(clientInstance, setSelector, value, Self.keyboardID).boolValue
        }

        private typealias BrightnessGetter = @convention(c) (NSObject, Selector, UInt64) -> Float
        private typealias BrightnessSetter = @convention(c) (NSObject, Selector, Float, UInt64) -> ObjCBool

        private func methodIMP<T>(on object: NSObject, selector: Selector, as type: T.Type) -> T? {
            guard let cls = object_getClass(object),
                  let method = class_getInstanceMethod(cls, selector)
            else { return nil }
            let imp = method_getImplementation(method)
            return unsafeBitCast(imp, to: type)
        }
    }

    private static let keyboardClient = KeyboardBrightnessClient()

    @objc func isKeyboardBrightnessAvailable(with reply: @escaping (Bool) -> Void) {
        reply(Self.keyboardClient.isAvailable)
    }

    @objc func currentKeyboardBrightness(with reply: @escaping (NSNumber?) -> Void) {
        reply(Self.keyboardClient.currentBrightness().map { NSNumber(value: $0) })
    }

    @objc func setKeyboardBrightness(_ value: Float, with reply: @escaping (Bool) -> Void) {
        reply(Self.keyboardClient.setBrightness(value))
    }
    // MARK: - Screen Brightness (multi-display and legacy)

    @objc func isDisplayBrightnessAvailable(for displayID: UInt32, with reply: @escaping (Bool) -> Void) {
        let did = CGDirectDisplayID(displayID)
        var b: Float = 0
        if displayServicesGetBrightness(displayID: did, out: &b) || ioServiceFor(displayID: did) != nil {
            reply(true)
            return
        }
        reply(true)
    }

    @objc func currentDisplayBrightness(for displayID: UInt32, with reply: @escaping (NSNumber?) -> Void) {
        let did = CGDirectDisplayID(displayID)

        // 1. Apple Builtin or Apple-branded Display: DisplayServicesGetBrightness is fast & authoritative
        if CGDisplayIsBuiltin(did) != 0 || CGDisplayVendorNumber(did) == 0x0610 {
            var b: Float = 0
            if displayServicesGetBrightness(displayID: did, out: &b) {
                reply(NSNumber(value: b))
                return
            }
        }

        // 2. Direct Hardware DDC/CI read for external displays (VESA standard) async on global queue
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else {
                reply(nil)
                return
            }
            if let ddcVal = NotchPulseDDC.getBrightness(for: did) {
                reply(NSNumber(value: ddcVal))
                return
            }

            // Fallback DisplayServices (for displays like LG UltraFine with Apple hardware integration)
            var b: Float = 0
            if self.displayServicesGetBrightness(displayID: did, out: &b) {
                reply(NSNumber(value: b))
                return
            }

            // Legacy IOKit (Apple Cinema Displays / Legacy Thunderbolt)
            if let io = self.ioServiceFor(displayID: did) {
                var level: Float = 0
                if IODisplayGetFloatParameter(io, 0, kIODisplayBrightnessKey as CFString, &level) == kIOReturnSuccess {
                    IOObjectRelease(io)
                    reply(NSNumber(value: level))
                    return
                }
                IOObjectRelease(io)
            }
            reply(nil)
        }
    }

    @objc func setDisplayBrightness(_ value: Float, for displayID: UInt32, with reply: @escaping (Bool) -> Void) {
        let did = CGDirectDisplayID(displayID)
        let clamped = max(0, min(1, value))

        // 1. Native Apple DisplayServices for Built-in Retina & Apple-branded Displays (Vendor 0x0610)
        // ⚠️ QUAN TRỌNG: TUYỆT ĐỐI KHÔNG thêm check DisplayServicesCanChangeBrightness tại đây!
        // DisplayServicesSetBrightness với màn hình bên thứ 3 (HKC, Dell, LG...) luôn trả về 0 (thành công giả),
        // làm chặn mất pipeline phần cứng DDC/CI bên dưới!
        let isBuiltin = (CGDisplayIsBuiltin(did) != 0)
        let isAppleBranded = (CGDisplayVendorNumber(did) == 0x0610)

        if isBuiltin || isAppleBranded {
            let ok = displayServicesSetBrightness(displayID: did, value: clamped)
            reply(ok)
            return
        }

        // 2. Direct Hardware DDC/CI Control for External Displays async on global queue
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else {
                reply(false)
                return
            }
            let ddcOk = NotchPulseDDC.setBrightness(clamped, for: did)
            if ddcOk {
                reply(true)
                return
            }

            // Fallback: If DDC fails, test if DisplayServices actually works on this display
            var testB: Float = 0
            if self.displayServicesGetBrightness(displayID: did, out: &testB) {
                if self.displayServicesSetBrightness(displayID: did, value: clamped) {
                    reply(true)
                    return
                }
            }

            // Fallback: Legacy IOKit (Apple Cinema Displays / Legacy Thunderbolt)
            if let io = self.ioServiceFor(displayID: did) {
                let ok = IODisplaySetFloatParameter(io, 0, kIODisplayBrightnessKey as CFString, clamped) == kIOReturnSuccess
                IOObjectRelease(io)
                reply(ok)
                return
            }

            reply(false)
        }
    }

    @objc func currentDisplayVolume(for displayID: UInt32, with reply: @escaping (NSNumber?) -> Void) {
        let did = CGDirectDisplayID(displayID)
        if let vol = NotchPulseDDC.getVolume(for: did) {
            reply(NSNumber(value: vol))
            return
        }
        reply(nil)
    }

    @objc func setDisplayVolume(_ value: Float, for displayID: UInt32, with reply: @escaping (Bool) -> Void) {
        let did = CGDirectDisplayID(displayID)
        let clamped = max(0, min(1, value))
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = NotchPulseDDC.setVolume(clamped, for: did)
            reply(ok)
        }
    }

    @objc func isScreenBrightnessAvailable(with reply: @escaping (Bool) -> Void) {
        isDisplayBrightnessAvailable(for: CGMainDisplayID(), with: reply)
    }

    @objc func currentScreenBrightness(with reply: @escaping (NSNumber?) -> Void) {
        currentDisplayBrightness(for: CGMainDisplayID(), with: reply)
    }

    @objc func setScreenBrightness(_ value: Float, with reply: @escaping (Bool) -> Void) {
        setDisplayBrightness(value, for: CGMainDisplayID(), with: reply)
    }

    // MARK: - DDC Cache Invalidation & Hardware Probe

    @objc func resetDDCCache(with reply: @escaping (Bool) -> Void) {
        NotchPulseDDC.shared.invalidateCache()
        reply(true)
    }

    @objc func isDDCSupported(for displayID: UInt32, with reply: @escaping (Bool) -> Void) {
        let did = CGDirectDisplayID(displayID)
        if CGDisplayIsBuiltin(did) != 0 || CGDisplayVendorNumber(did) == 0x0610 {
            reply(false) // Handled natively by Apple DisplayServices
            return
        }
        let supported = NotchPulseDDC.shared.hasTransport(for: did)
        reply(supported)
    }

    // MARK: - Private helpers for DisplayServices / IOKit access
    private func displayServicesGetBrightness(displayID: CGDirectDisplayID, out: inout Float) -> Bool {
        guard let sym = dlsym(DisplayServicesHandle.handle, "DisplayServicesGetBrightness") else { return false }
        typealias Fn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
        let fn = unsafeBitCast(sym, to: Fn.self)
        var tmp: Float = 0
        let r = fn(displayID, &tmp)
        if r == 0 { out = tmp; return true }
        return false
    }

    private func displayServicesSetBrightness(displayID: CGDirectDisplayID, value: Float) -> Bool {
        guard let sym = dlsym(DisplayServicesHandle.handle, "DisplayServicesSetBrightness") else { return false }
        typealias Fn = @convention(c) (CGDirectDisplayID, Float) -> Int32
        let fn = unsafeBitCast(sym, to: Fn.self)
        return fn(displayID, value) == 0
    }

    private func ioServiceFor(displayID: CGDirectDisplayID) -> io_service_t? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IODisplayConnect"), &iterator) == kIOReturnSuccess else { return nil }
        defer { IOObjectRelease(iterator) }

        while case let service = IOIteratorNext(iterator), service != 0 {
            let info = IODisplayCreateInfoDictionary(service, 0).takeRetainedValue() as NSDictionary
            if let vendorID = info[kDisplayVendorID] as? UInt32,
               let productID = info[kDisplayProductID] as? UInt32,
               vendorID == CGDisplayVendorNumber(displayID),
               productID == CGDisplayModelNumber(displayID) {
                return service
            }
            IOObjectRelease(service)
        }
        return nil
    }

    // MARK: - Helper handle for private framework
    private enum DisplayServicesHandle {
        static let handle: UnsafeMutableRawPointer? = {
            let paths = [
                "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
                "/System/Library/PrivateFrameworks/DisplayServices.framework/Versions/Current/DisplayServices"
            ]
            for p in paths {
                if let h = dlopen(p, RTLD_LAZY) { return h }
            }
            return nil
        }()
    }
}
