import Foundation
import CoreGraphics
import Observation

@Observable
@MainActor
final class NotchPulseFaceUnlockCoordinator {
    static let shared = NotchPulseFaceUnlockCoordinator(pocController: NotchPulsePOCController.shared)
    
    private let pocController: NotchPulsePOCController
    let lockMonitor = NotchPulseLockMonitor()
    let camera = NotchPulseCamera()
    let pipeline = NotchPulseFaceRecognitionPipeline()

    /// Persisted via NotchPulseFaceIDSettings. Setting to false cancels any in-flight scan and disarms the overlay immediately.
    var isEnabled: Bool {
        didSet {
            NotchPulseFaceIDSettings.shared.isFaceUnlockEnabled = isEnabled
            if !isEnabled { disarmOverlay() }
        }
    }

    /// Kept independent from Face Lab's own `threshold` so tuning the debug tool never silently changes the real unlock gate.
    var matchThreshold: Float {
        didSet { NotchPulseFaceIDSettings.shared.matchThreshold = matchThreshold }
    }
    /// Shares its setting with FaceIDOverlayController's scanning timeout, so the background loop stops in step with the UI collapsing.
    private var scanWindowDuration: TimeInterval {
        TimeInterval(NotchPulseFaceIDSettings.shared.faceDetectionSeconds)
    }

    private(set) var statusMessage = "Idle"
    private(set) var lastOutcome: String?

    private var hasArmedForCurrentLock = false
    /// One-shot per lock session — an auto-retry that could itself auto-retry would loop the camera for the whole lock session.
    private var hasAutoRetriedForCurrentLock = false
    private var scanTask: Task<Void, Never>?
    /// Bumped by every `startScanCycle()`; a cycle bails once superseded (see `runScanCycle(generation:)`).
    private var scanGeneration = 0
    /// When the last scan cycle was armed — collapses a single wake into a single arm (see `.wake` branch of `evaluateTrigger`).
    private var lastArmedAt: ContinuousClock.Instant?
    /// One lid-open fires several wake signals within a couple of seconds of each other; anything in this window counts as the same wake.
    private let rearmDebounce: Duration = .seconds(2)
    /// Held separately from `scanTask` since it's scheduled from inside the scan task it follows — reusing `scanTask` would self-cancel it.
    private var autoRetryTask: Task<Void, Never>?
    /// Gap between headless auto-retries, just to keep the camera from restarting in a tight loop.
    private let headlessRetryDelay: Duration = .seconds(1)

    /// When off, no notch/pill presence at all — every overlay call in this file is conditioned on this rather than just skipping the video.
    private var showsUI: Bool { NotchPulseFaceIDSettings.shared.showUnlockAnimation }

    /// Reads the space key on the lock screen for the "On space" trigger; only runs while locked + opted in.
    private let spaceKeyMonitor = NotchPulseSpaceKeyMonitor()

    init(pocController: NotchPulsePOCController) {
        self.pocController = pocController
        self.isEnabled = NotchPulseFaceIDSettings.shared.isFaceUnlockEnabled
        self.matchThreshold = NotchPulseFaceIDSettings.shared.matchThreshold
        spaceKeyMonitor.onSpaceKeyDown = { [weak self] in self?.handleSpaceKeyPress() }
        observeLockAndWakeEvents()
        
        Task { @MainActor [weak self] in
            if NotchPulseLockMonitor.isScreenActuallyLocked() {
                self?.evaluateTrigger()
            }
        }
    }

