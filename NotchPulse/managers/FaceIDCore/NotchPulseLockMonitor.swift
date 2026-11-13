import Foundation
import AppKit
import CoreGraphics
import Observation

/// Which signal most recently fired — `withObservationTracking`'s `onChange` doesn't say which property changed, so observers
/// read this alongside the monotonic `eventCount` to tell events apart.
enum LockEventKind {
    case screenLocked
    case screenUnlocked
    case willSleep
    /// Display turned back on, from system sleep, display sleep, or the screensaver stopping.
    case wake
}

@Observable
final class NotchPulseLockMonitor {
    /// NOT trustworthy alone: any same-user process can post these distributed notifications, and this process can be
    /// suspended before one is delivered (e.g. lid-close sleep racing a lock). UI/trigger signal only, never a security gate.
    private(set) var isScreenLocked: Bool = false

    /// Catches the case above: lock may have already happened while suspended, so wake is the first chance to notice — callers
    /// should re-derive lock state via `isScreenActuallyLocked()` on change rather than trust `isScreenLocked`.
    private(set) var wakeEventCount: Int = 0

    /// True from `willSleepNotification` until the next wake. `screenIsLocked` fires ~150ms before the system actually finishes
    /// suspending (measured via pmset/os_log correlation), so callers should skip acting on a lock while this is true and wait
    /// for the wake trigger instead.
    private(set) var isSleeping: Bool = false

    /// Observers track `eventCount` (changes on every event, even repeats of the same kind) then read `lastEvent`.
    private(set) var lastEvent: LockEventKind?
    private(set) var eventCount: Int = 0

    private var distributedObservers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []

    init() {
        startMonitoring()
    }

    deinit {
        let distributed = DistributedNotificationCenter.default()
        for observer in distributedObservers {
            distributed.removeObserver(observer)
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for observer in workspaceObservers {
            workspace.removeObserver(observer)
        }
    }

    private func startMonitoring() {
        let distributed = DistributedNotificationCenter.default()
        distributedObservers.append(distributed.addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Self.invalidateLockCache()
            self?.isScreenLocked = true
            self?.record(.screenLocked)
        })
        distributedObservers.append(distributed.addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Self.invalidateLockCache()
            self?.isScreenLocked = false
            self?.record(.screenUnlocked)
        })
        // Observing the key press that dismissed the screensaver isn't possible — Secure Event Input suppresses keyboard taps
        // on the lock screen regardless of Accessibility trust — so this notification stands in for it.
        distributedObservers.append(distributed.addObserver(
            forName: Notification.Name("com.apple.screensaver.didstop"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.record(.wake)
        })

        let workspace = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(workspace.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isSleeping = true
            self?.record(.willSleep)
        })
        // Display- and system-level wake are treated as equivalent triggers — they land within ~100ms of each other in either order.
        workspaceObservers.append(workspace.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.recordWake()
        })
        workspaceObservers.append(workspace.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.recordWake()
        })
    }

    private func recordWake() {
        Self.invalidateLockCache()
        isSleeping = false
        wakeEventCount += 1
        record(.wake)
    }

    private func record(_ kind: LockEventKind) {
        lastEvent = kind
        eventCount += 1
    }

    // MARK: - Short-lived lock-state cache
    // `CGSessionCopyCurrentDictionary()` is a WindowServer round-trip that allocates a dictionary on every call, and this
    // check sits on hot paths (hover, music polling, wake observers). A 200ms TTL removes the redundant IPC while the
    // lock/unlock notifications below invalidate it immediately, so state is never stale across a real transition.
    private nonisolated(unsafe) static var cachedLockState: (value: Bool, time: TimeInterval)?
    private static let lockCacheLock = NSLock()
    private static let lockCacheTTL: TimeInterval = 0.2

    nonisolated static func invalidateLockCache() {
        lockCacheLock.lock()
        cachedLockState = nil
        lockCacheLock.unlock()
    }

    /// Authoritative lock state from the CoreGraphics session server, not a spoofable notification. Fails closed if unavailable.
    nonisolated static func isScreenActuallyLocked(bypassCache: Bool = false) -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        if !bypassCache {
            lockCacheLock.lock()
            let cached = cachedLockState
            lockCacheLock.unlock()
            if let cached, now - cached.time < lockCacheTTL {
                return cached.value
            }
        }

        let value = queryScreenLockedState()
        lockCacheLock.lock()
        cachedLockState = (value, now)
        lockCacheLock.unlock()
        return value
    }

    private nonisolated static func queryScreenLockedState() -> Bool {
        guard let dict = CGSessionCopyCurrentDictionary() as? [String: Any] else {
            return false
        }
        if let num = dict["CGSSessionScreenIsLocked"] as? NSNumber {
            return num.boolValue
        }
        if let boolVal = dict["CGSSessionScreenIsLocked"] as? Bool {
            return boolVal
        }
        if let intVal = dict["CGSSessionScreenIsLocked"] as? Int {
            return intVal != 0
        }
        return false
    }
}
