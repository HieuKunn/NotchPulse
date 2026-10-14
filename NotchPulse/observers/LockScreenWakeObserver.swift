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
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(1500))
                guard let self = self, self.isScreenLocked else { break }
                
                let actuallyLocked = Self.isSessionLocked || NotchPulseLockMonitor.isScreenActuallyLocked()
                if actuallyLocked {
                    // LockSessionSupervisor handles session lock
                } else {
                    // Session was unlocked (notification may have been delayed or missed)
                    self.isScreenLocked = false
                    self.hideDebounceTask?.cancel()
                    self.hideDebounceTask = nil
                    self.updateLockScreenMediaWindowVisibility()
                    break
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
                try? await Task.sleep(for: .milliseconds(800))
                let locked = self.isScreenLocked || Self.isSessionLocked || NotchPulseLockMonitor.isScreenActuallyLocked()
                if locked {
                    self.isScreenLocked = true
                    self.startLockSessionSupervisor()
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
            if actuallyLocked {
                // Screen is still locked, but track state might be transitioning (e.g. Next/Previous track, seek)
                // Debounce hiding by 2.5 seconds to avoid the media window flickering or vanishing during track change
                if hideDebounceTask == nil {
                    hideDebounceTask = Task { @MainActor [weak self] in
                        try? await Task.sleep(for: .milliseconds(2500))
                        guard !Task.isCancelled, let self = self else { return }
                        self.hideDebounceTask = nil
                        if !self.shouldShowLockScreenMedia() {
                            LockScreenMediaWindow.shared.hide()
                        }
                    }
                }
            } else {
                // Screen is completely unlocked, dismiss immediately
                hideDebounceTask?.cancel()
                hideDebounceTask = nil
                LockScreenMediaWindow.shared.hide()
            }
        }
    }
}
