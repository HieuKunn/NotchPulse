//
//  NotchPulseSystemAuthCoordinator.swift
//  NotchPulse
//
//  Complete System Authorization, Terminal Quick-Auth & Apple Biometrics Integration.
//  Intercepts macOS SecurityAgent/installer prompts, supports Terminal & sudo Face ID,
//  and integrates Apple Touch ID / LocalAuthentication authority fallback.
//

import AppKit
import ApplicationServices
import LocalAuthentication
import Observation
import Defaults

@Observable
@MainActor
final class NotchPulseSystemAuthCoordinator: NSObject {
    static let shared = NotchPulseSystemAuthCoordinator()

    // MARK: - Observable State
    var isCurrentlyVerifying: Bool = false
    var statusMessage: String = "Ready"
    var isSudoTouchIDConfigured: Bool = false

    // MARK: - Internal Engine
    @ObservationIgnored private let settings = NotchPulseFaceIDSettings.shared
    @ObservationIgnored private let camera = NotchPulseCamera()
    @ObservationIgnored private let pipeline = NotchPulseFaceRecognitionPipeline()
    @ObservationIgnored private var verificationTask: Task<Void, Never>?
    @ObservationIgnored private var workspaceObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var promptDetectionTimer: Timer?
    @ObservationIgnored private var lastPromptPid: pid_t = 0
    @ObservationIgnored private var lastPromptTimestamp: Date = .distantPast

    override private init() {
        super.init()
        refreshSudoTouchIDStatus()
    }

