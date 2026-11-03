import Cocoa
import Combine
import Defaults
import Foundation

@MainActor
final class LockScreenWakeObserver: ObservableObject {
    static let shared = LockScreenWakeObserver()
    
    @Published private(set) var isScreenLocked: Bool = false
    
    private var cancellables = Set<AnyCancellable>()
    private var distributedTokens: [NSObjectProtocol] = []
    private var lockSessionTimer: Task<Void, Never>?
    private var hideDebounceTask: Task<Void, Never>?
    private var lockTransitionTask: Task<Void, Never>?
    private var wakeTransitionTask: Task<Void, Never>?
    
    nonisolated static var isSessionLocked: Bool {
        NotchPulseLockMonitor.isScreenActuallyLocked()
    }

    private init() {
        if NotchPulseLockMonitor.isScreenActuallyLocked() {
            self.isScreenLocked = true
            startLockSessionSupervisor()
            MusicManager.shared.forceUpdate()
            updateLockScreenMediaWindowVisibility()
        }
        setupObservers()
    }
    
    private func cancelPendingTasks() {
        hideDebounceTask?.cancel(); hideDebounceTask = nil
        lockSessionTimer?.cancel(); lockSessionTimer = nil
        lockTransitionTask?.cancel(); lockTransitionTask = nil
        wakeTransitionTask?.cancel(); wakeTransitionTask = nil
    }

    func cleanup() {
        cancelPendingTasks()
        for token in distributedTokens {
            DistributedNotificationCenter.default().removeObserver(token)
        }
        distributedTokens.removeAll()
        cancellables.removeAll()
    }
    
