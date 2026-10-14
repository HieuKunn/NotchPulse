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
        return false
    }

    private init() {
        if Self.isSessionLocked || NotchPulseLockMonitor.isScreenActuallyLocked() {
            self.isScreenLocked = true
            startLockSessionSupervisor()
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
    
    private func setupObservers() {
        // 1. Listen for screen lock
        let lockToken = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.isScreenLocked = true
                self.startLockSessionSupervisor()
                self.updateLockScreenMediaWindowVisibility()
            }
        }
        distributedTokens.append(lockToken)
        
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
        let handleWake = { [weak self] in
            guard let self = self else { return }
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                // Immediately check lock state and show window if locked without waiting 800ms
                let locked = self.isScreenLocked || Self.isSessionLocked || NotchPulseLockMonitor.isScreenActuallyLocked()
                if locked {
                    self.isScreenLocked = true
                    self.startLockSessionSupervisor()
                    self.updateLockScreenMediaWindowVisibility()
                }
                // Also re-verify after 400ms when display has fully powered on
                try? await Task.sleep(for: .milliseconds(400))
                if self.isScreenLocked || Self.isSessionLocked || NotchPulseLockMonitor.isScreenActuallyLocked() {
                    self.isScreenLocked = true
                    self.updateLockScreenMediaWindowVisibility()
                }
            }
        }

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.screensDidWakeNotification)
            .receive(on: DispatchQueue.main)
            .sink { _ in handleWake() }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: DispatchQueue.main)
            .sink { _ in handleWake() }
            .store(in: &cancellables)
            
        // 4. Listen for screen sleep (lid closed, screensaver sleep, display sleep)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.screensDidSleepNotification)
            .receive(on: DispatchQueue.main)
            .sink { _ in
                // Handled natively by NotchPulseFaceUnlockCoordinator
            }
            .store(in: &cancellables)

        // 4b. Listen for will sleep (e.g. lid closed)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)
            .receive(on: DispatchQueue.main)
            .sink { _ in
                // Handled natively by NotchPulseFaceUnlockCoordinator
            }
            .store(in: &cancellables)
            
        // 5. Listen for music state changes to show/hide lock screen window dynamically
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
        .store(in: &cancellables)
    }
    
    private func shouldShowLockScreenMedia() -> Bool {
        let actuallyLocked = isScreenLocked || Self.isSessionLocked || NotchPulseLockMonitor.isScreenActuallyLocked()
        guard actuallyLocked && Defaults[.enableLockScreenPlayer] else { return false }
        
        // CRITICAL: Once the lock screen media player is visible during an active lock session,
        // it must ALWAYS remain visible! Never hide or flash on track change, button clicks, pause, or seek.
        if LockScreenMediaWindow.shared.isWindowVisible {
            // Only hide if the underlying media app was explicitly quit by the user
            if let bundleId = MusicManager.shared.bundleIdentifier, !bundleId.isEmpty {
                if bundleId == "com.apple.Music" || bundleId == "com.spotify.client" {
                    let isAppRunning = NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleId }
                    if !isAppRunning && !MusicManager.shared.isPlaying {
                        return false
                    }
                }
            }
            return true
        }
        
        let title = MusicManager.shared.songTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty {
            if let bundleId = MusicManager.shared.bundleIdentifier, !bundleId.isEmpty {
                // If it's a known dedicated music app, verify app is still running
                if bundleId == "com.apple.Music" || bundleId == "com.spotify.client" {
                    let isAppRunning = NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleId }
                    if !isAppRunning {
                        return false
                    }
                }
            }
            return true
        }
        
        if MusicManager.shared.isPlaying {
            return true
        }
        
        let npTitle = NowPlayingController.shared.playbackState.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !npTitle.isEmpty || NowPlayingController.shared.playbackState.isPlaying {
            return true
        }
        
        // Also show if a media player bundle is known and running
        if let bundleId = MusicManager.shared.bundleIdentifier, !bundleId.isEmpty {
            let isAppRunning = NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleId }
            if isAppRunning && (bundleId == "com.apple.Music" || bundleId == "com.spotify.client") {
                return true
            }
        }
        
        return false
    }

    func updateLockScreenMediaWindowVisibility() {
        let actuallyLocked = isScreenLocked || Self.isSessionLocked || NotchPulseLockMonitor.isScreenActuallyLocked()
        let shouldShow = shouldShowLockScreenMedia()
        
        if shouldShow {
            hideDebounceTask?.cancel()
            hideDebounceTask = nil
            LockScreenMediaWindow.shared.show()
        } else {
            hideDebounceTask?.cancel()
            hideDebounceTask = nil
            // Only dismiss when the user actually unlocks the Mac or explicitly disables the player
            if !actuallyLocked || !Defaults[.enableLockScreenPlayer] {
                LockScreenMediaWindow.shared.hide()
            }
        }
    }
}
