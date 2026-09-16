//
//  SystemAuthPromptObserver.swift
//  NotchPulse
//
//  Created for NotchPulse v3.5 - System Authorization & Touch ID Prompt Interception
//  Event-driven observation of macOS SecurityAgent dialogs with 0% idle CPU overhead.
//

import AppKit
import Combine
import Defaults

@MainActor
final class SystemAuthPromptObserver: ObservableObject {
    static let shared = SystemAuthPromptObserver()
    
    private var cancellables = Set<AnyCancellable>()
    private var isCurrentlyVerifying: Bool = false
    private var verificationTask: Task<Void, Never>?
    
    private init() {
        setupObserver()
    }
    
    func cleanup() {
        verificationTask?.cancel()
        verificationTask = nil
        cancellables.removeAll()
        isCurrentlyVerifying = false
    }
    
    private func setupObserver() {
        // Event-driven: Only wakes up when an application changes focus
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleApplicationActivated(notification)
            }
            .store(in: &cancellables)
    }
    
    private func handleApplicationActivated(_ notification: Notification) {
        // Only run if the user has explicitly enabled Face ID for system prompts
        guard Defaults[.enableFaceIDForSystemPrompts],
              Defaults[.enableFaceID],
              FaceIDManager.shared.isEnrolled,
              FaceIDManager.shared.hasPasswordSet else {
            return
        }
        
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleId = app.bundleIdentifier else {
            return
        }
        
        // SecurityAgent handles system dialogs requesting administrator privileges or Touch ID/Password
        if bundleId == "com.apple.SecurityAgent" {
            triggerFaceIDForSecurityAgent(targetApp: app)
        }
    }
    
    private func triggerFaceIDForSecurityAgent(targetApp: NSRunningApplication) {
        guard !isCurrentlyVerifying else { return }
        isCurrentlyVerifying = true
        
        verificationTask?.cancel()
        verificationTask = Task { @MainActor [weak self] in
            // Allow SecurityAgent window to settle in front
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            
            // Present Face ID UI in the notch area
            LockScreenFaceIDWindow.shared.show()
            FaceIDManager.shared.startRecognitionOnWake()
            
            // Wait for scanning completion (timeout: 4.5s)
            let startTime = ContinuousClock.now
            var verified = false
            
            while ContinuousClock.now - startTime < .seconds(4.5) {
                if Task.isCancelled { break }
                
                if FaceIDManager.shared.lastUnlockSuccess {
                    verified = true
                    break
                }
                
                // If scanning finished without success, stop waiting
                if !FaceIDManager.shared.isScanning && !FaceIDManager.shared.lastUnlockSuccess {
                    break
                }
                
                try? await Task.sleep(for: .milliseconds(100))
            }
            
            if verified {
                // Success: Play chime if enabled
                if Defaults[.faceIDSound] {
                    NSSound(named: "Glass")?.play()
                }
                
                // Auto-fill password into SecurityAgent prompt
                if let passwordData = try? NotchPulseVault.readPassword(),
                   let password = String(data: passwordData, encoding: .utf8),
                   !password.isEmpty {
                    
                    // Inject keyboard events directly into SecurityAgent
                    DispatchQueue.global(qos: .userInteractive).async {
                        Self.injectSecurityAgentPassword(password)
                    }
                }
                
                // Show success animation briefly then dismiss
                try? await Task.sleep(for: .milliseconds(600))
            } else {
                // Not recognized or cancelled: Graceful fallback so user can use Touch ID or type manually
                try? await Task.sleep(for: .milliseconds(300))
            }
            
            LockScreenFaceIDWindow.shared.hide()
            self?.isCurrentlyVerifying = false
        }
    }
    
    nonisolated private static func injectSecurityAgentPassword(_ password: String) {
        let source = CGEventSource(stateID: .hidSystemState)
        
        // Ensure prompt field is active
        Thread.sleep(forTimeInterval: 0.08)
        
        // Clear existing input if any
        for _ in 0..<10 {
            if let delDown = CGEvent(keyboardEventSource: source, virtualKey: 0x33, keyDown: true),
               let delUp = CGEvent(keyboardEventSource: source, virtualKey: 0x33, keyDown: false) {
                delDown.flags = []
                delUp.flags = []
                delDown.post(tap: .cghidEventTap)
                delUp.post(tap: .cghidEventTap)
            }
            Thread.sleep(forTimeInterval: 0.005)
        }
        Thread.sleep(forTimeInterval: 0.02)
        
        // Type the password characters
        for char in password {
            if let keyInfo = NotchPulseFaceUnlockCoordinator.keyEventInfo(for: char) {
                if let down = CGEvent(keyboardEventSource: source, virtualKey: keyInfo.keyCode, keyDown: true),
                   let up = CGEvent(keyboardEventSource: source, virtualKey: keyInfo.keyCode, keyDown: false) {
                    if keyInfo.shift {
                        down.flags = .maskShift
                        up.flags = .maskShift
                    } else {
                        down.flags = []
                        up.flags = []
                    }
                    let utf16 = Array(String(char).utf16)
                    down.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
                    up.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
                    down.post(tap: .cghidEventTap)
                    Thread.sleep(forTimeInterval: 0.010)
                    up.post(tap: .cghidEventTap)
                    Thread.sleep(forTimeInterval: 0.010)
                }
            }
        }
        
        Thread.sleep(forTimeInterval: 0.05)
        
        // Press Return (virtualKey 0x24) to submit
        if let returnDown = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: true),
           let returnUp = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: false) {
            returnDown.flags = []
            returnUp.flags = []
            returnDown.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: 0.010)
            returnUp.post(tap: .cghidEventTap)
        }
    }
}
