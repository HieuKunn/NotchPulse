//
//  DisplayShadeManager.swift
//  NotchPulse
//
//  Provides seamless software dimming (window shade overlay) for external displays
//  where hardware DDC is unavailable, blocked by HDMI adapters, or ignored by monitors.
//

import AppKit
import CoreGraphics
import Foundation

@MainActor
final class DisplayShadeManager: ObservableObject {
    static let shared = DisplayShadeManager()

    private var shades: [CGDirectDisplayID: NSWindow] = [:]

    private init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateShadeFrames()
        }
    }

    /// Áp dụng Software Dimming (bằng Black Window Shade Overlay) cho các màn hình ảo / Sidecar (iPad, AirPlay).
    /// Vì Sidecar/AirPlay không có chip GPU CRTC/DAC phần cứng, macOS mã hoá video trực tiếp từ WindowServer.
    /// Do đó, lớp phủ NSWindow là cách duy nhất và chuẩn nhất để giảm sáng hiển thị trên iPad.
    /// Tuyệt đối KHÔNG áp dụng cho màn hình ngoài vật lý có DDC (HKC, Dell, LG...).
    func setBrightness(_ value: Float, for displayID: CGDirectDisplayID) {
        let clamped = max(0.05, min(1.0, value))

        // Nếu ở mức 100% (>= 0.99), ẩn shade hoàn toàn để tiết kiệm tài nguyên GPU
        if clamped >= 0.99 {
            removeShade(for: displayID)
            return
        }

        // Mức độ mờ tối của lớp phủ: độ sáng 0.1 -> alpha 0.9, độ sáng 0.8 -> alpha 0.2
        let shadeAlpha = CGFloat(1.0 - clamped)

        guard let window = getOrCreateShade(for: displayID) else { return }
        window.alphaValue = shadeAlpha
        if !window.isVisible {
            window.orderFrontRegardless()
        }
    }

    private func getOrCreateShade(for displayID: CGDirectDisplayID) -> NSWindow? {
        if let existing = shades[displayID] {
            return existing
        }

        guard let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == displayID
        }) else { return nil }

        let shade = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        shade.title = "NotchPulse Sidecar Shade (\(displayID))"
        shade.isOpaque = false
        shade.backgroundColor = .black
        shade.ignoresMouseEvents = true
        // ShieldingWindowLevel đảm bảo phủ lên toàn bộ nội dung hiển thị trên màn hình Sidecar
        shade.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        shade.collectionBehavior = [.stationary, .canJoinAllSpaces, .ignoresCycle, .fullScreenAuxiliary]
        shade.hasShadow = false
        shade.alphaValue = 0.0

        shades[displayID] = shade
        return shade
    }

    func removeShade(for displayID: CGDirectDisplayID) {
        if let shade = shades.removeValue(forKey: displayID) {
            shade.orderOut(nil)
        }
    }

    func updateShadeFrames() {
        for (id, shade) in shades {
            if let screen = NSScreen.screens.first(where: {
                ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == id
            }) {
                shade.setFrame(screen.frame, display: true)
            } else {
                removeShade(for: id)
            }
        }
    }

    func restoreNativeDisplay(for displayID: CGDirectDisplayID) {
        removeShade(for: displayID)
    }

    func removeAllShades() {
        for (_, shade) in shades {
            shade.orderOut(nil)
        }
        shades.removeAll()
    }
}
