import AVFoundation
import AppKit

enum NotchPulseCameraDeviceCatalog {
    /// Checks if a device is connected, not suspended, and valid for capture.
    static func isDeviceHealthy(_ device: AVCaptureDevice?) -> Bool {
        guard let device else { return false }
        return device.isConnected && !device.isSuspended
    }

    static func isContinuityOrMobileCamera(_ device: AVCaptureDevice) -> Bool {
        device.deviceType == .continuityCamera
            || device.modelID.hasPrefix("iPhone")
            || device.modelID.hasPrefix("iPad")
    }

    /// True if NotchPulse's active display is the Mac's built-in display
    /// (vs. an external monitor).
    @MainActor
    static func isUsingBuiltInDisplay() -> Bool {
        guard let screen = FaceIDOverlayGeometry.standardScreen() ?? NSScreen.main else { return true }
        return screen.isBuiltIn
    }

    /// Automatically picks the best healthy camera (built-in or wired external),
    /// only falling back to Continuity/iPhone cameras if no primary camera is available.
    @MainActor
    static func resolvedDevice() -> AVCaptureDevice? {
        resolvedDevices().first
    }

    /// Ordered candidate list (primary choice followed by healthy fallbacks).
    @MainActor
    static func resolvedDevices() -> [AVCaptureDevice] {
        let isBuiltIn = isUsingBuiltInDisplay()
        var candidates: [AVCaptureDevice] = []
        var seenIDs = Set<String>()

        func appendIfHealthy(_ device: AVCaptureDevice?) {
            guard let device, isDeviceHealthy(device), seenIDs.insert(device.uniqueID).inserted else { return }
            candidates.append(device)
        }

        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video,
            position: .unspecified
        )
        let healthy = discovery.devices.filter { isDeviceHealthy($0) }
        let defaultBuiltIn = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        let builtIn = ([defaultBuiltIn].compactMap { $0 } + healthy.filter { $0.deviceType == .builtInWideAngleCamera })
        let wiredExternal = healthy.filter { $0.deviceType == .external && !isContinuityOrMobileCamera($0) }
        let continuity = healthy.filter { isContinuityOrMobileCamera($0) }

        let prioritized = isBuiltIn
            ? (builtIn + wiredExternal + continuity)
            : (wiredExternal + builtIn + continuity)

        for device in prioritized {
            appendIfHealthy(device)
        }
        appendIfHealthy(AVCaptureDevice.default(for: .video))

        return candidates
    }

    @MainActor
    static func invalidateTargetScreenCache() {}
}
