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
        if let dict = CGSessionCopyCurrentDictionary() as? [String: Any] {
            if let val = dict["CGSSessionScreenIsLocked"] {
                return (val as? Bool) ?? ((val as? NSNumber)?.boolValue ?? false)
            }
        }
        return NotchPulseLockMonitor.isScreenActuallyLocked()
    }

    private init() {
        if Self.isSessionLocked || NotchPulseLockMonitor.isScreenActuallyLocked() {
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
            var consecutiveUnlockedCount = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(1500))
                guard let self = self, self.isScreenLocked else { break }
                
                let actuallyLocked = Self.isSessionLocked || NotchPulseLockMonitor.isScreenActuallyLocked()
                if actuallyLocked {
                    consecutiveUnlockedCount = 0
                } else {
                    // CGSessionCopyCurrentDictionary can return nil/empty during wake and sleep transitions.
                    // Only conclude unlocked if it remains unlocked for multiple consecutive checks (4.5s)
                    consecutiveUnlockedCount += 1
                    if consecutiveUnlockedCount >= 3 {
                        self.isScreenLocked = false
                        self.hideDebounceTask?.cancel()
                        self.hideDebounceTask = nil
                        self.updateLockScreenMediaWindowVisibility()
                        break
                    }
                }
            }
        }
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
                guard self.isScreenLocked || Self.isSessionLocked || NotchPulseLockMonitor.isScreenActuallyLocked() else { break }
                self.isScreenLocked = true
                MusicManager.shared.forceUpdate()
                self.updateLockScreenMediaWindowVisibility()
            }
        }
    }
    
    private func handleWake() {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            let locked = self.isScreenLocked || Self.isSessionLocked || NotchPulseLockMonitor.isScreenActuallyLocked()
            if locked {
                self.isScreenLocked = true
                self.startLockSessionSupervisor()
                MusicManager.shared.forceUpdate()
                self.updateLockScreenMediaWindowVisibility()
            }
            // Verify progressively after wake as display powers on
            for delayMs in [150, 350, 650, 1000] {
                try? await Task.sleep(for: .milliseconds(delayMs))
                if self.isScreenLocked || Self.isSessionLocked || NotchPulseLockMonitor.isScreenActuallyLocked() {
                    self.isScreenLocked = true
                    MusicManager.shared.forceUpdate()
                    self.updateLockScreenMediaWindowVisibility()
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
                guard let self = self else { return }
                self.isScreenLocked = false
                self.lockSessionTimer?.cancel()
                self.lockSessionTimer = nil
                self.hideDebounceTask?.cancel()
                self.hideDebounceTask = nil
                self.updateLockScreenMediaWindowVisibility()
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
                    self?.handleLockTransition()
                }
            }
            .store(in: &cancellables)

        // 4b. Listen for will sleep (e.g. lid closed)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleLockTransition()
                }
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
        let actuallyLocked = isScreenLocked || Self.isSessionLocked || NotchPulseLockMonitor.isScreenActuallyLocked()
        guard actuallyLocked && Defaults[.enableLockScreenPlayer] else { return false }
        let title = MusicManager.shared.songTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty && title != "I'm Handsome" else { return false }
        return true
    }

    func updateLockScreenMediaWindowVisibility() {
        let actuallyLocked = isScreenLocked || Self.isSessionLocked || NotchPulseLockMonitor.isScreenActuallyLocked()
        let shouldShow = shouldShowLockScreenMedia()
        
        hideDebounceTask?.cancel()
        hideDebounceTask = nil
        
        if shouldShow {
            LockScreenMediaWindow.shared.show()
        } else {
            if !actuallyLocked || !Defaults[.enableLockScreenPlayer] {
                LockScreenMediaWindow.shared.hide()
            }
        }
    }
}
