@preconcurrency import AppKit
import ApplicationServices
@preconcurrency import CoreFoundation
import Defaults
import Foundation
import IOKit.hid

// MARK: - Multitouch Trackpad 4/5-Finger Pinch Detector

/// Reads raw multi-touch trackpad frames via Apple's MultitouchSupport framework
/// so 4/5-finger inward pinch opens Launchpad Home immediately (~40ms) before
/// WindowServer's SpotlightApps system gesture animates onto the screen.
private final class LaunchpadMultitouchPinchDetector: @unchecked Sendable {
    private struct MTPoint {
        var x: Float
        var y: Float
    }

    private struct MTVector {
        var position: MTPoint
        var velocity: MTPoint
    }

    private struct MTTouch {
        var frame: Int32
        var timestamp: Double
        var pathIndex: Int32
        var state: UInt32
        var fingerID: Int32
        var handID: Int32
        var normalizedVector: MTVector
        var zTotal: Float
        var field9: Int32
        var angle: Float
        var majorAxis: Float
        var minorAxis: Float
        var absoluteVector: MTVector
        var field14: Int32
        var field15: Int32
        var zDensity: Float
    }

    private typealias MTDeviceCreateListFn = @convention(c) () -> Unmanaged<CFArray>?
    private typealias MTContactFrameCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, Int32, Double, Int32) -> Int32
    private typealias MTRegisterCallbackFn = @convention(c) (UnsafeMutableRawPointer?, MTContactFrameCallback?) -> Void
    private typealias MTUnregisterCallbackFn = @convention(c) (UnsafeMutableRawPointer?, MTContactFrameCallback?) -> Void
    private typealias MTDeviceStartFn = @convention(c) (UnsafeMutableRawPointer?, Int32) -> Int32
    private typealias MTDeviceStopFn = @convention(c) (UnsafeMutableRawPointer?) -> Int32
    private typealias MTDeviceReleaseFn = @convention(c) (UnsafeMutableRawPointer?) -> Void
    private typealias MTDeviceGetSurfaceDimsFn = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<Int32>?, UnsafeMutablePointer<Int32>?) -> Int32

    private struct TouchSample {
        let id: Int32
        let point: MTPoint
    }

    private struct DeviceSession {
        enum Phase {
            case idle
            case arming(ids: Set<Int32>, startedAt: TimeInterval, scales: [Float], centroids: [MTPoint])
            case tracking(
                ids: Set<Int32>,
                baselineScale: Float,
                baselineCentroid: MTPoint,
                baselineRadii: [Int32: Float],
                filteredScale: Float,
                pinchInMatches: Int,
                spreadOutMatches: Int
            )
            case triggered
        }

        var phase: Phase = .idle
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var activeInstance: LaunchpadMultitouchPinchDetector?

    private var frameworkHandle: UnsafeMutableRawPointer?
    private var devices: [UnsafeMutableRawPointer] = []
    private var unregisterCallbackFn: MTUnregisterCallbackFn?
    private var stopDeviceFn: MTDeviceStopFn?
    private var releaseDeviceFn: MTDeviceReleaseFn?

    // Gesture tracking state per device (guarded by lock)
    private var deviceSessions: [UInt: DeviceSession] = [:]
    private var lastTriggerTimestamp: TimeInterval = 0

    private let onPinchIn: @Sendable () -> Void
    private let onSpreadOut: @Sendable () -> Void

    init(
        onPinchIn: @escaping @Sendable () -> Void,
        onSpreadOut: @escaping @Sendable () -> Void
    ) {
        self.onPinchIn = onPinchIn
        self.onSpreadOut = onSpreadOut
    }

    deinit {
        stop()
    }

    func start() {
        Self.lock.lock()
        guard devices.isEmpty else {
            Self.lock.unlock()
            return
        }
        Self.activeInstance = self
        Self.lock.unlock()

        guard let handle = frameworkHandle ?? dlopen(
            "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport",
            RTLD_LAZY
        ) else {
            return
        }
        frameworkHandle = handle

        guard let createSym = dlsym(handle, "MTDeviceCreateList"),
              let regSym = dlsym(handle, "MTRegisterContactFrameCallback"),
              let unregSym = dlsym(handle, "MTUnregisterContactFrameCallback"),
              let startSym = dlsym(handle, "MTDeviceStart"),
              let stopSym = dlsym(handle, "MTDeviceStop") else {
            return
        }

        let createList = unsafeBitCast(createSym, to: MTDeviceCreateListFn.self)
        let registerFn = unsafeBitCast(regSym, to: MTRegisterCallbackFn.self)
        let unregisterFn = unsafeBitCast(unregSym, to: MTUnregisterCallbackFn.self)
        let startFn = unsafeBitCast(startSym, to: MTDeviceStartFn.self)
        let stopFn = unsafeBitCast(stopSym, to: MTDeviceStopFn.self)
        let releaseFn = dlsym(handle, "MTDeviceRelease").map { unsafeBitCast($0, to: MTDeviceReleaseFn.self) }
        let dimsFn = dlsym(handle, "MTDeviceGetSensorSurfaceDimensions").map {
            unsafeBitCast($0, to: MTDeviceGetSurfaceDimsFn.self)
        }

        self.unregisterCallbackFn = unregisterFn
        self.stopDeviceFn = stopFn
        self.releaseDeviceFn = releaseFn

        guard let cfArray = createList()?.takeRetainedValue() else { return }
        let count = CFArrayGetCount(cfArray)
        var startedDevices: [UnsafeMutableRawPointer] = []

        for idx in 0..<count {
            guard let ptr = CFArrayGetValueAtIndex(cfArray, idx) else { continue }
            let dev = UnsafeMutableRawPointer(mutating: ptr)

            // Skip Touch Bar sensors (extremely wide and shallow surface dimensions)
            if let dimsFn {
                var width: Int32 = 0
                var height: Int32 = 0
                if dimsFn(dev, &width, &height) == 0, width > 1000 && height > 0 && height < 100 {
                    continue
                }
            }

            // Retain MTDeviceRef before cfArray is released (matches OpenMTManager pattern)
            _ = Unmanaged<AnyObject>.fromOpaque(dev).retain()
            registerFn(dev, Self.contactCallback)
            if startFn(dev, 0) == 0 {
                startedDevices.append(dev)
            } else {
                unregisterFn(dev, Self.contactCallback)
                releaseFn?(dev)
            }
        }

        Self.lock.lock()
        self.devices = startedDevices
        Self.lock.unlock()
    }

    func stop() {
        Self.lock.lock()
        let currentDevices = devices
        devices.removeAll()
        deviceSessions.removeAll()
        if Self.activeInstance === self {
            Self.activeInstance = nil
        }
        Self.lock.unlock()

        for dev in currentDevices {
            unregisterCallbackFn?(dev, Self.contactCallback)
            _ = stopDeviceFn?(dev)
            releaseDeviceFn?(dev)
        }
    }

    func restart() {
        stop()
        start()
    }

    private static let contactCallback: MTContactFrameCallback = { devicePtr, touchesPtr, numFingers, timestamp, _ in
        LaunchpadMultitouchPinchDetector.lock.lock()
        guard let instance = LaunchpadMultitouchPinchDetector.activeInstance else {
            LaunchpadMultitouchPinchDetector.lock.unlock()
            return 0
        }
        let deviceKey = UInt(bitPattern: devicePtr)
        instance.processFrame(deviceKey: deviceKey, touchesPtr: touchesPtr, numFingers: Int(numFingers), timestamp: timestamp)
        LaunchpadMultitouchPinchDetector.lock.unlock()
        return 0
    }

    private func processFrame(deviceKey: UInt, touchesPtr: UnsafeRawPointer?, numFingers: Int, timestamp: Double) {
        var session = deviceSessions[deviceKey] ?? DeviceSession()
        defer { deviceSessions[deviceKey] = session }

        guard let touchesPtr, numFingers > 0, numFingers <= 12 else {
            session.phase = .idle
            return
        }

        let touches = touchesPtr.bindMemory(to: MTTouch.self, capacity: numFingers)
        var samples: [TouchSample] = []
        samples.reserveCapacity(numFingers)

        for i in 0..<numFingers {
            let touch = touches[i]
            // MTTouchStateMakeTouch = 3, MTTouchStateTouching = 4
            guard touch.state == 3 || touch.state == 4 else { continue }
            let p = touch.normalizedVector.position
            guard p.x.isFinite, p.y.isFinite, p.x >= -0.25, p.x <= 1.25, p.y >= -0.25, p.y <= 1.25 else { continue }
            samples.append(TouchSample(id: touch.fingerID, point: p))
        }

        guard samples.count == 4 || samples.count == 5 else {
            session.phase = .idle
            return
        }

        let now = ProcessInfo.processInfo.systemUptime
        let currentIDs = Set(samples.map(\.id))
        let scale = medianPairwiseDistance(samples)
        let cent = centroid(samples)

        switch session.phase {
        case .idle, .triggered:
            guard case .idle = session.phase else { return }
            session.phase = .arming(ids: currentIDs, startedAt: now, scales: [scale], centroids: [cent])

        case .arming(let ids, let startedAt, var scales, var centroids):
            guard currentIDs == ids else {
                session.phase = .arming(ids: currentIDs, startedAt: now, scales: [scale], centroids: [cent])
                return
            }
            scales.append(scale)
            centroids.append(cent)

            // Wait ~25ms / >=2 frames to let all fingers settle cleanly before capturing baseline
            guard now - startedAt >= 0.025 && scales.count >= 2 else {
                session.phase = .arming(ids: ids, startedAt: startedAt, scales: scales, centroids: centroids)
                return
            }

            let baselineWindow = min(scales.count, 3)
            let baselineScale = medianFloat(Array(scales.prefix(baselineWindow)))
            guard baselineScale >= 0.08 else {
                session.phase = .idle
                return
            }
            let baseCent = averagePoint(Array(centroids.prefix(baselineWindow)))
            let baseRadii = radii(samples, around: baseCent)
            session.phase = .tracking(
                ids: ids,
                baselineScale: baselineScale,
                baselineCentroid: baseCent,
                baselineRadii: baseRadii,
                filteredScale: baselineScale,
                pinchInMatches: 0,
                spreadOutMatches: 0
            )

        case .tracking(let ids, let baseScale, let baseCent, let baseRadii, let filteredScale, let pinchInMatches, let spreadOutMatches):
            guard currentIDs == ids else {
                session.phase = .arming(ids: currentIDs, startedAt: now, scales: [scale], centroids: [cent])
                return
            }

            guard now - lastTriggerTimestamp > 0.50 else { return }

            let smoothed = filteredScale * 0.65 + scale * 0.35
            let ratio = smoothed / max(0.001, baseScale)
            let drift = hypotf(cent.x - baseCent.x, cent.y - baseCent.y)
            let maxDrift = max(baseScale * 0.55, 0.04)

            guard drift <= maxDrift else {
                // Parallel 4/5-finger swipe (Mission Control / Desktop Space switching)
                session.phase = .tracking(
                    ids: ids,
                    baselineScale: baseScale,
                    baselineCentroid: baseCent,
                    baselineRadii: baseRadii,
                    filteredScale: smoothed,
                    pinchInMatches: 0,
                    spreadOutMatches: 0
                )
                return
            }

            let curRadii = radii(samples, around: cent)
            var inwardCount = 0
            var outwardCount = 0
            for (id, r) in curRadii {
                guard let br = baseRadii[id], br > 0.001 else { continue }
                let rr = r / br
                if rr <= 0.96 { inwardCount += 1 }
                if rr >= 1.05 { outwardCount += 1 }
            }

            let minParticipating = max(3, samples.count - 1)
            let isPinchIn = ratio <= 0.84 && inwardCount >= minParticipating
            let isSpreadOut = ratio >= 1.18 && outwardCount >= minParticipating

            let nextIn = isPinchIn ? (pinchInMatches + 1) : 0
            let nextOut = isSpreadOut ? (spreadOutMatches + 1) : 0

            if nextIn >= 2 {
                session.phase = .triggered
                lastTriggerTimestamp = now
                onPinchIn()
                return
            }
            if nextOut >= 2 {
                session.phase = .triggered
                lastTriggerTimestamp = now
                onSpreadOut()
                return
            }

            session.phase = .tracking(
                ids: ids,
                baselineScale: baseScale,
                baselineCentroid: baseCent,
                baselineRadii: baseRadii,
                filteredScale: smoothed,
                pinchInMatches: nextIn,
                spreadOutMatches: nextOut
            )
        }
    }

    private func medianPairwiseDistance(_ samples: [TouchSample]) -> Float {
        guard samples.count > 1 else { return 0 }
        var distances: [Float] = []
        distances.reserveCapacity((samples.count * (samples.count - 1)) / 2)
        for i in 0..<samples.count {
            for j in (i + 1)..<samples.count {
                let dx = samples[i].point.x - samples[j].point.x
                let dy = samples[i].point.y - samples[j].point.y
                distances.append(hypotf(dx, dy))
            }
        }
        return medianFloat(distances)
    }

    private func centroid(_ samples: [TouchSample]) -> MTPoint {
        var sx: Float = 0
        var sy: Float = 0
        for s in samples {
            sx += s.point.x
            sy += s.point.y
        }
        let n = Float(max(samples.count, 1))
        return MTPoint(x: sx / n, y: sy / n)
    }

    private func radii(_ samples: [TouchSample], around c: MTPoint) -> [Int32: Float] {
        var result: [Int32: Float] = [:]
        result.reserveCapacity(samples.count)
        for s in samples {
            result[s.id] = hypotf(s.point.x - c.x, s.point.y - c.y)
        }
        return result
    }

    private func averagePoint(_ points: [MTPoint]) -> MTPoint {
        guard !points.isEmpty else { return MTPoint(x: 0, y: 0) }
        var sx: Float = 0
        var sy: Float = 0
        for p in points {
            sx += p.x
            sy += p.y
        }
        let n = Float(points.count)
        return MTPoint(x: sx / n, y: sy / n)
    }

    private func medianFloat(_ values: [Float]) -> Float {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) * 0.5
        }
        return sorted[mid]
    }
}

