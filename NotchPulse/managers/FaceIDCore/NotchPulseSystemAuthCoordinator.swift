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
    @ObservationIgnored private var distributedObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var promptDetectionTimer: Timer?
    @ObservationIgnored private var promptCooldowns: [pid_t: Date] = [:]
    @ObservationIgnored private var globalLastPromptDate: Date = .distantPast
    @ObservationIgnored private var lastPromptPid: pid_t = 0
    @ObservationIgnored private var lastPromptTimestamp: Date = .distantPast

    private func shouldHandlePrompt(pid: pid_t) -> Bool {
        let now = Date()
        // Global throttle: at least 2.5 seconds between any two prompt authentications
        if now.timeIntervalSince(globalLastPromptDate) < 2.5 {
            return false
        }
        // Per-PID throttle: do not re-prompt the same PID within 8 seconds
        if let lastDate = promptCooldowns[pid], now.timeIntervalSince(lastDate) < 8.0 {
            return false
        }
        return true
    }

    private func recordPromptAttempt(pid: pid_t) {
        let now = Date()
        promptCooldowns[pid] = now
        globalLastPromptDate = now
        lastPromptPid = pid
        lastPromptTimestamp = now
    }

    override private init() {
        super.init()
        refreshSudoTouchIDStatus()
    }

    deinit {
        promptDetectionTimer?.invalidate()
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        for observer in distributedObservers {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
    }

    // MARK: - Workspace Observers (SecurityAgent & System Prompts)

    func updatePromptTimerState() {
        let shouldPoll = !NotchPulseLockMonitor.isScreenActuallyLocked()
            && settings.isSystemAuthFaceIDEnabled
            && NotchPulseFaceEnrollmentStore.shared.hasEnrolledFace
            && NotchPulseVault.isSessionUnlocked
            
        if shouldPoll {
            if promptDetectionTimer == nil {
                let timer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.checkOnScreenAuthPrompts()
                    }
                }
                timer.tolerance = 0.5
                promptDetectionTimer = timer
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

        let dist = DistributedNotificationCenter.default()
        let lockObs = dist.addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                if self?.isCurrentlyVerifying == true {
                    self?.cancelVerification()
                }
                self?.updatePromptTimerState()
            }
        }
        let unlockObs = dist.addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updatePromptTimerState()
            }
        }
        distributedObservers = [lockObs, unlockObs]

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
        for observer in distributedObservers {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        distributedObservers.removeAll()
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
                || bundleId.contains("coreservices.uiagent")
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
        guard !NotchPulseLockMonitor.isScreenActuallyLocked(),
              settings.isSystemAuthFaceIDEnabled,
              NotchPulseFaceEnrollmentStore.shared.hasEnrolledFace,
              NotchPulseVault.isSessionUnlocked,
              !isCurrentlyVerifying else {
            updatePromptTimerState()
            return
        }

        // Fast check 1: Check frontmost application directly in O(1)
        if let frontApp = NSWorkspace.shared.frontmostApplication, Self.isAuthAgent(frontApp) {
            let pid = frontApp.processIdentifier
            if shouldHandlePrompt(pid: pid) {
                recordPromptAttempt(pid: pid)
                authenticateForSystemPrompt(targetApp: frontApp)
            }
            return
        }

        // Fast check 2: Only enumerate CGWindowList if an auth agent is actually running in the system
        let isAuthRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.SecurityAgent").isEmpty
            || !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.CoreAuthUI").isEmpty
        guard isAuthRunning else {
            lastPromptPid = 0
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
                        if shouldHandlePrompt(pid: ownerPid) {
                            recordPromptAttempt(pid: ownerPid)
                            if let runningApp = NSRunningApplication(processIdentifier: ownerPid) {
                                authenticateForSystemPrompt(targetApp: runningApp)
                            }
                            return
                        }
                    }
                }
            }
        }
    }

    // MARK: - Notification Handlers

    private func handleAppNotification(_ notification: Notification) {
        guard !NotchPulseLockMonitor.isScreenActuallyLocked(),
              settings.isSystemAuthFaceIDEnabled,
              NotchPulseFaceEnrollmentStore.shared.hasEnrolledFace,
              NotchPulseVault.isSessionUnlocked else {
            return
        }

        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              Self.isAuthAgent(app) else {
            return
        }

        let pid = app.processIdentifier
        if shouldHandlePrompt(pid: pid) {
            recordPromptAttempt(pid: pid)
            authenticateForSystemPrompt(targetApp: app)
        }
    }

    private func handleDeactivation(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              Self.isAuthAgent(app) else {
            return
        }

        // Only clear tracking when the application is actually terminated, preventing focus-change infinite loops
        if app.isTerminated {
            lastPromptPid = 0
            promptCooldowns.removeValue(forKey: app.processIdentifier)
        }

        if isCurrentlyVerifying {
            cancelVerification()
        }
    }

    func cancelVerification() {
        verificationTask?.cancel()
        verificationTask = nil
        camera.stop()
        if FaceIDOverlayController.shared.isPresenting && !FaceIDOverlayController.shared.isArmed {
            FaceIDOverlayController.shared.dismissImmediately()
        }
        isCurrentlyVerifying = false
        statusMessage = "Cancelled"
    }

    // MARK: - System Prompt Authorization

    func authenticateForSystemPrompt(targetApp: NSRunningApplication) {
        guard !NotchPulseLockMonitor.isScreenActuallyLocked() else { return }
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
        guard !NotchPulseLockMonitor.isScreenActuallyLocked() else { return false }

        // Fetch active enrolled identities ONCE up front to avoid querying Keychain on the MainActor per-frame
        var activeIdentities = NotchPulseFaceEnrollmentStore.shared.activeIdentities
        if activeIdentities.isEmpty {
            if let directLoaded = try? NotchPulseSecureFaceStore.load(), !directLoaded.isEmpty {
                activeIdentities = directLoaded.filter(\.isEnabled)
            }
        }
        guard !activeIdentities.isEmpty else {
            print("[SystemAuth] No enrolled face identities available for verification.")
            FaceIDOverlayController.shared.finish(success: false)
            return false
        }

        FaceIDOverlayController.shared.present()

        // Pre-warm ArcFace CoreML model in background concurrently while camera hardware starts up
        ArcFaceEmbedder.warmUp()
        await camera.start()
        defer {
            camera.stop()
        }

        let timeoutSeconds: Double = Double(settings.faceDetectionSeconds)
        let threshold = settings.matchThreshold
        var lastProcessedFrameID: UInt64?
        var lastFaceBoundingBox: CGRect?
        var consecutiveWrongFaceFrames = 0
        let wrongFaceStreakThreshold = 20
        var readyMatch: ScoredIdentity?
        var readyMatchTime: ContinuousClock.Instant?

        let liveness = NotchPulseLivenessAnalyzer()
        liveness.modeProvider = { [weak self] in self?.settings.livenessMode ?? .light }
        var livenessConfirmed = !settings.livenessChecksEnabled

        let windowDuration = Duration.seconds(timeoutSeconds)
        let firstFrameCap = ContinuousClock.now + .seconds(8)
        var effectiveDeadline = ContinuousClock.now + windowDuration
        var firstFrameSeen = false
        var scanStartTime: ContinuousClock.Instant?

        while ContinuousClock.now < effectiveDeadline, !Task.isCancelled {
            guard !NotchPulseLockMonitor.isScreenActuallyLocked() else {
                FaceIDOverlayController.shared.finish(success: false)
                return false
            }

            guard let frame = camera.currentFrame, frame.id != lastProcessedFrameID else {
                if !firstFrameSeen {
                    if ContinuousClock.now > firstFrameCap { break }
                    effectiveDeadline = ContinuousClock.now + windowDuration
                }
                try? await Task.sleep(for: .milliseconds(20))
                continue
            }
            if !firstFrameSeen {
                firstFrameSeen = true
                scanStartTime = ContinuousClock.now
                effectiveDeadline = ContinuousClock.now + windowDuration
            }
            lastProcessedFrameID = frame.id

            let pipeline = self.pipeline
            let previousBoundingBox = lastFaceBoundingBox
            let outcome = await Task.detached(priority: .userInitiated) { () -> (FaceRecognitionResult, LivenessFrame)? in
                guard let result = try? pipeline.recognize(
                    in: frame.image,
                    preferNear: previousBoundingBox
                ) else { return nil }
                let faceCrop = NotchPulseCamera.renderCrop(from: frame, imageRect: result.face.boundingBox)
                return (result, NotchPulseLivenessFeatures.extract(from: result, frame: frame.image, faceCrop: faceCrop))
            }.value

            guard let (result, livenessFrame) = outcome else {
                readyMatch = nil
                readyMatchTime = nil
                consecutiveWrongFaceFrames = 0
                lastFaceBoundingBox = nil
                try? await Task.sleep(for: .milliseconds(20))
                continue
            }
            lastFaceBoundingBox = result.face.normalizedBoundingBox

            if settings.livenessChecksEnabled {
                let snapshot = liveness.observe(livenessFrame)
                if case .denied(let cue) = snapshot.decision {
                    print("[SystemAuth] Liveness rejected: \(cue)")
                    FaceIDOverlayController.shared.finish(success: false)
                    return false
                } else if snapshot.decision.isConfirmed {
                    livenessConfirmed = true
                }
            }

            let scored = pipeline.score(result.embedding, against: activeIdentities)
            let matched = pipeline.bestMatch(in: scored, threshold: threshold)

            let isWarmingUp = scanStartTime.map { ContinuousClock.now - $0 < .milliseconds(1200) } ?? true

            if let matched {
                consecutiveWrongFaceFrames = 0
                readyMatch = matched
                readyMatchTime = ContinuousClock.now
            } else {
                if !isWarmingUp {
                    consecutiveWrongFaceFrames += 1
                }
                if consecutiveWrongFaceFrames >= 3 {
                    readyMatch = nil
                    readyMatchTime = nil
                }
                if consecutiveWrongFaceFrames >= wrongFaceStreakThreshold {
                    FaceIDOverlayController.shared.finish(success: false)
                    return false
                }
            }

            let candidateMatch = matched ?? (readyMatchTime.map { ContinuousClock.now - $0 < .milliseconds(400) } == true ? readyMatch : nil)

            if let _ = candidateMatch, livenessConfirmed {
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

        // Read password off the MainActor to guarantee zero UI hitching
        guard let passwordData = await Task.detached(priority: .userInitiated, operation: {
            try? NotchPulseVault.readPassword()
        }).value, !passwordData.isEmpty else {
            return
        }

        if let app = targetApp {
            app.activate()
            let bundle = app.bundleIdentifier ?? ""
            let bundleLower = bundle.lowercased()
            let requiresPasswordButton = bundleLower.contains("localauthentication")
                || bundleLower.contains("coreauthui")
                || bundleLower.contains("authenticationservices")
                || bundleLower.contains("coreservices.uiagent")
            if requiresPasswordButton {
                let targetPid = app.processIdentifier
                await Task.detached(priority: .userInitiated) {
                    Self.prepareLocalAuthenticationPasswordField(processIdentifier: targetPid)
                }.value
                try? await Task.sleep(for: .milliseconds(350))
            } else {
                try? await Task.sleep(for: .milliseconds(120))
            }
        } else {
            try? await Task.sleep(for: .milliseconds(80))
        }

        await Task.detached(priority: .userInitiated) {
            try? KeystrokeInjector.typeAndReturn(passwordData)
        }.value
    }

    nonisolated private static func prepareLocalAuthenticationPasswordField(processIdentifier: pid_t) {
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
