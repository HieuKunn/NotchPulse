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
        return discovery.devices
            .filter { $0.isConnected && !$0.isSuspended }
            .map { CameraDevice(id: $0.uniqueID, name: $0.localizedName) }
    }

    /// Checks if a device is connected, not suspended, and valid for capture.
    static func isDeviceHealthy(_ device: AVCaptureDevice?) -> Bool {
        guard let device else { return false }
        return device.isConnected && !device.isSuspended
    }

    /// True if the currently-active screen is the Mac's built-in display
    /// (vs. an external monitor) — used to pick between the built-in/
    /// external camera overrides matching Glance.
    @MainActor
    static func isUsingBuiltInDisplay() -> Bool {
        guard let screen = NSScreen.main,
              let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        else { return true }
        return CGDisplayIsBuiltin(screenNumber) != 0
    }

    /// Display-specific override, then flat default, then the system default camera matching Glance.
    /// Strictly guarantees returned device is connected and not suspended; gracefully falls back
    /// if a preferred external/Continuity camera is unplugged or asleep.
    @MainActor
    static func resolvedDevice() -> AVCaptureDevice? {
        let settings = NotchPulseFaceIDSettings.shared
        let isBuiltIn = isUsingBuiltInDisplay()
        let preferredID = isBuiltIn
            ? (settings.builtInDisplayCameraID ?? settings.defaultCameraID)
            : (settings.externalDisplayCameraID ?? settings.defaultCameraID)

        if let preferredID,
           let device = AVCaptureDevice(uniqueID: preferredID),
           isDeviceHealthy(device) {
            return device
        }

        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video,
            position: .unspecified
        )
        let connectedDevices = discovery.devices.filter { isDeviceHealthy($0) }

        if isBuiltIn {
            if let builtIn = connectedDevices.first(where: { $0.deviceType == .builtInWideAngleCamera }) {
                return builtIn
            }
            if let anyConnected = connectedDevices.first {
                return anyConnected
            }
        } else {
            if let external = connectedDevices.first(where: { $0.deviceType == .external || $0.deviceType == .continuityCamera }) {
                return external
            }
            if let builtIn = connectedDevices.first(where: { $0.deviceType == .builtInWideAngleCamera }) {
                return builtIn
            }
            if let anyConnected = connectedDevices.first {
                return anyConnected
            }
        }

        if let defaultBuiltIn = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
           isDeviceHealthy(defaultBuiltIn) {
            return defaultBuiltIn
        }
        if let defaultVideo = AVCaptureDevice.default(for: .video),
           isDeviceHealthy(defaultVideo) {
            return defaultVideo
        }

        return nil
    }

    @MainActor
    static func invalidateTargetScreenCache() {}
}
