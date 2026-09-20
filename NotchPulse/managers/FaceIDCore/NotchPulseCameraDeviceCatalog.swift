//
//  NotchPulseCameraDeviceCatalog.swift
//  NotchPulse
//
//  Resolves the app's camera preference (flat default, or split by built-in vs. external display) into the device to open.
//

import AVFoundation
import AppKit

struct CameraDevice: Identifiable, Hashable {
    let id: String // AVCaptureDevice.uniqueID
    let name: String
}

enum NotchPulseCameraDeviceCatalog {
    static func availableDevices() -> [CameraDevice] {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video,
            position: .unspecified
        )
        return discovery.devices.map { CameraDevice(id: $0.uniqueID, name: $0.localizedName) }
    }

    /// True if the currently-active screen is the Mac's built-in display
    /// (vs. an external monitor) — used to pick between the built-in/
    /// external camera overrides.
    @MainActor
    static func isUsingBuiltInDisplay() -> Bool {
        guard let screen = FaceIDOverlayGeometry.preferredScreen() ?? NSScreen.main,
              let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        else { return true }
        return CGDisplayIsBuiltin(screenNumber) != 0
    }

    /// Display-specific override, then flat default, then the system default camera.
    @MainActor
    static func resolvedDevice() -> AVCaptureDevice? {
        let settings = NotchPulseFaceIDSettings.shared
        let preferredID = isUsingBuiltInDisplay()
            ? (settings.builtInDisplayCameraID ?? settings.defaultCameraID)
            : (settings.externalDisplayCameraID ?? settings.defaultCameraID)

        if let preferredID, let device = AVCaptureDevice(uniqueID: preferredID) {
            return device
        }
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            ?? AVCaptureDevice.default(for: .video)
    }

    /// Finds which screen physically corresponds to the camera being used for Face ID
    @MainActor
    static func targetScreen(for device: AVCaptureDevice?) -> NSScreen? {
        guard let device else {
            return NSScreen.screens.first(where: { $0.isBuiltIn || $0.safeAreaInsets.top > 0 }) ?? NSScreen.main
        }
        
        // 1. Built-in camera (MacBook webcam) -> Built-in screen
        if device.deviceType == .builtInWideAngleCamera
            || device.localizedName.localizedCaseInsensitiveContains("built-in")
            || device.localizedName.localizedCaseInsensitiveContains("MacBook")
            || device.localizedName.localizedCaseInsensitiveContains("FaceTime") {
            if let builtInScreen = NSScreen.screens.first(where: { $0.isBuiltIn || $0.safeAreaInsets.top > 0 }) {
                return builtInScreen
            }
        }
        
        // 2. Camera whose name matches an external monitor name (e.g., Studio Display)
        for screen in NSScreen.screens where !screen.isBuiltIn {
            let screenName = screen.localizedName.lowercased()
            let devName = device.localizedName.lowercased()
            if devName.contains(screenName) || screenName.contains(devName) {
                return screen
            }
        }
        
        // 3. External camera (webcam on external monitor) -> First non-builtin screen
        if device.deviceType == .external || device.deviceType == .continuityCamera {
            if let externalScreen = NSScreen.screens.first(where: { !$0.isBuiltIn && $0.safeAreaInsets.top == 0 }) {
                return externalScreen
            }
        }
        
        // Default fallback
        return NSScreen.screens.first(where: { $0.isBuiltIn || $0.safeAreaInsets.top > 0 }) ?? NSScreen.main
    }
}
