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
    
    func cleanup() {
        hideDebounceTask?.cancel()
        hideDebounceTask = nil
        lockSessionTimer?.cancel()
        lockSessionTimer = nil
        for token in distributedTokens {
            DistributedNotificationCenter.default().removeObserver(token)
        }
        distributedTokens.removeAll()
        cancellables.removeAll()
    }
    
    private func startLockSessionSupervisor() {
        lockSessionTimer?.cancel()
        lockSessionTimer = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(800))
                guard let self = self, self.isScreenLocked else { break }
                
                let actuallyLocked = NotchPulseLockMonitor.isScreenActuallyLocked()
                if !actuallyLocked {
                    self.handleUnlockTransition()
                    break
                }
            }
        }
    }

    func handleUnlockTransition() {
        self.isScreenLocked = false
        NotchPulseLockMonitor.setCachedLockState(false)
        self.lockSessionTimer?.cancel()
        self.lockSessionTimer = nil
        self.hideDebounceTask?.cancel()
        self.hideDebounceTask = nil
        LockScreenMediaWindow.shared.hideImmediately()
    }
    
    private func handleLockTransition() {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.isScreenLocked = true
            self.startLockSessionSupervisor()
            MusicManager.shared.forceUpdate()
            self.updateLockScreenMediaWindowVisibility()
            
            // Progressively re-assert visibility as WindowServer transitions into lock screen space
            for delayMs in [150, 350, 650, 1000] {
                try? await Task.sleep(for: .milliseconds(delayMs))
                guard self.isScreenLocked || NotchPulseLockMonitor.isScreenActuallyLocked() else { break }
                self.isScreenLocked = true
                MusicManager.shared.forceUpdate()
                self.updateLockScreenMediaWindowVisibility()
            }
        }
    }
    
    private func handleWake() {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            NotchPulseLockMonitor.invalidateLockCache()
            NotchPulseVault.preflightKeychainAuthorization()
            NotchPulseFaceEnrollmentStore.shared.reloadIfUnlocked()
            let locked = NotchPulseLockMonitor.isScreenActuallyLocked()
            self.isScreenLocked = locked
            if locked {
                self.startLockSessionSupervisor()
                MusicManager.shared.forceUpdate()
                self.updateLockScreenMediaWindowVisibility()
            } else {
                self.handleUnlockTransition()
            }
            // Verify progressively after wake as display powers on
            for delayMs in [250, 600, 1000] {
                try? await Task.sleep(for: .milliseconds(delayMs))
                let recheck = NotchPulseLockMonitor.isScreenActuallyLocked()
                if self.isScreenLocked != recheck {
                    self.isScreenLocked = recheck
                    if recheck {
                        self.startLockSessionSupervisor()
                        MusicManager.shared.forceUpdate()
                        self.updateLockScreenMediaWindowVisibility()
                    } else {
                        self.handleUnlockTransition()
                    }
                }
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
                self?.handleUnlockTransition()
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
        guard NotchPulseLockMonitor.isScreenActuallyLocked() && Defaults[.enableLockScreenPlayer] else { return false }
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
                LockScreenMediaWindow.shared.hide()
            }
        }
    }
}
