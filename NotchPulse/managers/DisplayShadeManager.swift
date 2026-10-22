//
//  DisplayShadeManager.swift
//  NotchPulse
//
//  Provides seamless software dimming (window shade overlay) for external displays
//  where hardware DDC is unavailable, blocked by HDMI adapters, or ignored by monitors.
//

import AppKit
import Defaults
import Foundation

final class DisplayShadeManager: ObservableObject {
    static let shared = DisplayShadeManager()

    private var shades: [CGDirectDisplayID: NSWindow] = [:]
    private var displayBrightness: [CGDirectDisplayID: Float] = [:]

    private init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateShadeFrames()
        }
    }

    func setBrightness(_ value: Float, for displayID: CGDirectDisplayID) {
        let clamped = max(0.0, min(1.0, value))
        displayBrightness[displayID] = clamped

        // Only external third-party displays need the software shade overlay
        guard Defaults[.enableSoftwareDimming], CGDisplayIsBuiltin(displayID) == 0 else {
            DispatchQueue.main.async { [weak self] in
                self?.removeShade(for: displayID)
            }
            return
        }

        // Target alpha: At 100% brightness (1.0), alpha is 0.0 (completely clear/transparent).
        // At 0% brightness, alpha is 0.90 (comfortably dark without turning screen 100% black).
        let shadeAlpha = CGFloat((1.0 - clamped) * 0.90)

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if shadeAlpha <= 0.005 {
                self.removeShade(for: displayID)
            } else {
                let shade = self.getOrCreateShade(for: displayID)
                shade?.alphaValue = shadeAlpha
                shade?.orderFrontRegardless()
            }
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
            defer: false
        )
        shade.title = "NotchPulse Display Shade (\(displayID))"
        shade.isOpaque = false
        shade.backgroundColor = .black
        shade.ignoresMouseEvents = true
        shade.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        shade.collectionBehavior = [.stationary, .canJoinAllSpaces, .ignoresCycle]
        shade.alphaValue = 0.0
        shade.orderFrontRegardless()

        shades[displayID] = shade
        return shade
    }

    private func removeShade(for displayID: CGDirectDisplayID) {
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

    func removeAllShades() {
        for (_, shade) in shades {
            shade.orderOut(nil)
        }
        shades.removeAll()
    }
}
