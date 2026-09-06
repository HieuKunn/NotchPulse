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
        // 1. Listen for screen lock
        let lockToken = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.isScreenLocked = true
                self.updateLockScreenMediaWindowVisibility()
                
                // Show Lock Screen Face ID Notch HUD and trigger recognition
                if Defaults[.enableFaceID] && FaceIDManager.shared.isEnrolled {
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
                FaceIDManager.shared.cancelCurrentSession()
                LockScreenFaceIDWindow.shared.hide()
                self.updateLockScreenMediaWindowVisibility()
            }
        }
        distributedTokens.append(unlockToken)
        
        // 3. Listen for screen wake (user touched trackpad, pressed key, opened lid)
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
            
        // 4. Listen for screen sleep
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.screensDidSleepNotification)
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