// MARK: - System Launchpad Event Tap, AX Observer & Fallback Coordinator

/// Intercepts Dock Apps clicks, Launchpad hardware keys, 4/5-finger trackpad pinches,
/// and macOS 27 Spotlight Apps windows so Apple's native UI is swallowed immediately
/// and NotchPulse Launchpad Home opens instead.
@MainActor
final class LaunchpadSystemInterceptor {
    static let shared = LaunchpadSystemInterceptor()

    nonisolated private static let kVKLaunchpadKeyCode: Int64 = 131
    nonisolated private static let kVKLaunchpadAlternateKeyCode: Int64 = 160
    nonisolated private static let nxSystemDefinedEventTypeRaw: UInt32 = 14 // NX_SYSDEFINED
    nonisolated private static let nxKeyTypeLaunchPanel = 13 // NX_KEYTYPE_LAUNCH_PANEL

    // System preference backup keys for clean restore on disable / quit
    private static let savedOverrideActiveKey = "LaunchpadSystemGestureOverrideActive"
    private static let savedTrackpadAppBrowseHadValueKey = "LaunchpadSavedTrackpadAppBrowseHadValue"
    private static let savedTrackpadAppBrowseValueKey = "LaunchpadSavedTrackpadAppBrowseValue"
    private static let savedDockLaunchpadHadValueKey = "LaunchpadSavedDockLaunchpadHadValue"
    private static let savedDockLaunchpadValueKey = "LaunchpadSavedDockLaunchpadValue"

