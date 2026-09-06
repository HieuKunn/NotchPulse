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
    
    private init() {
        setupObservers()
    }
    
    func cleanup() {
        for token in distributedTokens {
            DistributedNotificationCenter.default().removeObserver(token)
        }
        distributedTokens.removeAll()
        cancellables.removeAll()
    }
    
    private func setupObservers() {
        // 1. Listen for screen lock (when user locks screen, do NOT auto-unlock immediately)
        let lockToken = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.isScreenLocked = true
                self.updateLockScreenMediaWindowVisibility()
                
                // User intentionally locked their screen while working at desk.
                // Show the waiting Face ID UI so they can click to scan, but do NOT scan automatically.
                if Defaults[.enableFaceID] && FaceIDManager.shared.isEnrolled {
                    LockScreenFaceIDWindow.shared.show()
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
                FaceIDManager.shared.cancelCurrentSession()
                LockScreenFaceIDWindow.shared.hide()
                self.updateLockScreenMediaWindowVisibility()
            }
        }
        distributedTokens.append(unlockToken)
        
        // 3. Listen for screen wake (user opens MacBook lid, touches trackpad/keyboard to wake display from sleep)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.screensDidWakeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                if self.isScreenLocked {
                    if Defaults[.enableFaceID] && FaceIDManager.shared.isEnrolled {
                        LockScreenFaceIDWindow.shared.show()
                        FaceIDManager.shared.startRecognitionOnWake()
                    }
                    self.updateLockScreenMediaWindowVisibility()
                }
            }
            .store(in: &cancellables)

        // 3b. Listen for system wake from sleep (e.g. MacBook lid opened)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                if self.isScreenLocked {
                    if Defaults[.enableFaceID] && FaceIDManager.shared.isEnrolled {
                        LockScreenFaceIDWindow.shared.show()
                        FaceIDManager.shared.startRecognitionOnWake()
                    }
                    self.updateLockScreenMediaWindowVisibility()
                }
            }
            .store(in: &cancellables)
            
        // 4. Listen for screen sleep (lid closed, screensaver sleep, display sleep)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.screensDidSleepNotification)
            .receive(on: DispatchQueue.main)
            .sink { _ in
                FaceIDManager.shared.cancelCurrentSession()
                LockScreenFaceIDWindow.shared.hide()
            }
            .store(in: &cancellables)

        // 4b. Listen for will sleep (e.g. lid closed)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)
            .receive(on: DispatchQueue.main)
            .sink { _ in
                FaceIDManager.shared.cancelCurrentSession()
                LockScreenFaceIDWindow.shared.hide()
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
            
        // 6. Listen for Face ID state changes to hide LockScreenFaceIDWindow on success after delay
        FaceIDManager.shared.$lastUnlockSuccess
            .receive(on: DispatchQueue.main)
            .sink { success in
                if success {
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(1200))
                        LockScreenFaceIDWindow.shared.hide()
                    }
                }
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
