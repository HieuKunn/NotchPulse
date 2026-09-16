//
//  SystemAuthPromptObserver.swift
//  NotchPulse
//
//  Created for NotchPulse v3.5 - System Authorization & Touch ID Prompt Interception
//  Event-driven observation of macOS SecurityAgent dialogs with 0% idle CPU overhead.
//

import AppKit
import ApplicationServices
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
    
    private static func isAuthAgent(_ app: NSRunningApplication) -> Bool {
        isAuthAgent(bundleId: app.bundleIdentifier)
    }
    
    private static func isAuthAgent(bundleId: String?) -> Bool {
        guard let bundleId = bundleId else { return false }
        return bundleId == "com.apple.SecurityAgent"
            || bundleId == "com.apple.coreservices.uiagent"
            || bundleId.contains("LocalAuthentication")
            || bundleId.contains("CoreAuthUI")
    }
    
    private func setupObserver() {
        // Event-driven: Only wakes up when an application changes focus
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleApplicationActivated(notification)
            }
            .store(in: &cancellables)
            
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didDeactivateApplicationNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleApplicationDeactivated(notification)
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
              Self.isAuthAgent(app) else {
            return
        }
        
        triggerFaceIDForAuthPrompt(targetApp: app)
    }
    
    private func handleApplicationDeactivated(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              Self.isAuthAgent(app) else {
            return
        }
        
        // If the authorization prompt was dismissed, cancel Face ID immediately
        if isCurrentlyVerifying {
            verificationTask?.cancel()
            verificationTask = nil
            FaceIDManager.shared.cancelCurrentSession()
            LockScreenFaceIDWindow.shared.isSystemPromptMode = false
            LockScreenFaceIDWindow.shared.hide()
            isCurrentlyVerifying = false
        }
    }
    
    private func triggerFaceIDForAuthPrompt(targetApp: NSRunningApplication) {
        guard !isCurrentlyVerifying else { return }
        isCurrentlyVerifying = true
        
        verificationTask?.cancel()
        verificationTask = Task { @MainActor [weak self] in
            // Allow SecurityAgent/LocalAuth window to settle in front
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else {
                self?.isCurrentlyVerifying = false
                return
            }
            
            // Present Face ID UI in the notch area
            LockScreenFaceIDWindow.shared.isSystemPromptMode = true
            LockScreenFaceIDWindow.shared.show()
            
            // Run dedicated system prompt face verification without lock screen requirements
            let verified = await FaceIDManager.shared.verifyForSystemPrompt(timeoutSeconds: 4.0)
            
            guard !Task.isCancelled else {
                LockScreenFaceIDWindow.shared.isSystemPromptMode = false
                LockScreenFaceIDWindow.shared.hide()
                self?.isCurrentlyVerifying = false
                return
            }
            
            if verified {
                // Safety check: Verify the auth agent is still frontmost before injecting credentials
                if let frontApp = NSWorkspace.shared.frontmostApplication,
                   Self.isAuthAgent(frontApp) {
                    
                    if let passwordData = try? NotchPulseVault.readPassword(),
                       let password = String(data: passwordData, encoding: .utf8),
                       !password.isEmpty {
                        
                        let isLocalAuth = frontApp.bundleIdentifier?.contains("LocalAuthentication") == true
                        let targetPid = frontApp.processIdentifier
                        
                        // Inject password on background thread
                        DispatchQueue.global(qos: .userInteractive).async {
                            if isLocalAuth {
                                Self.prepareLocalAuthenticationPasswordField(processIdentifier: targetPid)
                            }
                            Self.injectSecurityAgentPassword(password)
                        }
                    }
                }
                
                // Show success animation briefly then dismiss
                try? await Task.sleep(for: .milliseconds(600))
            } else {
                // Not recognized or timed out: Graceful fallback so user can use Touch ID or type manually
                try? await Task.sleep(for: .milliseconds(300))
            }
            
            LockScreenFaceIDWindow.shared.isSystemPromptMode = false
            LockScreenFaceIDWindow.shared.hide()
            self?.isCurrentlyVerifying = false
        }
    }
    
    nonisolated private static func prepareLocalAuthenticationPasswordField(processIdentifier: pid_t) {
        let axApp = AXUIElementCreateApplication(processIdentifier)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement], let win = windows.first else {
            return
        }
        
        func findPasswordButton(_ el: AXUIElement) -> AXUIElement? {
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(el, kAXTitleAttribute as CFString, &titleRef)
            if let title = titleRef as? String, title.contains("Password") {
                return el
            }
            var childrenRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &childrenRef) == .success,
               let children = childrenRef as? [AXUIElement] {
                for child in children {
                    if let found = findPasswordButton(child) { return found }
                }
            }
            return nil
        }
        
        if let btn = findPasswordButton(win) {
            _ = AXUIElementPerformAction(btn, kAXPressAction as CFString)
            Thread.sleep(forTimeInterval: 0.15)
        }
    }
    
    nonisolated private static func injectSecurityAgentPassword(_ password: String) {
        guard AXIsProcessTrusted() else {
            print("[SystemAuth] Cannot inject password: Accessibility permission not granted")
            return
        }
        
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
            } else {
                // Unicode fallback for special or international characters
                let utf16 = Array(String(char).utf16)
                if let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                   let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
                    down.flags = []
                    up.flags = []
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
            let returnUnicode: [UniChar] = [0x000D]
            returnDown.keyboardSetUnicodeString(stringLength: 1, unicodeString: returnUnicode)
            returnUp.keyboardSetUnicodeString(stringLength: 1, unicodeString: returnUnicode)
            returnDown.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: 0.010)
            returnUp.post(tap: .cghidEventTap)
        }
    }
}