    private static let spotlightDomain = "com.apple.spotlight" as CFString
    private static let trackpadAppBrowseKey = "trackpadAppBrowseEnabled" as CFString
    private static let dockDomain = "com.apple.dock" as CFString
    private static let dockLaunchpadKey = "showLaunchpadGestureEnabled" as CFString

    nonisolated private static let spotlightInternalBundle = Bundle(
        path: "/System/Library/PrivateFrameworks/SpotlightUIInternal.framework"
    )

    nonisolated private static var localizedSpotlightSearchPlaceholders: Set<String> {
        var set: Set<String> = [
            "Spotlight Search",
            "Tìm kiếm Spotlight",
            "Search or Ask",
            "Tìm kiếm hoặc hỏi"
        ]
        if let b = spotlightInternalBundle {
            let s1 = b.localizedString(forKey: "SPOTLIGHT_SEARCH", value: "", table: nil)
            if !s1.isEmpty { set.insert(s1) }
            let s2 = b.localizedString(forKey: "SIRI_SEARCH_PLACEHOLDER", value: "", table: nil)
            if !s2.isEmpty { set.insert(s2) }
        }
        return set
    }

    nonisolated private static var localizedAppsPlaceholders: Set<String> {
        var set: Set<String> = [
            "Applications",
            "Ứng dụng",
            "Apps",
            FileManager.default.displayName(atPath: "/Applications")
        ]
        if let b = spotlightInternalBundle {
            let a1 = b.localizedString(forKey: "Apps", value: "", table: nil)
            if !a1.isEmpty { set.insert(a1) }
        }
        return set
    }

    private var isConfigured = false
    private var eventTap: CFMachPort?
    private var eventTapRunLoopSource: CFRunLoopSource?
    private final class TapSharedState: @unchecked Sendable {
        let lock = NSLock()
        var isEnabled = false
        var replaceSystemGesture = false
        var symbolicHotKey: (keyCode: Int64, modifiers: CGEventFlags)?
        var swallowNextKeyUp = false
        var eventTap: CFMachPort?
    }
    private let tapState = TapSharedState()
    private var symbolicLaunchpadHotKey: (keyCode: Int64, modifiers: CGEventFlags)?
    private var hidManager: IOHIDManager?

    private var multitouchDetector: LaunchpadMultitouchPinchDetector?
    private var axObservers: [pid_t: AXObserver] = [:]
    private var workspaceLaunchObserver: Any?
    private var workspaceActivateObserver: Any?
    private var workspaceWakeObserver: Any?
    private var deferredAXCheckTask: Task<Void, Never>?
    private var fallbackMonitorSource: DispatchSourceTimer?
    private let fallbackMonitorQueue = DispatchQueue(label: "com.notchpulse.launchpad.windowwatcher", qos: .utility)
    private var wasSystemAppsWindowOnScreen = false
    private var nativeDismissGeneration: Int = 0

    private var lastTriggerAt: Date = .distantPast
    private var suppressNativeDismissUntil: Date = .distantPast

    private init() {}

    func configure() {
        guard Defaults[.enableLaunchpad] else {
            teardown()
            return
        }

        if !isConfigured {
            isConfigured = true
            installDarwinAndWorkspaceObservers()
        }

        refreshSymbolicLaunchpadHotKey()
        syncTapConfiguration()
        syncSystemTrackpadGestureSuppression()
        installMultitouchDetectorIfNeeded()
        installHIDConsumerObserverIfAuthorized()
        installEventTapIfNeeded()
        attachSystemAXObservers()
        updateFallbackMonitorState()
    }

    private func syncTapConfiguration() {
        let enabled = Defaults[.enableLaunchpad]
        let replaceGesture = Defaults[.launchpadReplaceSystemGesture]
        let hotKey = symbolicLaunchpadHotKey
        tapState.lock.lock()
        tapState.isEnabled = enabled
        tapState.replaceSystemGesture = replaceGesture
        tapState.symbolicHotKey = hotKey
        tapState.lock.unlock()
    }

    func noteInterceptedSystemTrigger() {
        let now = Date()
        lastTriggerAt = now
        suppressNativeDismissUntil = now.addingTimeInterval(0.95)
    }

