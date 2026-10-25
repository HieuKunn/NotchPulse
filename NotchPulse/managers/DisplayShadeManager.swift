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

final class DisplayShadeManager: ObservableObject {
    static let shared = DisplayShadeManager()

    // Original hardware gamma tables cached per display
    private var originalGammaTables: [CGDirectDisplayID: (red: [CGGammaValue], green: [CGGammaValue], blue: [CGGammaValue], count: UInt32)] = [:]

    private init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.originalGammaTables.removeAll()
        }
    }

    /// Áp dụng Software Dimming (giảm sáng bằng Gamma Table) cho các màn hình KHÔNG có DDC phần cứng (như iPad Sidecar, AirPlay, màn ảo).
    /// Tuyệt đối KHÔNG áp dụng cho các màn hình hỗ trợ DDC phần cứng (HKC, Dell, LG...) để đảm bảo độ sáng vật lý thật 100%.
    func setBrightness(_ value: Float, for displayID: CGDirectDisplayID) {
        let clamped = max(0.05, min(1.0, value))
        applyGammaDimming(factor: clamped, for: displayID)
    }

    private func applyGammaDimming(factor: Float, for displayID: CGDirectDisplayID) {
        if originalGammaTables[displayID] == nil {
            var red = [CGGammaValue](repeating: 0, count: 256)
            var green = [CGGammaValue](repeating: 0, count: 256)
            var blue = [CGGammaValue](repeating: 0, count: 256)
            var sampleCount: UInt32 = 0
            if CGGetDisplayTransferByTable(displayID, 256, &red, &green, &blue, &sampleCount) == .success, sampleCount > 0 {
                originalGammaTables[displayID] = (red, green, blue, sampleCount)
            }
        }

        guard let original = originalGammaTables[displayID] else { return }

        if factor >= 0.999 {
            _ = CGSetDisplayTransferByTable(displayID, original.count, original.red, original.green, original.blue)
            return
        }

        let gammaScale = CGGammaValue(factor)
        let dimmedRed = original.red.map { $0 * gammaScale }
        let dimmedGreen = original.green.map { $0 * gammaScale }
        let dimmedBlue = original.blue.map { $0 * gammaScale }
        _ = CGSetDisplayTransferByTable(displayID, original.count, dimmedRed, dimmedGreen, dimmedBlue)
    }

    func restoreNativeDisplay(for displayID: CGDirectDisplayID) {
        if let original = originalGammaTables[displayID] {
            _ = CGSetDisplayTransferByTable(displayID, original.count, original.red, original.green, original.blue)
        } else {
            CGDisplayRestoreColorSyncSettings()
        }
    }

    func removeAllShades() {
        for (id, original) in originalGammaTables {
            _ = CGSetDisplayTransferByTable(id, original.count, original.red, original.green, original.blue)
        }
        originalGammaTables.removeAll()
        CGDisplayRestoreColorSyncSettings()
    }
}