    /// Re-subscribes on every change — `withObservationTracking` only fires once per registration.
    private func observeLockAndWakeEvents() {
        withObservationTracking {
            _ = lockMonitor.isScreenLocked
            _ = lockMonitor.wakeEventCount
            _ = lockMonitor.isSleeping
            // Also tracked so screensaver-stop and display-only wakes still wake this up.
            _ = lockMonitor.eventCount
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.observeLockAndWakeEvents()
                // Brief settle delay: CGSession's reported state can lag the true state right after wake.
                try? await Task.sleep(nanoseconds: 300_000_000)
                self?.evaluateTrigger()
            }
        }
    }

    private func evaluateTrigger() {
        if !NotchPulseLockMonitor.isScreenActuallyLocked() {
            // When waking from sleep, CGSessionCopyCurrentDictionary often lags by 300-1200ms
            if lockMonitor.lastEvent == .wake || lockMonitor.hasRecentWake {
                hasArmedForCurrentLock = false
                hasAutoRetriedForCurrentLock = false
                Task { @MainActor [weak self] in
                    for delay in [150, 300, 500, 800, 1200] {
                        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000))
                        guard let self else { return }
                        if NotchPulseLockMonitor.isScreenActuallyLocked() {
                            self.evaluateTrigger()
                            return
                        }
                    }
                    guard let self else { return }
                    if !NotchPulseLockMonitor.isScreenActuallyLocked() {
                        self.hasArmedForCurrentLock = false
                        self.hasAutoRetriedForCurrentLock = false
                        self.disarmOverlay()
                    }
                }
                return
            }

            hasArmedForCurrentLock = false
            hasAutoRetriedForCurrentLock = false
            disarmOverlay()
            return
        }
        guard !lockMonitor.isSleeping else { return }

        // `.wake` or hasRecentWake (sleep, display sleep, or screensaver stopping) is an explicit "let me back in," so clear the one-shot guard.
        let isWake = lockMonitor.lastEvent == .wake || lockMonitor.hasRecentWake
        if isWake, !isWithinRecentArmBurst {
            hasArmedForCurrentLock = false
            hasAutoRetriedForCurrentLock = false
        }

        // Runs before the hasArmedForCurrentLock guard — the space monitor's lifetime is tied to "locked + opted in," not to whether a scan already ran.
        updateSpaceMonitor()

        guard isEnabled, !hasArmedForCurrentLock else { return }
        
        let signal: UnlockTrigger?
        if isWake {
            signal = .onWake
        } else {
            signal = requiredTrigger(for: lockMonitor.lastEvent)
        }
        guard let signal else { return }

        // A pinned display that isn't connected bails entirely rather than showing up elsewhere; "Main display" (nil) always resolves.
        guard NotchGeometry.preferredScreen() != nil else { return }

        if !NotchPulseVault.isSessionUnlocked {
            _ = NotchPulseVault.ensureSessionKey()
        }
        guard NotchPulseVault.isSessionUnlocked else {
            statusMessage = "Face unlock is on, but the session is locked — authenticate once from Password settings first."
            return
        }
        guard NotchPulseVault.hasStoredPassword() else {
            statusMessage = "Face unlock is on, but no password is stored yet."
            return
        }

        // A deselected trigger means "don't auto-scan for this signal," not "do nothing" — the user can still opt in by hand.
        let shouldAutoScan: Bool
        if signal == .onLock {
            // When locking the screen, arm the notch so it is ready for hover, but do not automatically trigger camera scan before user hovers
            shouldAutoScan = false
        } else {
            shouldAutoScan = NotchPulseFaceIDSettings.shared.unlockTriggers.contains(signal)
        }

        // Headless has nothing to arm/hover, so if this signal isn't selected there's nothing to do — and hasArmedForCurrentLock
        // must stay false, or a later selected signal could never fire (nothing else calls arm() to reset it).
        guard showsUI || shouldAutoScan else { return }

        hasArmedForCurrentLock = true
        lastArmedAt = .now
        ArcFaceEmbedder.warmUp()
        NotchPulseVault.preflightKeychainAuthorization()
        NotchPulseFaceEnrollmentStore.shared.reloadIfUnlocked()
        Task { [weak self] in
            // arm() only shows a small closed notch silhouette, so this only needs a brief buffer past the login window's entrance.
            try? await Task.sleep(nanoseconds: 250_000_000)
            await self?.arm(autoScan: shouldAutoScan)
        }
    }

    /// Whether the last arm was recent enough to be part of the same wake burst rather than a new one.
    private var isWithinRecentArmBurst: Bool {
        guard let lastArmedAt else { return false }
        return ContinuousClock.now - lastArmedAt < rearmDebounce
    }

    /// nil for signals that shouldn't arm anything — including a nil `lastEvent`, or the first observation would fire regardless of user selection.
    private func requiredTrigger(for event: LockEventKind?) -> UnlockTrigger? {
        switch event {
        case .wake: return .onWake
        case .screenLocked: return .onLock
        case .screenUnlocked, .willSleep: return nil
        case nil: return .onWake
        }
    }

    private func disarmOverlay() {
        scanTask?.cancel()
        scanTask = nil
        // Bumping makes any cycle still suspended at `await camera.start()` inert, rather than resuming and re-showing the overlay.
        scanGeneration &+= 1
        autoRetryTask?.cancel()
        autoRetryTask = nil
        camera.stop()
        FaceIDOverlayController.shared.dismissImmediately()
        FaceIDOverlayController.shared.disarm()
        // Covers isEnabled being switched off directly, keeping "disarmed" and "not listening for space" in lockstep.
        spaceKeyMonitor.stop()
    }

    /// Idempotent and safe to call on every lock/wake event. Deliberately does not prompt for Input Monitoring — a missing grant just means "don't listen."
    private func updateSpaceMonitor() {
        let shouldListen = isEnabled
            && NotchPulseFaceIDSettings.shared.unlockTriggers.contains(.onSpace)
            && NotchPulseLockMonitor.isScreenActuallyLocked()
            && NotchPulseSpaceKeyMonitor.hasInputMonitoringAccess()
        if shouldListen {
            spaceKeyMonitor.start()
        } else {
            spaceKeyMonitor.stop()
        }
    }

    /// Runs the same gate chain as `evaluateTrigger`, then starts a scan. Independent of `NotchPulseLockMonitor` events, so doesn't touch `hasArmedForCurrentLock`.
    private func handleSpaceKeyPress() {
        guard isEnabled,
              NotchPulseFaceIDSettings.shared.unlockTriggers.contains(.onSpace),
              NotchPulseLockMonitor.isScreenActuallyLocked(),
              NotchGeometry.preferredScreen() != nil,
              NotchPulseVault.isSessionUnlocked,
              NotchPulseVault.hasStoredPassword()
        else { return }

        // Already looking — swallows auto-repeat/double-presses and lets "On wake"/"On lock" override "On space" with no special-casing.
        guard FaceIDOverlayController.shared.phase != .scanning else { return }

        guard showsUI else {
            // Headless: no overlay, just scan.
            startScanCycle()
            return
        }
        if FaceIDOverlayController.shared.isArmed {
            // Closed pill/notch already up — expand and scan, like a hover retry.
            startScanCycle()
        } else {
            Task { [weak self] in await self?.arm(autoScan: true) }
        }
    }

    /// Either way the overlay still arms — a deselected trigger only skips the automatic scan, leaving hover-to-start available.
    private func arm(autoScan: Bool) async {
        guard NotchPulseLockMonitor.isScreenActuallyLocked() else { return }
        guard showsUI else {
            // Headless: evaluateTrigger() already guaranteed autoScan is true here, so this is just "start scanning."
            startScanCycle()
            return
        }
        FaceIDOverlayController.shared.arm { [weak self] in
            self?.startScanCycle()
        }
        if autoScan {
            startScanCycle()
        }
    }

    /// Called on arm, and again whenever the overlay hover-activates.
    func startScanManually() {
        startScanCycle()
    }

    private func startScanCycle() {
        scanTask?.cancel()
        scanGeneration &+= 1
        let generation = scanGeneration
        scanTask = Task { [weak self] in
            await self?.runScanCycle(generation: generation)
        }
    }

    private func runScanCycle(generation: Int) async {
        guard NotchPulseLockMonitor.isScreenActuallyLocked() else { return }

        // Prerequisite check: Do NOT start camera hardware if Accessibility is not granted
        // or there is no stored password to unlock the Mac. This avoids runaway camera loops.
        guard KeystrokeInjector.isAccessibilityTrusted() else {
            statusMessage = "Accessibility not granted — cannot auto-fill password."
            if self.showsUI {
                FaceIDOverlayController.shared.finish(success: false)
            }
            return
        }
        guard NotchPulseVault.hasStoredPassword() else {
            statusMessage = "No stored password to unlock Mac."
            if self.showsUI {
                FaceIDOverlayController.shared.finish(success: false)
            }
            return
        }

        // Verify active enrolled faces exist before spinning camera hardware
        var activeIdentities = NotchPulseFaceEnrollmentStore.shared.activeIdentities
        if activeIdentities.isEmpty {
            NotchPulseFaceEnrollmentStore.shared.reloadIfUnlocked()
            activeIdentities = NotchPulseFaceEnrollmentStore.shared.activeIdentities
        }
        if activeIdentities.isEmpty {
            if let direct = try? NotchPulseSecureFaceStore.load(), !direct.isEmpty {
                activeIdentities = direct.filter(\.isEnabled)
            }
        }
        guard !activeIdentities.isEmpty else {
            statusMessage = "No enrolled face found. Enroll your face in Settings."
            if self.showsUI {
                FaceIDOverlayController.shared.finish(success: false)
            }
            return
        }

        let showsUI = self.showsUI
        statusMessage = "Looking for your face…"

        await camera.start()
        guard generation == scanGeneration else { return }

        if let error = camera.errorMessage {
            statusMessage = error
            camera.stop()
            if showsUI {
                FaceIDOverlayController.shared.finish(success: false)
            }
            return
        }

        if showsUI {
            FaceIDOverlayController.shared.beginScanning()
            FaceIDOverlayController.shared.restartScanTimeout()
        }

        let outcome = await observeScanWindow(
            deadline: Date().addingTimeInterval(scanWindowDuration),
            requireOverlayScanning: showsUI
        )

        // A newer cycle now owns the camera and overlay — leave both alone, and leave the auto-retry one-shot unspent.
        guard generation == scanGeneration else { return }

        camera.stop()

        switch outcome {
        case .matched:
            if showsUI {
                FaceIDOverlayController.shared.finish(success: true)
            }
        case .consistentlyWrongFace, .spoofSuspected:
            statusMessage = "Face not recognized. Hover to try again."
            if showsUI {
                if FaceIDOverlayController.shared.phase == .scanning {
                    FaceIDOverlayController.shared.finish(success: false)
                    scheduleAutoRetryIfEnabled(after: FaceIDOverlayController.shared.failureHoldDuration)
                } else {
                    await FaceIDOverlayController.shared.collapse()
                    scheduleAutoRetryIfEnabled(after: FaceIDOverlayController.shared.collapseAnimationDuration)
                }
            } else {
                scheduleAutoRetryIfEnabled(after: headlessRetryDelay)
            }
        case .noResolution:
            statusMessage = "Hover the notch to try again."
            if showsUI {
                await FaceIDOverlayController.shared.collapse()
                scheduleAutoRetryIfEnabled(after: FaceIDOverlayController.shared.collapseAnimationDuration)
            } else {
                scheduleAutoRetryIfEnabled(after: headlessRetryDelay)
            }
        }
    }

    /// `delay` waits out whatever the overlay is still showing so the retry doesn't start underneath the previous outcome.
    private func scheduleAutoRetryIfEnabled(after delay: Duration) {
        guard NotchPulseFaceIDSettings.shared.autoRetryOnce, !hasAutoRetriedForCurrentLock else { return }
        hasAutoRetriedForCurrentLock = true
        autoRetryTask?.cancel()
        autoRetryTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            // Re-check rather than trust the delay: the user may have unlocked by password or retried manually while this waited.
            guard NotchPulseLockMonitor.isScreenActuallyLocked(), self.isEnabled else { return }
            if self.showsUI {
                guard FaceIDOverlayController.shared.phase == .closed else { return }
            }
            self.startScanCycle()
        }
    }

    private enum ScanOutcome {
        case matched
        case consistentlyWrongFace
        /// A deny cue (glare, device rectangle) fired — actively rejected as a spoof regardless of match. Same failure path as `.consistentlyWrongFace`.
        case spoofSuspected
        case noResolution
    }

    /// Recognition and liveness run concurrently and each latches when it succeeds, so unlock fires the moment the second lands;
    /// liveness never fails the scan by staying undecided, it just keeps scanning until `deadline`.
    /// `requireOverlayScanning` bails early once the overlay's own timeout collapses the UI — only applied when there is an
    /// overlay, since headlessly `phase` never becomes `.scanning` at all.
    private func observeScanWindow(deadline: Date, requireOverlayScanning: Bool) async -> ScanOutcome {
        let livenessEnabled = NotchPulseFaceIDSettings.shared.livenessChecksEnabled
        let liveness = NotchPulseLivenessAnalyzer()
        liveness.modeProvider = { NotchPulseFaceIDSettings.shared.livenessMode }
        var consecutiveWrongFaceFrames = 0
        let wrongFaceStreakThreshold = 65

        /// Cleared when no match has been seen recently or a streak of non-matching frames occurs.
        var readyMatch: ScoredIdentity?
        var readyMatchTimestamp: Date?
        /// Turning liveness off in Settings makes this half permanently ready.
        var livenessConfirmed = !livenessEnabled
        /// Last frame's selected face, passed back so `selectDominantFace` stays on the same person instead of flip-flopping.
        var lastFaceBoundingBox: CGRect?
        /// Cheap way to detect "no new camera frame yet" vs. "fresh frame" — without it a repeat frame would corrupt the liveness motion signal.
        var lastProcessedFrameID: UInt64?

        var cachedActiveIdentities = NotchPulseFaceEnrollmentStore.shared.activeIdentities
        if cachedActiveIdentities.isEmpty {
            NotchPulseFaceEnrollmentStore.shared.reloadIfUnlocked()
            cachedActiveIdentities = NotchPulseFaceEnrollmentStore.shared.activeIdentities
        }
        if cachedActiveIdentities.isEmpty {
            if let direct = try? NotchPulseSecureFaceStore.load(), !direct.isEmpty {
                cachedActiveIdentities = direct.filter(\.isEnabled)
            }
        }

        // The user's scan window must measure FACE-SCANNING time, not camera boot time.
        // Wait up to 10s for the very first frame WITHOUT counting it against the
        // window, then re-anchor the deadline from the first real frame.
        let windowDuration = deadline.timeIntervalSinceNow
        let firstFrameCap = Date().addingTimeInterval(10)
        var effectiveDeadline = deadline
        var firstFrameSeen = false
        var scanStartTime: Date?

        while Date() < effectiveDeadline, !Task.isCancelled,
              !requireOverlayScanning || FaceIDOverlayController.shared.phase == .scanning {
            guard NotchPulseLockMonitor.isScreenActuallyLocked() else { return .noResolution }

            // Midway into scan duration, show the looking-around searching animation if still scanning
            let remaining = effectiveDeadline.timeIntervalSinceNow
            if remaining < windowDuration * 0.60 && showsUI {
                FaceIDOverlayController.shared.showSearchingAnimation()
            }

            guard let frame = camera.currentFrame, frame.id != lastProcessedFrameID else {
                if !firstFrameSeen {
                    if Date() > firstFrameCap { return .noResolution }
                    effectiveDeadline = Date().addingTimeInterval(windowDuration)
                }
                // 20ms keeps the liveness window's sample count high while staying close to the camera's native ~33ms cadence.
                try? await Task.sleep(nanoseconds: 20_000_000)
                continue
            }
            if !firstFrameSeen {
                firstFrameSeen = true
                scanStartTime = Date()
                effectiveDeadline = Date().addingTimeInterval(windowDuration)
                if showsUI {
                    FaceIDOverlayController.shared.restartScanTimeout()
                }
            }
            lastProcessedFrameID = frame.id

            let pipeline = self.pipeline
            let previousBoundingBox = lastFaceBoundingBox
            let currentThreshold = matchThreshold
            let outcome = await Task.detached(priority: .userInitiated) { () -> (FaceRecognitionResult, LivenessFrame)? in
                autoreleasepool {
                    guard let result = try? pipeline.recognize(
                        in: frame.image,
                        preferNear: previousBoundingBox
                    ) else { return nil }
                    let faceCrop = NotchPulseCamera.renderCrop(from: frame, imageRect: result.face.boundingBox)
                    return (result, NotchPulseLivenessFeatures.extract(from: result, frame: frame.image, faceCrop: faceCrop))
                }
            }.value

            guard let (result, livenessFrame) = outcome else {
                readyMatch = nil
                readyMatchTimestamp = nil
                consecutiveWrongFaceFrames = 0
                lastFaceBoundingBox = nil
                try? await Task.sleep(nanoseconds: 35_000_000)
                continue
            }
            lastFaceBoundingBox = result.face.normalizedBoundingBox

            // Fed regardless of match, so liveness stays a genuinely independent gate rather than one starved by recognition confidence.
            var confirmingCue: LivenessCue?
            if livenessEnabled {
                let snapshot = liveness.observe(livenessFrame)
                switch snapshot.decision {
                case .denied:
                    lastOutcome = snapshot.decision.denialReason
                    return .spoofSuspected
                case .confirmed(let cue):
                    livenessConfirmed = true
                    confirmingCue = cue
                case .pending:
                    break
                }
            }

            // Match against active identities with user's selected threshold
            if cachedActiveIdentities.isEmpty {
                cachedActiveIdentities = NotchPulseFaceEnrollmentStore.shared.activeIdentities
            }
            let scored = pipeline.score(result.embedding, against: cachedActiveIdentities)
            let matched = pipeline.bestMatch(in: scored, threshold: currentThreshold)

            let isWarmingUp = scanStartTime.map { Date().timeIntervalSince($0) < 1.2 } ?? true

            if let matched {
                consecutiveWrongFaceFrames = 0
                readyMatch = matched
                readyMatchTimestamp = Date()
            } else {
                if let ts = readyMatchTimestamp, Date().timeIntervalSince(ts) > 0.4 {
                    readyMatch = nil
                    readyMatchTimestamp = nil
                }
                if !isWarmingUp {
                    consecutiveWrongFaceFrames += 1
                    if consecutiveWrongFaceFrames >= wrongFaceStreakThreshold {
                        statusMessage = "Face not recognized."
                        lastOutcome = "Unrecognized face detected."
                        return .consistentlyWrongFace
                    }
                }
            }

            let candidateMatch = matched ?? (readyMatchTimestamp.map { Date().timeIntervalSince($0) < 0.4 } == true ? readyMatch : nil)

            if let candidateMatch, livenessConfirmed {
                statusMessage = "Recognized — unlocking…"
                let livenessNote = livenessEnabled
                    ? (confirmingCue.map { "live via \($0.title)" } ?? "live confirmed")
                    : "liveness off"
                lastOutcome = "Matched \(candidateMatch.identity.name) at \(String(format: "%.3f", max(candidateMatch.centroidSimilarity, candidateMatch.maxSampleSimilarity))), \(livenessNote)."
                if showsUI {
                    FaceIDOverlayController.shared.finish(success: true)
                }
                LockScreenMediaWindow.shared.hideImmediately()
                await pocController.injectStoredPassword(requireAuthoritativeLock: true)
                return .matched
            }

            try? await Task.sleep(nanoseconds: 35_000_000)
        }

        return .noResolution
    }
}