    func teardown() {
        tapState.lock.lock()
        tapState.isEnabled = false
        tapState.swallowNextKeyUp = false
        tapState.lock.unlock()

        deferredAXCheckTask?.cancel()
        deferredAXCheckTask = nil

        fallbackMonitorSource?.cancel()
        fallbackMonitorSource = nil
        wasSystemAppsWindowOnScreen = false

        multitouchDetector?.stop()
        multitouchDetector = nil

        removeHIDConsumerObserver()
        removeEventTap()

        for (_, observer) in axObservers {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        axObservers.removeAll()

        restoreSystemTrackpadGestureIfNeeded()
    }

    // MARK: - OS System Pinch Suppression (Reversible)

    /// Disables macOS's native 4/5-finger Spotlight Applications / Launchpad pinch gesture
    /// (`com.apple.spotlight` -> `trackpadAppBrowseEnabled` on macOS 26+) so WindowServer
    /// unregisters `SpotlightAppsSystemGesture` while `MultitouchSupport` still reads hardware touches.
    private func syncSystemTrackpadGestureSuppression() {
        guard Defaults[.enableLaunchpad], Defaults[.launchpadReplaceSystemGesture] else {
            restoreSystemTrackpadGestureIfNeeded()
            return
        }

        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: Self.savedOverrideActiveKey) {
            let existingSpotlightVal = CFPreferencesCopyValue(
                Self.trackpadAppBrowseKey,
                Self.spotlightDomain,
                kCFPreferencesCurrentUser,
                kCFPreferencesAnyHost
            )
            defaults.set(existingSpotlightVal != nil, forKey: Self.savedTrackpadAppBrowseHadValueKey)
            if let boolNum = existingSpotlightVal as? Bool {
                defaults.set(boolNum, forKey: Self.savedTrackpadAppBrowseValueKey)
            } else if let num = existingSpotlightVal as? NSNumber {
                defaults.set(num.boolValue, forKey: Self.savedTrackpadAppBrowseValueKey)
            }

            let existingDockVal = CFPreferencesCopyValue(
                Self.dockLaunchpadKey,
                Self.dockDomain,
                kCFPreferencesCurrentUser,
                kCFPreferencesAnyHost
            )
            defaults.set(existingDockVal != nil, forKey: Self.savedDockLaunchpadHadValueKey)
            if let boolNum = existingDockVal as? Bool {
                defaults.set(boolNum, forKey: Self.savedDockLaunchpadValueKey)
            } else if let num = existingDockVal as? NSNumber {
                defaults.set(num.boolValue, forKey: Self.savedDockLaunchpadValueKey)
            }

            defaults.set(true, forKey: Self.savedOverrideActiveKey)
        }

        CFPreferencesSetValue(
            Self.trackpadAppBrowseKey,
            kCFBooleanFalse,
            Self.spotlightDomain,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )
        CFPreferencesSynchronize(Self.spotlightDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)

        CFPreferencesSetValue(
            Self.dockLaunchpadKey,
            kCFBooleanFalse,
            Self.dockDomain,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )
        CFPreferencesSynchronize(Self.dockDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        notifyDockAndTrackpadPreferencesChanged()
    }

    /// Restores the user's original Trackpad Launchpad / Applications pinch preference
    /// when overriding is turned off, Launchpad Home is disabled, or NotchPulse quits.
    func restoreSystemTrackpadGestureIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: Self.savedOverrideActiveKey) else { return }

        let hadSpotlightValue = defaults.bool(forKey: Self.savedTrackpadAppBrowseHadValueKey)
        if hadSpotlightValue {
            let prev = defaults.bool(forKey: Self.savedTrackpadAppBrowseValueKey)
            CFPreferencesSetValue(
                Self.trackpadAppBrowseKey,
                prev ? kCFBooleanTrue : kCFBooleanFalse,
                Self.spotlightDomain,
                kCFPreferencesCurrentUser,
                kCFPreferencesAnyHost
            )
        } else {
            CFPreferencesSetValue(
                Self.trackpadAppBrowseKey,
                nil,
                Self.spotlightDomain,
                kCFPreferencesCurrentUser,
                kCFPreferencesAnyHost
            )
        }
        CFPreferencesSynchronize(Self.spotlightDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)

        let hadDockValue = defaults.bool(forKey: Self.savedDockLaunchpadHadValueKey)
        if hadDockValue {
            let prevDock = defaults.bool(forKey: Self.savedDockLaunchpadValueKey)
            CFPreferencesSetValue(
                Self.dockLaunchpadKey,
                prevDock ? kCFBooleanTrue : kCFBooleanFalse,
                Self.dockDomain,
                kCFPreferencesCurrentUser,
                kCFPreferencesAnyHost
            )
        } else {
            CFPreferencesSetValue(
                Self.dockLaunchpadKey,
                nil,
                Self.dockDomain,
                kCFPreferencesCurrentUser,
                kCFPreferencesAnyHost
            )
        }
        CFPreferencesSynchronize(Self.dockDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        notifyDockAndTrackpadPreferencesChanged()

        defaults.removeObject(forKey: Self.savedOverrideActiveKey)
        defaults.removeObject(forKey: Self.savedTrackpadAppBrowseHadValueKey)
        defaults.removeObject(forKey: Self.savedTrackpadAppBrowseValueKey)
        defaults.removeObject(forKey: Self.savedDockLaunchpadHadValueKey)
        defaults.removeObject(forKey: Self.savedDockLaunchpadValueKey)
    }