    deinit {
        promptDetectionTimer?.invalidate()
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    // MARK: - Workspace Observers (SecurityAgent & System Prompts)

    private var cachedHasPasswordTimestamp: Date = .distantPast
    private var cachedHasPassword: Bool = false
    
    private func hasStoredPasswordCached() -> Bool {
        if Date().timeIntervalSince(cachedHasPasswordTimestamp) > 5.0 {
            cachedHasPassword = NotchPulseVault.hasStoredPassword()
            cachedHasPasswordTimestamp = Date()
        }
        return cachedHasPassword
    }

    func updatePromptTimerState() {
        let shouldPoll = settings.isSystemAuthFaceIDEnabled
            && NotchPulseFaceEnrollmentStore.shared.hasEnrolledFace
            && hasStoredPasswordCached()
            
        if shouldPoll {
            if promptDetectionTimer == nil {
                promptDetectionTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.checkOnScreenAuthPrompts()
                    }
                }
            }
        } else {
            promptDetectionTimer?.invalidate()
            promptDetectionTimer = nil
        }
    }

    func startObserving() {
        stopObserving()

        let nc = NSWorkspace.shared.notificationCenter

        let activated = nc.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            Task { @MainActor [weak self] in
                self?.handleAppNotification(note)
            }
        }

        let launched = nc.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            Task { @MainActor [weak self] in
                self?.handleAppNotification(note)
            }
        }

        let deactivated = nc.addObserver(
            forName: NSWorkspace.didDeactivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            Task { @MainActor [weak self] in
                self?.handleDeactivation(note)
            }
        }

        workspaceObservers = [activated, launched, deactivated]

        // Active prompt polling: CoreAuthUI & SecurityAgent only polled when feature is active
        updatePromptTimerState()
    }

    func stopObserving() {
        promptDetectionTimer?.invalidate()
        promptDetectionTimer = nil
        verificationTask?.cancel()
        verificationTask = nil
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        workspaceObservers.removeAll()
        isCurrentlyVerifying = false
    }

    // MARK: - Identification Helpers

    static func isAuthAgentName(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.contains("securityagent")
            || lower.contains("coreauthui")
            || lower.contains("localauthentication")
            || lower.contains("authorization")
            || lower.contains("coreservices.uiagent")
    }

    static func isAuthAgent(_ app: NSRunningApplication?) -> Bool {
        guard let app else { return false }
        if let bundleId = app.bundleIdentifier?.lowercased() {
            return bundleId.contains("securityagent")
                || bundleId.contains("coreauthui")
                || bundleId.contains("localauthentication")
                || bundleId.contains("authenticationservices")
                || bundleId.contains("credential")
                || bundleId.contains("coreservices.uiagent")
                || bundleId == "com.apple.cryptotokenkit.pkitoken"
        }
        // Avoid calling app.localizedName if bundleIdentifier exists (prevents LaunchServices XPC storms)
        if app.bundleIdentifier == nil, let localizedName = app.localizedName {
            if isAuthAgentName(localizedName) {
                return true
            }
        }
        return false
    }

    static func isTerminalApp(_ app: NSRunningApplication?) -> Bool {
        guard let id = app?.bundleIdentifier?.lowercased() else { return false }
        return id.contains("terminal")
            || id.contains("iterm")
            || id.contains("warp")
            || id.contains("alacritty")
            || id.contains("kitty")
            || id.contains("hyper")
            || id.contains("ghostty")
            || id.contains("vscode")
            || id.contains("cursor")
    }

    // MARK: - Active Window Polling

    private func checkOnScreenAuthPrompts() {
        guard settings.isSystemAuthFaceIDEnabled,
              NotchPulseFaceEnrollmentStore.shared.hasEnrolledFace,
              hasStoredPasswordCached(),
              !isCurrentlyVerifying else {
            updatePromptTimerState()
            return
        }

        // Check on-screen window list for SecurityAgent or CoreAuthUI
        if let windowInfoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
            for win in windowInfoList {
                guard let ownerName = win[kCGWindowOwnerName as String] as? String,
                      let ownerPid = win[kCGWindowOwnerPID as String] as? pid_t else {
                    continue
                }

                if Self.isAuthAgentName(ownerName) {
                    if let boundsDict = win[kCGWindowBounds as String] as? [String: Any],
                       let w = boundsDict["Width"] as? CGFloat,
                       let h = boundsDict["Height"] as? CGFloat,
                       w > 50, h > 50 {
                        if ownerPid != lastPromptPid || Date().timeIntervalSince(lastPromptTimestamp) > 3.0 {
                            lastPromptPid = ownerPid
                            lastPromptTimestamp = Date()
                            if let runningApp = NSRunningApplication(processIdentifier: ownerPid) {
                                authenticateForSystemPrompt(targetApp: runningApp)
                            }
                            return
                        }
                    }
                }
            }
        }

        // Check frontmost application directly in O(1) without iterating all running applications
        if let frontApp = NSWorkspace.shared.frontmostApplication, Self.isAuthAgent(frontApp) {
            let pid = frontApp.processIdentifier
            if pid != lastPromptPid || Date().timeIntervalSince(lastPromptTimestamp) > 3.0 {
                lastPromptPid = pid
                lastPromptTimestamp = Date()
                authenticateForSystemPrompt(targetApp: frontApp)
                return
            }
        }
    }

    // MARK: - Notification Handlers

    private func handleAppNotification(_ notification: Notification) {
        guard settings.isSystemAuthFaceIDEnabled,
              NotchPulseFaceEnrollmentStore.shared.hasEnrolledFace,
              hasStoredPasswordCached() else {
            return
        }

        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              Self.isAuthAgent(app) else {
            return
        }

        authenticateForSystemPrompt(targetApp: app)
    }

    private func handleDeactivation(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              Self.isAuthAgent(app) else {
            return
        }

        if isCurrentlyVerifying {
            cancelVerification()
        }
    }

    func cancelVerification() {
        verificationTask?.cancel()
        verificationTask = nil
        camera.stop()
        FaceIDOverlayController.shared.disarm()
        isCurrentlyVerifying = false
        statusMessage = "Cancelled"
    }

    // MARK: - System Prompt Authorization

    func authenticateForSystemPrompt(targetApp: NSRunningApplication) {
        guard !isCurrentlyVerifying else { return }
        isCurrentlyVerifying = true

        verificationTask?.cancel()
        verificationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            // Let SecurityAgent settle into focus
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else {
                self.isCurrentlyVerifying = false
                return
            }

            self.statusMessage = "Verifying with Face ID for system prompt…"
            let verified = await self.runFaceVerification(promptTitle: "System Authorization")

            guard !Task.isCancelled else {
                self.isCurrentlyVerifying = false
                return
            }

            if verified {
                self.statusMessage = "Authorized"
                FaceIDOverlayController.shared.finish(success: true)
                try? await Task.sleep(for: .milliseconds(150))
                await self.injectStoredPassword(into: targetApp)
            } else {
                self.statusMessage = "Face ID not recognized"
                FaceIDOverlayController.shared.finish(success: false)
            }

            self.isCurrentlyVerifying = false
        }
    }

    // MARK: - Terminal & Quick-Auth Trigger

    func triggerQuickAuth() {
        let frontApp = NSWorkspace.shared.frontmostApplication
        authenticateForTerminalOrActiveField(targetApp: frontApp)
    }

    func authenticateForTerminalOrActiveField(targetApp: NSRunningApplication?) {
        guard !isCurrentlyVerifying else { return }
        guard NotchPulseFaceEnrollmentStore.shared.hasEnrolledFace,
              NotchPulseVault.hasStoredPassword() else {
            NSSound.beep()
            return
        }

        isCurrentlyVerifying = true
        verificationTask?.cancel()

        verificationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            self.statusMessage = "Verifying Face ID for password entry…"

            let verified = await self.runFaceVerification(promptTitle: "Password Verification")

            guard !Task.isCancelled else {
                self.isCurrentlyVerifying = false
                return
            }

            if verified {
                self.statusMessage = "Password Injected"
                await self.injectStoredPassword(into: targetApp)
            } else if self.settings.useAppleAuthFallback {
                self.statusMessage = "Face ID unconfirmed — Apple Biometrics fallback…"
                let appleVerified = await self.authenticateWithAppleBiometrics(reason: "Authorize Password Quick-Auth")
                if appleVerified {
                    self.statusMessage = "Authorized via Apple Biometrics"
                    await self.injectStoredPassword(into: targetApp)
                } else {
                    self.statusMessage = "Quick-Auth cancelled"
                }
            } else {
                self.statusMessage = "Face not recognized"
            }

            self.isCurrentlyVerifying = false
        }
    }

    // MARK: - Core Face Verification Loop with Notch Overlay

    private func runFaceVerification(promptTitle: String) async -> Bool {
        FaceIDOverlayController.shared.present()

        await camera.start()
        defer {
            camera.stop()
        }

        let timeoutSeconds: Double = Double(settings.faceDetectionSeconds)
        let startTime = ContinuousClock.now
        let threshold = settings.matchThreshold
        var lastProcessedFrameID: UInt64?

        let liveness = NotchPulseLivenessAnalyzer()
        liveness.modeProvider = { [weak self] in self?.settings.livenessMode ?? .light }
        var livenessConfirmed = !settings.livenessChecksEnabled

        while ContinuousClock.now - startTime < .seconds(timeoutSeconds), !Task.isCancelled {
            guard let frame = camera.currentFrame, frame.id != lastProcessedFrameID else {
                try? await Task.sleep(for: .milliseconds(20))
                continue
            }
            lastProcessedFrameID = frame.id

            let pipeline = self.pipeline
            let outcome = await Task.detached(priority: .userInitiated) { () -> (FaceRecognitionResult, LivenessFrame)? in
                guard let result = try? pipeline.recognize(in: frame.image) else { return nil }
                let faceCrop = NotchPulseCamera.renderCrop(from: frame, imageRect: result.face.boundingBox)
                return (result, NotchPulseLivenessFeatures.extract(from: result, frame: frame.image, faceCrop: faceCrop))
            }.value

            guard let (result, livenessFrame) = outcome else {
                try? await Task.sleep(for: .milliseconds(20))
                continue
            }

            if settings.livenessChecksEnabled {
                let snapshot = liveness.observe(livenessFrame)
                if case .denied(let cue) = snapshot.decision {
                    print("[SystemAuth] Liveness rejected: \(cue)")
                    try? await Task.sleep(for: .milliseconds(80))
                    continue
                } else if snapshot.decision.isConfirmed {
                    livenessConfirmed = true
                }
            }

            let activeIdentities = NotchPulseFaceEnrollmentStore.shared.activeIdentities
            guard !activeIdentities.isEmpty else {
                FaceIDOverlayController.shared.finish(success: false)
                return false
            }

            let scored = pipeline.score(result.embedding, against: activeIdentities)
            if let _ = pipeline.bestMatch(in: scored, threshold: threshold) {
                if !livenessConfirmed {
                    try? await Task.sleep(for: .milliseconds(30))
                    continue
                }

                FaceIDOverlayController.shared.finish(success: true)
                if Defaults[.faceIDSound] {
                    NSSound(named: "Glass")?.play()
                }
                return true
            }

            try? await Task.sleep(for: .milliseconds(25))
        }

        FaceIDOverlayController.shared.finish(success: false)
        return false
    }

    // MARK: - Apple Biometrics & Authority Fallback

    func authenticateWithAppleBiometrics(reason: String) async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        var error: NSError?

        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            do {
                return try await context.evaluatePolicy(
                    .deviceOwnerAuthenticationWithBiometrics,
                    localizedReason: reason
                )
            } catch {
                print("[SystemAuth] Biometrics error: \(error.localizedDescription)")
            }
        }

        // Fallback to system password / Apple Watch / Touch ID
        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            do {
                return try await context.evaluatePolicy(
                    .deviceOwnerAuthentication,
                    localizedReason: reason
                )
            } catch {
                print("[SystemAuth] Device owner authentication error: \(error.localizedDescription)")
            }
        }

        return false
    }

    // MARK: - Password Injection

    private func injectStoredPassword(into targetApp: NSRunningApplication?) async {
        guard KeystrokeInjector.isAccessibilityTrusted() else {
            KeystrokeInjector.promptForAccessibility()
            return
        }

        guard let passwordData = try? NotchPulseVault.readPassword(),
              !passwordData.isEmpty else {
            return
        }

        if let app = targetApp {
            app.activate(options: [.activateIgnoringOtherApps])
            let bundle = app.bundleIdentifier ?? ""
            let requiresPasswordButton = bundle.localizedCaseInsensitiveContains("LocalAuthentication")
                || bundle.localizedCaseInsensitiveContains("CoreAuthUI")
                || bundle.localizedCaseInsensitiveContains("AuthenticationServices")
                || bundle.localizedCaseInsensitiveContains("coreservices.uiagent")
            if requiresPasswordButton {
                let targetPid = app.processIdentifier
                prepareLocalAuthenticationPasswordField(processIdentifier: targetPid)
                try? await Task.sleep(for: .milliseconds(350))
            } else {
                try? await Task.sleep(for: .milliseconds(120))
            }
        } else {
            try? await Task.sleep(for: .milliseconds(80))
        }

        try? KeystrokeInjector.typeAndReturn(passwordData)
    }

    nonisolated private func prepareLocalAuthenticationPasswordField(processIdentifier: pid_t) {
        let axApp = AXUIElementCreateApplication(processIdentifier)
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
        guard let win else { return }

        func findPasswordButton(_ el: AXUIElement) -> AXUIElement? {
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(el, kAXTitleAttribute as CFString, &titleRef)
            if let title = titleRef as? String {
                let lower = title.lowercased()
                if lower.contains("password") || lower.contains("passcode") || lower.contains("mật khẩu") || lower.contains("use password") || lower.contains("sử dụng mật khẩu") {
                    return el
                }
            }
            var descRef: CFTypeRef?
            AXUIElementCopyAttributeValue(el, kAXDescriptionAttribute as CFString, &descRef)
            if let desc = descRef as? String {
                let lower = desc.lowercased()
                if lower.contains("password") || lower.contains("passcode") || lower.contains("mật khẩu") || lower.contains("use password") || lower.contains("sử dụng mật khẩu") {
                    return el
                }
            }
            var idRef: CFTypeRef?
            AXUIElementCopyAttributeValue(el, kAXIdentifierAttribute as CFString, &idRef)
            if let ident = idRef as? String {
                let lower = ident.lowercased()
                if lower.contains("password") || lower.contains("usepassword") {
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

        if let btn = findPasswordButton(win) {
            _ = AXUIElementPerformAction(btn, kAXPressAction as CFString)
        }
    }

    // MARK: - PAM Sudo Touch ID Configuration

    func refreshSudoTouchIDStatus() {
        let path = "/etc/pam.d/sudo_local"
        guard FileManager.default.fileExists(atPath: path),
              let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            isSudoTouchIDConfigured = false
            return
        }

        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.hasPrefix("#") && trimmed.contains("pam_tid.so") {
                isSudoTouchIDConfigured = true
                return
            }
        }
        isSudoTouchIDConfigured = false
    }

    func enableSudoTouchID() async -> Bool {
        let script = """
        do shell script "if [ ! -f /etc/pam.d/sudo_local ]; then cp /etc/pam.d/sudo_local.template /etc/pam.d/sudo_local; fi && grep -q 'pam_tid.so' /etc/pam.d/sudo_local && sed -i '' 's/^#auth[[:space:]]*sufficient[[:space:]]*pam_tid.so/auth       sufficient     pam_tid.so/' /etc/pam.d/sudo_local || echo 'auth       sufficient     pam_tid.so' >> /etc/pam.d/sudo_local" with administrator privileges
        """

        let appleScript = NSAppleScript(source: script)
        var errorDict: NSDictionary?
        _ = appleScript?.executeAndReturnError(&errorDict)

        refreshSudoTouchIDStatus()
        return isSudoTouchIDConfigured
    }
}
