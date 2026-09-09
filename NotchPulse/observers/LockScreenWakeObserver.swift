//
//  LockScreenWakeObserver.swift
//  NotchPulse
//
//  Created for NotchPulse v2.0 - Lock Screen & Wake Coordination
//

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
    
    nonisolated static var isSessionLocked: Bool {
        if let dict = CGSessionCopyCurrentDictionary() as? [String: Any] {
            if let val = dict["CGSSessionScreenIsLocked"] {
                return (val as? Bool) ?? ((val as? NSNumber)?.boolValue ?? false)
            }
        }
        return false
    }

    private init() {
        if Self.isSessionLocked {
            self.isScreenLocked = true
            startLockSessionSupervisor()
            if Defaults[.enableFaceID] && FaceIDManager.shared.isEnrolled {
                LockScreenFaceIDWindow.shared.show()
            }
        }
        setupObservers()
    }
    
    func cleanup() {
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
                
                if Self.isSessionLocked {
                    if Defaults[.enableFaceID] && FaceIDManager.shared.isEnrolled {
                        if !LockScreenFaceIDWindow.shared.isVisible {
                            LockScreenFaceIDWindow.shared.show()
                        }
                    }
                } else {
                    // Session was unlocked (notification may have been delayed or missed)
                    self.isScreenLocked = false
                    FaceIDManager.shared.cancelCurrentSession()
                    LockScreenFaceIDWindow.shared.hide()
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
                
                if Defaults[.enableFaceID] && FaceIDManager.shared.isEnrolled {
                    FaceIDManager.shared.lastUnlockSuccess = false
                    FaceIDManager.shared.statusMessage = "Ready"
                    LockScreenFaceIDWindow.shared.show()
                    FaceIDManager.shared.startRecognitionOnWake()
                }
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
                FaceIDManager.shared.cancelCurrentSession()
                LockScreenFaceIDWindow.shared.hide()
                self.updateLockScreenMediaWindowVisibility()
            }
        }
        distributedTokens.append(unlockToken)
        
        // 3. Listen for screen wake & system wake
        let handleWake = { [weak self] in
            guard let self = self else { return }
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                try? await Task.sleep(for: .milliseconds(120))
                let locked = self.isScreenLocked || Self.isSessionLocked
                if locked {
                    self.isScreenLocked = true
                    self.startLockSessionSupervisor()
                    if Defaults[.enableFaceID] && FaceIDManager.shared.isEnrolled {
                        LockScreenFaceIDWindow.shared.show()
                        FaceIDManager.shared.startRecognitionOnWake()
                    }
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
        // Keep LockScreenFaceIDWindow attached so it is ready immediately upon display power-on
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.screensDidSleepNotification)
            .receive(on: DispatchQueue.main)
            .sink { _ in
                FaceIDManager.shared.cancelCurrentSession()
            }
            .store(in: &cancellables)

        // 4b. Listen for will sleep (e.g. lid closed)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)
            .receive(on: DispatchQueue.main)
            .sink { _ in
                FaceIDManager.shared.cancelCurrentSession()
            }
            .store(in: &cancellables)
            
        // 5. Listen for music state changes to show/hide lock screen media player dynamically
        MusicManager.shared.$isPlaying
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateLockScreenMediaWindowVisibility()
            }
            .store(in: &cancellables)
            
        Defaults.publisher(.enableLockScreenPlayer)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateLockScreenMediaWindowVisibility()
            }
            .store(in: &cancellables)
    }
    
    func updateLockScreenMediaWindowVisibility() {
        let shouldShow = isScreenLocked
            && Defaults[.enableLockScreenPlayer]
            && (MusicManager.shared.isPlaying || !MusicManager.shared.isPlayerIdle)
        
        if shouldShow {
            LockScreenMediaWindow.shared.show()
        } else {
            LockScreenMediaWindow.shared.hide()
        }
    }
}
