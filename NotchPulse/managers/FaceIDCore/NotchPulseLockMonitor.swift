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
            self?.isScreenLocked = true
            Self.setCachedLockState(true)
            self?.record(.screenLocked)
        })
        distributedObservers.append(distributed.addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isScreenLocked = false
            Self.invalidateLockCache()
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
        isSleeping = false
        wakeEventCount += 1
        Self.invalidateLockCache()
        record(.wake)
    }

    private func record(_ kind: LockEventKind) {
        lastEvent = kind
        eventCount += 1
    }

    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cachedLockState: Bool?
    nonisolated(unsafe) private static var cachedLockTimestamp: TimeInterval = 0

    nonisolated static func invalidateLockCache() {
        cacheLock.lock()
        cachedLockState = nil
        cachedLockTimestamp = 0
        cacheLock.unlock()
    }

    nonisolated static func setCachedLockState(_ locked: Bool) {
        cacheLock.lock()
        cachedLockState = locked
        cachedLockTimestamp = ProcessInfo.processInfo.systemUptime
        cacheLock.unlock()
    }

    /// Authoritative lock state from the CoreGraphics session server.
    /// Bridges the initial entrance animation with a brief 2.0s cache when entering lock,
    /// but never caches false so wake delays never freeze lock detection.
    nonisolated static func isScreenActuallyLocked(bypassCache: Bool = false) -> Bool {
        if !bypassCache {
            cacheLock.lock()
            let now = ProcessInfo.processInfo.systemUptime
            // Trust cached lock state during the initial 2.0s transition window only when locked
            if let cached = cachedLockState, cached == true, (now - cachedLockTimestamp) < 2.0 {
                cacheLock.unlock()
                return true
            }
            cacheLock.unlock()
        }

        guard let dict = CGSessionCopyCurrentDictionary() as? [String: Any] else {
            cacheLock.lock()
            let fallback = (cachedLockState == true)
            cacheLock.unlock()
            return fallback
        }
        let isLocked = (dict["CGSSessionScreenIsLocked"] as? Bool) ?? false
        if isLocked {
            setCachedLockState(true)
        } else {
            invalidateLockCache()
        }
        return isLocked
    }
}
