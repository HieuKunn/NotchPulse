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
        // Disabled: Never spawn full-screen shielding windows over user displays.
        // Clean up any remaining shades to eliminate screen flicker.
        removeAllShades()
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

    func removeShade(for displayID: CGDirectDisplayID) {
        DispatchQueue.main.async { [weak self] in
            if let shade = self?.shades.removeValue(forKey: displayID) {
                shade.orderOut(nil)
            }
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