    private func notifyDockAndTrackpadPreferencesChanged() {
        let dockChanged = CFNotificationName("com.apple.dock.prefchanged" as CFString)
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDistributedCenter(),
            dockChanged,
            nil,
            nil,
            true
        )
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            dockChanged,
            nil,
            nil,
            true
        )
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDistributedCenter(),
            CFNotificationName("AppleTrackpadPreferencesChanged" as CFString),
            nil,
            nil,
            true
        )
    }

    /// Reads macOS System Settings -> Keyboard Shortcuts -> Launchpad (`160`) so custom
    /// or system-configured Launchpad keyboard shortcuts are intercepted alongside F4 / HID Launchpad.
    private func refreshSymbolicLaunchpadHotKey() {
        defer { syncTapConfiguration() }
        guard let hotKeys = CFPreferencesCopyValue(
            "AppleSymbolicHotKeys" as CFString,
            "com.apple.symbolichotkeys" as CFString,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        ) as? [String: Any],
              let entry = hotKeys["160"] as? [String: Any] else {
            symbolicLaunchpadHotKey = nil
            return
        }

        let enabled: Bool
        if let b = entry["enabled"] as? Bool {
            enabled = b
        } else if let n = entry["enabled"] as? NSNumber {
            enabled = n.boolValue
        } else {
            enabled = false
        }
        guard enabled,
              let value = entry["value"] as? [String: Any],
              let params = value["parameters"] as? [NSNumber],
              params.count >= 3 else {
            symbolicLaunchpadHotKey = nil
            return
        }

        let virtualKeyCode = params[1].int64Value
        let rawModifiers = params[2].uint64Value
        guard virtualKeyCode >= 0 && virtualKeyCode != 65535 else {
            symbolicLaunchpadHotKey = nil
            return
        }

        var flags: CGEventFlags = []
        if (rawModifiers & UInt64(NSEvent.ModifierFlags.command.rawValue)) != 0 { flags.insert(.maskCommand) }
        if (rawModifiers & UInt64(NSEvent.ModifierFlags.control.rawValue)) != 0 { flags.insert(.maskControl) }
        if (rawModifiers & UInt64(NSEvent.ModifierFlags.option.rawValue)) != 0 { flags.insert(.maskAlternate) }
        if (rawModifiers & UInt64(NSEvent.ModifierFlags.shift.rawValue)) != 0 { flags.insert(.maskShift) }
        symbolicLaunchpadHotKey = (virtualKeyCode, flags)
    }

    // MARK: - Trackpad Multitouch Detector

    private func installMultitouchDetectorIfNeeded() {
        guard multitouchDetector == nil else { return }
        let detector = LaunchpadMultitouchPinchDetector(
            onPinchIn: {
                Task { @MainActor in
                    LaunchpadSystemInterceptor.shared.handleMultitouchPinchIn()
                }
            },
            onSpreadOut: {
                Task { @MainActor in
                    LaunchpadSystemInterceptor.shared.handleMultitouchSpreadOut()
                }
            }
        )
        detector.start()
        multitouchDetector = detector
    }

    private func handleMultitouchPinchIn() {
        guard Defaults[.enableLaunchpad] else { return }
        let controller = LaunchpadWindowController.shared
        guard !controller.isPresented else { return }
        let now = Date()
        guard now.timeIntervalSince(lastTriggerAt) >= 0.55 else { return }
        lastTriggerAt = now
        suppressNativeDismissUntil = now.addingTimeInterval(0.95)
        controller.show()
    }

    private func handleMultitouchSpreadOut() {
        guard Defaults[.enableLaunchpad] else { return }
        let controller = LaunchpadWindowController.shared
        guard controller.isPresented else { return }
        let now = Date()
        guard now.timeIntervalSince(lastTriggerAt) >= 0.45 else { return }
        lastTriggerAt = now
        controller.dismiss(restorePreviousApp: true)
    }

    // MARK: - External Keyboard HID Consumer Listener (No Extra Prompt)

    private func installHIDConsumerObserverIfAuthorized() {
        guard hidManager == nil else { return }
        guard IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted else { return }

        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matches: [[String: Any]] = [
            [
                kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
                kIOHIDDeviceUsageKey as String: kHIDUsage_GD_Keyboard
            ],
            [
                kIOHIDDeviceUsagePageKey as String: kHIDPage_Consumer,
                kIOHIDDeviceUsageKey as String: kHIDUsage_Csmr_ConsumerControl
            ]
        ]
        IOHIDManagerSetDeviceMatchingMultiple(mgr, matches as CFArray)

        let refcon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerRegisterInputValueCallback(mgr, { context, _, _, value in
            guard let context else { return }
            let intVal = IOHIDValueGetIntegerValue(value)
            guard intVal != 0 else { return }

            let element = IOHIDValueGetElement(value)
            let usagePage = IOHIDElementGetUsagePage(element)
            let usage = IOHIDElementGetUsage(element)

            // Catch external/USB/Bluetooth keyboards sending HID Consumer
            // `AC Desktop Show All Applications` (0x2A2) directly at hardware level.
            let isShowAllAppsConsumer = (usagePage == UInt32(kHIDPage_Consumer)
                && usage == UInt32(kHIDUsage_Csmr_ACDesktopShowAllApplications))
            guard isShowAllAppsConsumer else { return }

            let interceptor = Unmanaged<LaunchpadSystemInterceptor>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in
                interceptor.handleExternalLaunchpadHIDKey()
            }
        }, refcon)

        IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        guard IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            IOHIDManagerUnscheduleFromRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            return
        }
        hidManager = mgr
    }

    private func removeHIDConsumerObserver() {
        guard let mgr = hidManager else { return }
        IOHIDManagerUnscheduleFromRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        hidManager = nil
    }

    private func handleExternalLaunchpadHIDKey() {
        guard Defaults[.enableLaunchpad] else { return }
        let now = Date()
        guard now.timeIntervalSince(lastTriggerAt) >= 0.45 else { return }
        lastTriggerAt = now
        suppressNativeDismissUntil = now.addingTimeInterval(0.95)
        LaunchpadWindowController.shared.toggle()
        if LaunchpadWindowController.shared.isPresented {
            dismissNativeSpotlightAppsWindow(keepLaunchpadOpen: true)
        }
    }

    // MARK: - CGEventTap (Dock Click + Launchpad Key Swallower)

    /// Dedicated lightweight run loop serving Launchpad key taps off MainThread
    /// (mirrors vorssaint-utils PointerTapRunLoop: zero UI, zero timers, zero Accessibility calls).
    private enum LaunchpadTapRunLoop {
        private final class RunLoopHolder: @unchecked Sendable {
            var loop: CFRunLoop?
        }

        static let runLoop: CFRunLoop = {
            let holder = RunLoopHolder()
            let ready = DispatchSemaphore(value: 0)
            let thread = Thread {
                holder.loop = CFRunLoopGetCurrent()
                RunLoop.current.add(NSMachPort(), forMode: .common)
                ready.signal()
                while true {
                    CFRunLoopRunInMode(.defaultMode, .greatestFiniteMagnitude, false)
                }
            }
            thread.name = "NotchPulse Launchpad Key Tap"
            thread.qualityOfService = .userInteractive
            thread.start()
            ready.wait()
            return holder.loop!
        }()

        static func add(_ source: CFRunLoopSource) {
            CFRunLoopAddSource(runLoop, source, .commonModes)
            CFRunLoopWakeUp(runLoop)
        }

        static func remove(_ source: CFRunLoopSource, invalidating port: CFMachPort?) {
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
                if let port {
                    CFMachPortInvalidate(port)
                }
            }
            CFRunLoopWakeUp(runLoop)
        }
    }

    private func installEventTapIfNeeded() {
        guard eventTap == nil, AXIsProcessTrusted() else { return }

        // Only intercept Launchpad keyboard/media keys off-main-thread; NEVER tap leftMouseDown/Up globally
        // or run synchronous AXUIElementCopyElementAtPosition inside a CGEventTap callback (prevents WindowServer deadlocks).
        let mask =
            (CGEventMask(1) << CGEventType.keyDown.rawValue) |
            (CGEventMask(1) << CGEventType.keyUp.rawValue) |
            (CGEventMask(1) << Self.nxSystemDefinedEventTypeRaw)

        let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, cgEvent, userInfo in
                guard let userInfo else { return Unmanaged.passRetained(cgEvent) }
                let interceptor = Unmanaged<LaunchpadSystemInterceptor>.fromOpaque(userInfo).takeUnretainedValue()
                return interceptor.handleCGEvent(type: type, cgEvent: cgEvent)
            },
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) ?? CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, cgEvent, userInfo in
                guard let userInfo else { return Unmanaged.passRetained(cgEvent) }
                let interceptor = Unmanaged<LaunchpadSystemInterceptor>.fromOpaque(userInfo).takeUnretainedValue()
                return interceptor.handleCGEvent(type: type, cgEvent: cgEvent)
            },
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )

        guard let tap else { return }
        eventTap = tap
        tapState.lock.lock()
        tapState.eventTap = tap
        tapState.lock.unlock()

        if let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) {
            eventTapRunLoopSource = source
            LaunchpadTapRunLoop.add(source)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func removeEventTap() {
        let tap = eventTap
        let source = eventTapRunLoopSource
        eventTap = nil
        eventTapRunLoopSource = nil

        tapState.lock.lock()
        tapState.eventTap = nil
        tapState.swallowNextKeyUp = false
        tapState.lock.unlock()

        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source {
            LaunchpadTapRunLoop.remove(source, invalidating: tap)
        } else if let tap {
            CFMachPortInvalidate(tap)
        }
    }

    nonisolated private func handleCGEvent(type: CGEventType, cgEvent: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            tapState.lock.lock()
            let tap = tapState.eventTap
            tapState.lock.unlock()
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passRetained(cgEvent)
        }

        tapState.lock.lock()
        let enabled = tapState.isEnabled
        let replaceGesture = tapState.replaceSystemGesture
        let hotKey = tapState.symbolicHotKey
        tapState.lock.unlock()

        guard enabled else {
            return Unmanaged.passRetained(cgEvent)
        }

        if type.rawValue == Self.nxSystemDefinedEventTypeRaw,
           let nsEvent = NSEvent(cgEvent: cgEvent),
           nsEvent.type == .systemDefined,
           nsEvent.subtype.rawValue == 8 {
            let keyCode = (nsEvent.data1 & 0xFFFF_0000) >> 16
            let stateByte = (nsEvent.data1 & 0xFF00) >> 8
            if keyCode == Self.nxKeyTypeLaunchPanel {
                if stateByte == 0xA {
                    DispatchQueue.main.async {
                        LaunchpadSystemInterceptor.shared.triggerLaunchpadFromTap(dismissWindowSeconds: 0.60)
                    }
                }
                return nil
            }
            return Unmanaged.passRetained(cgEvent)
        }

        switch type {
        case .keyUp:
            tapState.lock.lock()
            let shouldSwallow = tapState.swallowNextKeyUp
            if shouldSwallow { tapState.swallowNextKeyUp = false }
            tapState.lock.unlock()
            return shouldSwallow ? nil : Unmanaged.passRetained(cgEvent)

        case .keyDown:
            let keyCode = cgEvent.getIntegerValueField(.keyboardEventKeycode)
            let flags = cgEvent.flags
            let relevantFlags = flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift])
            let hasModifiers = !relevantFlags.isEmpty
            let matchesSymbolicHotKey: Bool = {
                guard replaceGesture, let hotKey else { return false }
                return keyCode == hotKey.keyCode && relevantFlags == hotKey.modifiers
            }()
            let matchesRawLaunchpadKey = (keyCode == Self.kVKLaunchpadKeyCode || keyCode == Self.kVKLaunchpadAlternateKeyCode) && !hasModifiers
            if matchesRawLaunchpadKey || matchesSymbolicHotKey {
                tapState.lock.lock()
                tapState.swallowNextKeyUp = true
                tapState.lock.unlock()
                DispatchQueue.main.async {
                    LaunchpadSystemInterceptor.shared.triggerLaunchpadFromTap(dismissWindowSeconds: 0.75)
                }
                return nil
            }
            return Unmanaged.passRetained(cgEvent)

        default:
            return Unmanaged.passRetained(cgEvent)
        }
    }

    private func triggerLaunchpadFromTap(dismissWindowSeconds: TimeInterval) {
        guard Defaults[.enableLaunchpad] else { return }
        let now = Date()
        lastTriggerAt = now
        suppressNativeDismissUntil = now.addingTimeInterval(dismissWindowSeconds)
        LaunchpadWindowController.shared.toggle()
    }

    // MARK: - Darwin, Workspace & AXObserver Interception

    private func installDarwinAndWorkspaceObservers() {
        if let center = CFNotificationCenterGetDarwinNotifyCenter() {
            let callback: CFNotificationCallback = { _, _, name, _, _ in
                guard let name, (name.rawValue as String) == "com.apple.launchpad.toggle" else { return }
                Task { @MainActor in
                    LaunchpadSystemInterceptor.shared.handleSystemAppsPopupDetected(fromNativeTrigger: true)
                }
            }
            CFNotificationCenterAddObserver(
                center,
                Unmanaged.passUnretained(self).toOpaque(),
                callback,
                "com.apple.launchpad.toggle" as CFString,
                nil,
                .deliverImmediately
            )
        }

        let wsCenter = NSWorkspace.shared.notificationCenter
        workspaceLaunchObserver = wsCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notif in
            let app = notif.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bundleId = app?.bundleIdentifier
            if bundleId == "com.apple.apps.launcher" {
                app?.hide()
                app?.terminate()
                Task { @MainActor in
                    self?.handleSystemAppsPopupDetected(fromNativeTrigger: true)
                }
            } else if bundleId == "com.apple.campo" || bundleId == "com.apple.Spotlight" {
                Task { @MainActor in
                    self?.attachSystemAXObservers()
                }
            }
        }

        workspaceActivateObserver = wsCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notif in
            let app = notif.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.bundleIdentifier == "com.apple.apps.launcher" else { return }
            app?.hide()
            app?.terminate()
            Task { @MainActor in
                self?.handleSystemAppsPopupDetected(fromNativeTrigger: true)
            }
        }

        workspaceWakeObserver = wsCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshSymbolicLaunchpadHotKey()
                self?.syncSystemTrackpadGestureSuppression()
                self?.multitouchDetector?.restart()
                self?.attachSystemAXObservers()
                self?.installEventTapIfNeeded()
            }
        }
    }

    private func attachSystemAXObservers() {
        guard AXIsProcessTrusted() else { return }

        let targetBundleIds = ["com.apple.campo", "com.apple.Spotlight"]
        let runningPIDs: [pid_t] = targetBundleIds.flatMap {
            NSRunningApplication.runningApplications(withBundleIdentifier: $0).map(\.processIdentifier)
        }
        for (pid, observer) in axObservers where !runningPIDs.contains(pid) {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
            axObservers.removeValue(forKey: pid)
        }

        for pid in runningPIDs where axObservers[pid] == nil {
            var newObserver: AXObserver?
            let err = AXObserverCreate(pid, { _, element, notification, _ in
                if LaunchpadSystemInterceptor.isSystemAppsWindowElement(element) {
                    Task { @MainActor in
                        LaunchpadSystemInterceptor.shared.handleSystemAppsPopupDetected(fromNativeTrigger: false)
                    }
                    return
                }
                let notifStr = notification as String
                if notifStr == kAXFocusedWindowChangedNotification
                    || notifStr == kAXMainWindowChangedNotification
                    || notifStr == kAXWindowCreatedNotification
                    || notifStr == kAXApplicationActivatedNotification {
                    var targetPid: pid_t = 0
                    AXUIElementGetPid(element, &targetPid)
                    if targetPid != 0 {
                        Task { @MainActor in
                            LaunchpadSystemInterceptor.shared.scheduleDeferredAppsWindowCheck(forPid: targetPid)
                        }
                    }
                }
            }, &newObserver)

            guard err == .success, let observer = newObserver else { continue }
            let axApp = AXUIElementCreateApplication(pid)
            AXObserverAddNotification(observer, axApp, kAXFocusedWindowChangedNotification as CFString, nil)
            AXObserverAddNotification(observer, axApp, kAXMainWindowChangedNotification as CFString, nil)
            AXObserverAddNotification(observer, axApp, kAXWindowCreatedNotification as CFString, nil)
            AXObserverAddNotification(observer, axApp, kAXApplicationActivatedNotification as CFString, nil)
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
            axObservers[pid] = observer
        }

        updateFallbackMonitorState()
    }

    private func scheduleDeferredAppsWindowCheck(forPid pid: pid_t) {
        deferredAXCheckTask?.cancel()
        deferredAXCheckTask = Task { @MainActor [weak self] in
            for delayMs in [12, 22, 35, 60] {
                try? await Task.sleep(for: .milliseconds(delayMs))
                guard !Task.isCancelled, let self, Defaults[.enableLaunchpad] else { return }
                let axApp = AXUIElementCreateApplication(pid)
                for win in Self.candidateAXWindows(for: axApp) {
                    if Self.isSystemAppsWindowElement(win) {
                        self.handleSystemAppsPopupDetected(fromNativeTrigger: false)
                        return
                    }
                }
            }
        }
    }

    private func updateFallbackMonitorState() {
        guard Defaults[.enableLaunchpad] else {
            fallbackMonitorSource?.cancel()
            fallbackMonitorSource = nil
            return
        }

        // Keep a lightweight off-main-thread CGWindow watcher so macOS 26/27 Siri AI's
        // pre-warmed FluidWindow on `.launchAppsBrowsing` is caught without blocking MainActor.
        guard fallbackMonitorSource == nil else { return }

        final class WatcherState: @unchecked Sendable {
            var pollCount: Int = 0
            var wasOnScreen: Bool = false
        }
        let state = WatcherState()
        let timer = DispatchSource.makeTimerSource(queue: fallbackMonitorQueue)
        timer.schedule(deadline: .now() + .milliseconds(100), repeating: .milliseconds(100), leeway: .milliseconds(25))
        timer.setEventHandler { [weak self] in
            state.pollCount += 1
            let shouldRefreshObservers = state.pollCount >= 25
            if shouldRefreshObservers {
                state.pollCount = 0
            }

            let isCurrentlyOnScreen = Self.isSpotlightAppsCGWindowVisible()
            let stateChanged = (isCurrentlyOnScreen != state.wasOnScreen)
            state.wasOnScreen = isCurrentlyOnScreen

            guard stateChanged || shouldRefreshObservers else { return }
            Task { @MainActor [weak self] in
                guard let self, Defaults[.enableLaunchpad] else { return }
                if shouldRefreshObservers {
                    self.refreshSymbolicLaunchpadHotKey()
                    self.installHIDConsumerObserverIfAuthorized()
                    if AXIsProcessTrusted() && (self.axObservers.isEmpty || self.eventTap == nil) {
                        self.installEventTapIfNeeded()
                        self.attachSystemAXObservers()
                    }
                }
                if stateChanged {
                    self.wasSystemAppsWindowOnScreen = isCurrentlyOnScreen
                    if isCurrentlyOnScreen {
                        self.handleSystemAppsPopupDetected(fromNativeTrigger: false)
                    }
                }
            }
        }
        fallbackMonitorSource = timer
        timer.resume()
    }

    nonisolated private static func safeAXUIElement(_ ref: AnyObject?) -> AXUIElement? {
        guard let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(ref, to: AXUIElement.self)
    }

    nonisolated private static func safeAXValue(_ ref: AnyObject?) -> AXValue? {
        guard let ref, CFGetTypeID(ref) == AXValueGetTypeID() else { return nil }
        return unsafeDowncast(ref, to: AXValue.self)
    }

    nonisolated private static func candidateAXWindows(for axApp: AXUIElement) -> [AXUIElement] {
        var result: [AXUIElement] = []
        var focusedRef: AnyObject?
        if AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &focusedRef) == .success,
           let focusedWin = safeAXUIElement(focusedRef) {
            result.append(focusedWin)
        }
        var windowsRef: AnyObject?
        if AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
           let windows = windowsRef as? [AXUIElement] {
            for win in windows.prefix(6) {
                if !result.contains(where: { CFEqual($0, win) }) {
                    result.append(win)
                }
            }
        }
        return result
    }

    nonisolated private static func isSpotlightAppsCGWindowVisible() -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }

        var matchingOwnerPIDs: Set<pid_t> = []
        var candidateFound = false

        for info in list {
            guard let owner = info[kCGWindowOwnerName as String] as? String,
                  owner == "Siri" || owner == "Siri AI" || owner == "Spotlight" else { continue }
            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            guard layer >= 20 else { continue }
            let alpha = info[kCGWindowAlpha as String] as? CGFloat ?? 1.0
            guard alpha > 0.01 else { continue }
            guard let bounds = info[kCGWindowBounds as String] as? [String: Any] else { continue }
            let width = bounds["Width"] as? CGFloat ?? 0
            let height = bounds["Height"] as? CGFloat ?? 0

            // Regular Cmd+Space Spotlight Search is compact until results/Apps open, whereas
            // macOS 26/27 Applications overlay opens as ~844x579 FluidWindow + screen-sized backdrop.
            if width >= 700 && height >= 480 {
                candidateFound = true
                if let pid = info[kCGWindowOwnerPID as String] as? pid_t {
                    matchingOwnerPIDs.insert(pid)
                }
            }
        }

        guard candidateFound else { return false }

        // If Accessibility is available, confirm it really is Applications (and not Cmd+Space Search).
        if AXIsProcessTrusted(), !matchingOwnerPIDs.isEmpty {
            var sawPlainCmdSpaceSearch = false
            for pid in matchingOwnerPIDs {
                let axApp = AXUIElementCreateApplication(pid)
                for win in candidateAXWindows(for: axApp) {
                    if isSystemAppsWindowElement(win) {
                        return true
                    }
                    if isCmdSpaceSearchWindowElement(win) {
                        sawPlainCmdSpaceSearch = true
                    }
                }
            }
            if sawPlainCmdSpaceSearch {
                return false
            }
        }

        return true
    }

    nonisolated private static func isCmdSpaceSearchWindowElement(_ element: AXUIElement) -> Bool {
        let searchPlaceholders = localizedSpotlightSearchPlaceholders
        var queue: [(AXUIElement, Int)] = [(element, 0)]
        while !queue.isEmpty {
            let (node, depth) = queue.removeFirst()
            var idRef: AnyObject?
            AXUIElementCopyAttributeValue(node, kAXIdentifierAttribute as CFString, &idRef)
            if (idRef as? String) == "SpotlightSearchField" {
                var phRef: AnyObject?
                AXUIElementCopyAttributeValue(node, kAXPlaceholderValueAttribute as CFString, &phRef)
                if let ph = phRef as? String, searchPlaceholders.contains(ph) {
                    return true
                }
            }
            if depth < 5 {
                var childrenRef: AnyObject?
                if AXUIElementCopyAttributeValue(node, kAXChildrenAttribute as CFString, &childrenRef) == .success,
                   let children = childrenRef as? [AXUIElement] {
                    for child in children.prefix(30) {
                        queue.append((child, depth + 1))
                    }
                }
            }
        }
        return false
    }

    nonisolated private static func isSystemAppsWindowElement(_ element: AXUIElement) -> Bool {
        var roleRef: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        let role = roleRef as? String ?? ""

        let windowElement: AXUIElement
        if role == (kAXWindowRole as String) {
            windowElement = element
        } else if role == (kAXTextFieldRole as String) {
            var idRef: AnyObject?
            AXUIElementCopyAttributeValue(element, kAXIdentifierAttribute as CFString, &idRef)
            if (idRef as? String) == "SpotlightSearchField" {
                var phRef: AnyObject?
                AXUIElementCopyAttributeValue(element, kAXPlaceholderValueAttribute as CFString, &phRef)
                if let ph = phRef as? String,
                   localizedSpotlightSearchPlaceholders.contains(ph) {
                    return false
                }
            }
            var winRef: AnyObject?
            guard AXUIElementCopyAttributeValue(element, kAXWindowAttribute as CFString, &winRef) == .success,
                  let resolvedWin = safeAXUIElement(winRef) else {
                return false
            }
            windowElement = resolvedWin
        } else {
            return false
        }

        var sizeRef: AnyObject?
        if AXUIElementCopyAttributeValue(windowElement, kAXSizeAttribute as CFString, &sizeRef) == .success,
           let axVal = safeAXValue(sizeRef) {
            var size = CGSize.zero
            if AXValueGetValue(axVal, .cgSize, &size) {
                if size.width < 500 || size.height < 350 {
                    return false
                }
            }
        }

        let appsPlaceholders = localizedAppsPlaceholders
        let searchPlaceholders = localizedSpotlightSearchPlaceholders
        var hasFilterBar = false
        var hasAppsZKW = false
        var hasAppsPlaceholder = false
        var hasSearchPlaceholder = false

        var queue: [(AXUIElement, Int)] = [(windowElement, 0)]
        while !queue.isEmpty {
            let (node, depth) = queue.removeFirst()
            var idRef: AnyObject?
            AXUIElementCopyAttributeValue(node, kAXIdentifierAttribute as CFString, &idRef)
            let idStr = idRef as? String ?? ""

            if idStr.contains("com.apple.spotlight.zkw.apps") {
                hasAppsZKW = true
            } else if idStr == "QueryFilterBar" {
                hasFilterBar = true
            }
            if idStr == "SpotlightSearchField" {
                var phRef: AnyObject?
                AXUIElementCopyAttributeValue(node, kAXPlaceholderValueAttribute as CFString, &phRef)
                if let ph = phRef as? String {
                    if searchPlaceholders.contains(ph) {
                        hasSearchPlaceholder = true
                    } else if appsPlaceholders.contains(ph) {
                        hasAppsPlaceholder = true
                    }
                }
            }

            if depth < 6 {
                var childrenRef: AnyObject?
                if AXUIElementCopyAttributeValue(node, kAXChildrenAttribute as CFString, &childrenRef) == .success,
                   let children = childrenRef as? [AXUIElement] {
                    for child in children.prefix(35) {
                        queue.append((child, depth + 1))
                    }
                }
            }
        }

        if hasAppsZKW || hasAppsPlaceholder {
            return true
        }
        if hasSearchPlaceholder {
            return false
        }
        return hasFilterBar
    }

    // MARK: - Dismissal & Presentation Coordination

    /// Closes any lingering macOS Spotlight Applications (`Siri AI` / `Spotlight`) overlay
    /// if it slipped open behind Launchpad Home, without affecting `Cmd+Space` Search.
    /// Returns `true` if a visible native Spotlight Apps window was targeted for dismissal.
    @discardableResult
    func dismissResidualSpotlightAppsIfVisible(
        keepLaunchpadOpen: Bool,
        restoreApp: NSRunningApplication? = nil
    ) -> Bool {
        guard Defaults[.enableLaunchpad] else { return false }
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.apps.launcher") {
            app.hide()
            app.terminate()
        }
        guard Self.isSpotlightAppsCGWindowVisible() else { return false }
        dismissNativeSpotlightAppsWindow(keepLaunchpadOpen: keepLaunchpadOpen, restoreApp: restoreApp)
        return true
    }

    private func handleSystemAppsPopupDetected(fromNativeTrigger: Bool) {
        guard Defaults[.enableLaunchpad] else { return }

        for app in NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.apps.launcher") {
            app.hide()
            app.terminate()
        }

        let controller = LaunchpadWindowController.shared
        let now = Date()

        // If our Multitouch pinch already opened Launchpad Home < 0.95s ago and WindowServer
        // just fired SpotlightApps right behind us, silently kill Spotlight Apps without closing Launchpad Home!
        if controller.isPresented && now < suppressNativeDismissUntil {
            dismissNativeSpotlightAppsWindow(keepLaunchpadOpen: true)
            return
        }

        let minGap: TimeInterval = fromNativeTrigger ? 0.45 : 0.65
        guard now.timeIntervalSince(lastTriggerAt) >= minGap else { return }
        lastTriggerAt = now

        let willKeepOpen = !controller.isPresented
        controller.toggle()
        dismissNativeSpotlightAppsWindow(keepLaunchpadOpen: willKeepOpen)
    }

    private func dismissNativeSpotlightAppsWindow(
        keepLaunchpadOpen: Bool,
        restoreApp: NSRunningApplication? = nil
    ) {
        nativeDismissGeneration += 1
        let dismissGen = nativeDismissGeneration
        LaunchpadWindowController.shared.suppressEscape(for: 0.65)

        let targetApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.campo")
            + NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Spotlight")
        let siriApp = targetApps.first(where: { !$0.isTerminated })

        if AXIsProcessTrusted() {
            // Try silent AX cancel first on any visible Applications window.
            for app in targetApps where !app.isTerminated {
                let axApp = AXUIElementCreateApplication(app.processIdentifier)
                for win in Self.candidateAXWindows(for: axApp) where Self.isSystemAppsWindowElement(win) {
                    AXUIElementPerformAction(win, kAXCancelAction as CFString)
                }
            }

            let finishRestoreFocus = {
                if keepLaunchpadOpen {
                    guard LaunchpadWindowController.shared.isPresented else { return }
                    NSApp.activate()
                    LaunchpadWindowController.shared.bringPanelToFrontIfPresented()
                } else if let restoreApp, !restoreApp.isTerminated {
                    restoreApp.activate()
                }
            }

            let sendEscapeDismissal = { [weak self] in
                guard let self, self.nativeDismissGeneration == dismissGen else { return }
                LaunchpadWindowController.shared.suppressEscape(for: 0.55)
                siriApp?.activate()

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.018) { [weak self] in
                    guard let self, self.nativeDismissGeneration == dismissGen else { return }
                    LaunchpadWindowController.shared.suppressEscape(for: 0.45)
                    if let src = CGEventSource(stateID: .hidSystemState) {
                        CGEvent(keyboardEventSource: src, virtualKey: 0x35, keyDown: true)?.post(tap: .cghidEventTap)
                        CGEvent(keyboardEventSource: src, virtualKey: 0x35, keyDown: false)?.post(tap: .cghidEventTap)
                    }

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.045) { [weak self] in
                        guard let self, self.nativeDismissGeneration == dismissGen else { return }
                        finishRestoreFocus()
                    }
                }
            }

            sendEscapeDismissal()

            // Verify Siri AI did not ignore Escape mid-spring animation; retry cleanly if still visible.
            for verifyDelay in [0.055, 0.120, 0.220, 0.360] {
                DispatchQueue.main.asyncAfter(deadline: .now() + verifyDelay) { [weak self] in
                    guard let self, self.nativeDismissGeneration == dismissGen else { return }
                    guard Self.isSpotlightAppsCGWindowVisible() else {
                        self.wasSystemAppsWindowOnScreen = false
                        finishRestoreFocus()
                        return
                    }
                    sendEscapeDismissal()
                }
            }
            return
        }

        siriApp?.hide()
        if keepLaunchpadOpen {
            NSApp.activate()
            LaunchpadWindowController.shared.bringPanelToFrontIfPresented()
        } else if let restoreApp, !restoreApp.isTerminated {
            restoreApp.activate()
        } else if LaunchpadWindowController.shared.isPresented {
            NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first?.activate()
        }
    }
}
