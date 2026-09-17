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
            || bundleId.contains("AuthenticationServices")
            || bundleId.contains("Credential")
            || bundleId == "com.apple.CryptoTokenKit.pkitoken"
    }
    
    private func setupObserver() {
        // Event-driven: Wakes up when application focus changes or an auth agent launches
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleApplicationActivated(notification)
            }
            .store(in: &cancellables)
            
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)
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
            let verified = await FaceIDManager.shared.verifyForSystemPrompt(timeoutSeconds: 6.0)
            
            guard !Task.isCancelled else {
                LockScreenFaceIDWindow.shared.isSystemPromptMode = false
                LockScreenFaceIDWindow.shared.hide()
                self?.isCurrentlyVerifying = false
                return
            }
            
            if verified {
                // Safety check: Find active auth agent to inject credentials
                let targetAppToInject: NSRunningApplication? = {
                    if let frontApp = NSWorkspace.shared.frontmostApplication, Self.isAuthAgent(frontApp) {
                        return frontApp
                    }
                    if Self.isAuthAgent(targetApp) {
                        return targetApp
                    }
                    return NSWorkspace.shared.runningApplications.first(where: { Self.isAuthAgent($0) })
                }()
                
                if let authApp = targetAppToInject {
                    authApp.activate(options: [.activateIgnoringOtherApps])
                    
                    if let passwordData = try? NotchPulseVault.readPassword(),
                       let password = String(data: passwordData, encoding: .utf8),
                       !password.isEmpty {
                        
                        let bundle = authApp.bundleIdentifier ?? ""
                        let requiresPasswordButton = bundle.contains("LocalAuthentication")
                            || bundle.contains("CoreAuthUI")
                            || bundle.contains("AuthenticationServices")
                            || bundle.contains("coreservices.uiagent")
                        let targetPid = authApp.processIdentifier
                        
                        // Inject password on background thread
                        DispatchQueue.global(qos: .userInteractive).async {
                            if requiresPasswordButton {
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
        
        // Poll for window to appear (max 2s, 50ms intervals)
        var win: AXUIElement?
        let windowPollStart = Date()
        while Date().timeIntervalSince(windowPollStart) < 2.0 {
            var windowsRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
               let windows = windowsRef as? [AXUIElement], let firstWin = windows.first {
                win = firstWin
                break
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        guard let win else {
            print("[SystemAuth] No window found for auth agent within 2s")
            return
        }
        
        func findPasswordButton(_ el: AXUIElement) -> AXUIElement? {
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(el, kAXTitleAttribute as CFString, &titleRef)
            if let title = titleRef as? String {
                let lower = title.lowercased()
                if lower.contains("password") || lower.contains("passcode") || lower.contains("mật khẩu") || lower.contains("use password") {
                    return el
                }
            }
            var descRef: CFTypeRef?
            AXUIElementCopyAttributeValue(el, kAXDescriptionAttribute as CFString, &descRef)
            if let desc = descRef as? String {
                let lower = desc.lowercased()
                if lower.contains("password") || lower.contains("passcode") || lower.contains("mật khẩu") || lower.contains("use password") {
                    return el
                }
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
        
        func findPasswordField(_ el: AXUIElement) -> Bool {
            var roleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &roleRef)
            if let role = roleRef as? String, role == kAXTextFieldRole || role == "AXSecureTextField" {
                return true
            }
            var childrenRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &childrenRef) == .success,
               let children = childrenRef as? [AXUIElement] {
                for child in children {
                    if findPasswordField(child) { return true }
                }
            }
            return false
        }
        
        if let btn = findPasswordButton(win) {
            // Retry button click up to 3 times with 200ms intervals
            for attempt in 1...3 {
                _ = AXUIElementPerformAction(btn, kAXPressAction as CFString)
                
                // Poll for password field to appear (max 1.5s, 50ms intervals)
                let pollStart = Date()
                var fieldFound = false
                while Date().timeIntervalSince(pollStart) < 1.5 {
                    if findPasswordField(win) {
                        fieldFound = true
                        break
                    }
                    Thread.sleep(forTimeInterval: 0.05)
                }
                
                if fieldFound {
                    print("[SystemAuth] Password field appeared after button click attempt \(attempt)")
                    return
                }
                
                if attempt < 3 {
                    print("[SystemAuth] Password field not found after button click attempt \(attempt), retrying...")
                    Thread.sleep(forTimeInterval: 0.2)
                }
            }
            print("[SystemAuth] Password field did not appear after 3 button click attempts — falling back to keyboard injection")
        }
    }
    
    nonisolated private static func injectSecurityAgentPassword(_ password: String) {
        guard AXIsProcessTrusted() else {
            print("[SystemAuth] Cannot inject password: Accessibility permission not granted")
            return
        }
        
        let source = CGEventSource(stateID: .hidSystemState)
        
        // Adaptive wait: poll for keyboard focus readiness (max 500ms, 50ms intervals)
        let focusPollStart = Date()
        var focusReady = false
        while Date().timeIntervalSince(focusPollStart) < 0.5 {
            // Send a harmless mouse move to wake the event system
            let mouseLoc = CGEvent(source: nil)?.location ?? CGPoint(x: 500, y: 500)
            if let moveEvent = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: CGPoint(x: mouseLoc.x, y: mouseLoc.y), mouseButton: .left) {
                moveEvent.post(tap: .cghidEventTap)
            }
            // Check if we can create keyboard events (indicates event system is responsive)
            if CGEvent(keyboardEventSource: source, virtualKey: 0x33, keyDown: true) != nil {
                focusReady = true
                break
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        
        if !focusReady {
            print("[SystemAuth] Warning: keyboard focus may not be ready, proceeding anyway")
        }
        
        // Small settle delay after focus confirmed
        Thread.sleep(forTimeInterval: 0.03)
        
        // Clear existing input if any
        for _ in 0..<10 {
            if let delDown = CGEvent(keyboardEventSource: source, virtualKey: 0x33, keyDown: true),
               let delUp = CGEvent(keyboardEventSource: source, virtualKey: 0x33, keyDown: false) {
                delDown.flags = []
                delUp.flags = []
                delDown.post(tap: .cghidEventTap)
                delUp.post(tap: .cghidEventTap)
            }
            Thread.sleep(forTimeInterval: 0.008)
        }
        Thread.sleep(forTimeInterval: 0.02)
        
        // Type the password characters with adaptive inter-key delay
        let interKeyDelay: TimeInterval = 0.012
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
                    Thread.sleep(forTimeInterval: interKeyDelay)
                    up.post(tap: .cghidEventTap)
                    Thread.sleep(forTimeInterval: interKeyDelay)
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
                    Thread.sleep(forTimeInterval: interKeyDelay)
                    up.post(tap: .cghidEventTap)
                    Thread.sleep(forTimeInterval: interKeyDelay)
                }
            }
        }
        
        // Settle before submitting
        Thread.sleep(forTimeInterval: 0.06)
        
        // Press Return (virtualKey 0x24) to submit
        if let returnDown = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: true),
           let returnUp = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: false) {
            returnDown.flags = []
            returnUp.flags = []
            let returnUnicode: [UniChar] = [0x000D]
            returnDown.keyboardSetUnicodeString(stringLength: 1, unicodeString: returnUnicode)
            returnUp.keyboardSetUnicodeString(stringLength: 1, unicodeString: returnUnicode)
            returnDown.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: 0.015)
            returnUp.post(tap: .cghidEventTap)
        }
        
        print("[SystemAuth] Password injection completed")
    }
}