    private func startLockSessionSupervisor() {
        lockSessionTimer?.cancel()
        lockSessionTimer = Task { @MainActor [weak self] in
            // Step 1: Wait until WindowServer confirms screen is actually locked before monitoring for unlock
            var confirmedLocked = false
            for _ in 0..<20 {
                try? await Task.sleep(for: .milliseconds(150))
                guard let self = self, self.isScreenLocked else { return }
                if NotchPulseLockMonitor.isScreenActuallyLocked() {
                    confirmedLocked = true
                    break
                }
            }
            guard confirmedLocked else { return }

            // Step 2: Now actively monitor for unlock with consecutive debounce to guard against transient WindowServer drops
            var consecutiveUnlockedCount = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(800))
                guard let self = self, self.isScreenLocked else { break }
                
                let actuallyLocked = NotchPulseLockMonitor.isScreenActuallyLocked()
                if actuallyLocked {
                    consecutiveUnlockedCount = 0
                } else {
                    consecutiveUnlockedCount += 1
                    if consecutiveUnlockedCount >= 3 {
                        self.handleUnlockTransition(animated: true)
                        break
                    }
                }
            }
        }
    }

    func handleUnlockTransition(animated: Bool = true) {
        guard self.isScreenLocked || LockScreenMediaWindow.shared.isWindowVisible else { return }
        self.isScreenLocked = false
        cancelPendingTasks()
        NotchPulseLockMonitor.invalidateLockCache()
        if animated {
            LockScreenMediaWindow.shared.hide(immediately: false)
        } else {
            LockScreenMediaWindow.shared.hideImmediately()
        }
    }
    
    private func handleLockTransition() {
        wakeTransitionTask?.cancel()
        wakeTransitionTask = nil
        lockTransitionTask?.cancel()
        lockTransitionTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.isScreenLocked = true
            self.startLockSessionSupervisor()
            MusicManager.shared.forceUpdate()
            self.updateLockScreenMediaWindowVisibility()
            
            // Progressively re-assert visibility as WindowServer transitions into lock screen space
            for delayMs in [150, 350, 650, 1000, 1500] {
                try? await Task.sleep(for: .milliseconds(delayMs))
                guard !Task.isCancelled, self.isScreenLocked else { break }
                MusicManager.shared.forceUpdate()
                self.updateLockScreenMediaWindowVisibility()
            }
        }
    }
    
    private func handleWake() {
        lockTransitionTask?.cancel()
        lockTransitionTask = nil
        wakeTransitionTask?.cancel()
        wakeTransitionTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            // Brief settle delay: CGSession's reported state can lag the true state right after wake.
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            
            NotchPulseLockMonitor.invalidateLockCache()
            NotchPulseVault.preflightKeychainAuthorization()
            if NotchPulseFaceEnrollmentStore.shared.activeIdentities.isEmpty {
                NotchPulseFaceEnrollmentStore.shared.reloadIfUnlocked()
            }
            
            // Progressive verification on wake: WindowServer can take 300-1200ms after overnight deep sleep
            var isLocked = false
            for delayMs in [0, 250, 450, 600] {
                if delayMs > 0 {
                    try? await Task.sleep(for: .milliseconds(delayMs))
                }
                guard !Task.isCancelled else { return }
                if NotchPulseLockMonitor.isScreenActuallyLocked(bypassCache: true) {
                    isLocked = true
                    break
                }
            }
            
            self.isScreenLocked = isLocked
            if isLocked {
                self.startLockSessionSupervisor()
                MusicManager.shared.forceUpdate()
                self.updateLockScreenMediaWindowVisibility()
            } else {
                self.handleUnlockTransition(animated: false)
                return
            }
        }
    }
    
    private func setupObservers() {
        // 1. Listen for screen lock
        let lockToken = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleLockTransition()
            }
        }
        distributedTokens.append(lockToken)
        
        // 1b. Listen for screensaver start
        let screensaverToken = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screensaver.didstart"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleLockTransition()
            }
        }
        distributedTokens.append(screensaverToken)
        
        // 2. Listen for screen unlock
        let unlockToken = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleUnlockTransition(animated: true)
            }
        }
        distributedTokens.append(unlockToken)
        
        // 3. Listen for screen wake & system wake
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.screensDidWakeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.handleWake() }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.handleWake() }
            .store(in: &cancellables)
            
        // 4. Listen for screen sleep (lid closed, screensaver sleep, display sleep)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.screensDidSleepNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    LockScreenMediaWindow.shared.hideImmediately()
                    self?.handleLockTransition()
                }
            }
            .store(in: &cancellables)

        // 4b. Listen for will sleep (e.g. lid closed)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    LockScreenMediaWindow.shared.hideImmediately()
                    self?.handleLockTransition()
                }
            }
            .store(in: &cancellables)

        // 4c. Listen for screen parameter changes (connecting/disconnecting monitor, resolution change)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateLockScreenMediaWindowVisibility()
            }
            .store(in: &cancellables)
            
        // 5. Listen for music state changes to show/hide lock screen window dynamically (deferred to prevent dispatch_once init deadlocks)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            Publishers.Merge4(
                MusicManager.shared.$isPlaying.map { _ in () },
                MusicManager.shared.$songTitle.map { _ in () },
                MusicManager.shared.$bundleIdentifier.map { _ in () },
                Defaults.publisher(.enableLockScreenPlayer).map { _ in () }
            )
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateLockScreenMediaWindowVisibility()
            }
            .store(in: &self.cancellables)
        }
    }
    
    private func shouldShowLockScreenMedia() -> Bool {
        guard isScreenLocked else { return false }
        guard Defaults[.enableLockScreenPlayer] else { return false }
        let title = MusicManager.shared.songTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty && title != "I'm Handsome" else { return false }
        return true
    }

    func updateLockScreenMediaWindowVisibility(immediately: Bool = false) {
        let shouldShow = shouldShowLockScreenMedia()
        
        hideDebounceTask?.cancel()
        hideDebounceTask = nil
        
        if shouldShow {
            LockScreenMediaWindow.shared.show()
        } else {
            if immediately || !isScreenLocked {
                LockScreenMediaWindow.shared.hideImmediately()
            } else {
                // Debounce hide by 2.0s to prevent window tear-down / flashing during inter-track transitions
                hideDebounceTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(2000))
                    guard !Task.isCancelled, let self = self else { return }
                    if !self.shouldShowLockScreenMedia() {
                        LockScreenMediaWindow.shared.hide()
                    }
                }
            }
        }
    }
}
