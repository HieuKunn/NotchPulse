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

    func setBrightness(_ value: Float, for displayID: CGDirectDisplayID) {
        // Disabled: Never manipulate gamma or create shade overlays.
        // Pure hardware backlight control only.
    }

    func restoreNativeDisplay(for displayID: CGDirectDisplayID) {
        CGDisplayRestoreColorSyncSettings()
    }

    func removeAllShades() {
        CGDisplayRestoreColorSyncSettings()
    }
}
