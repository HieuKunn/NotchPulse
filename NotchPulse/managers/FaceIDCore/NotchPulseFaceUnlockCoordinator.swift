//
//  NotchPulseFaceUnlockCoordinator.swift
//  NotchPulse
//
//  Connects face recognition to the actual unlock path. Handles lock states and liveness checks.
//  Native NotchPulse Face ID biometric implementation.
//

import Foundation
import CoreGraphics
import Observation
import Defaults
import AppKit

import AppKit

@Observable
@MainActor
final class NotchPulseFaceUnlockCoordinator {
    static let shared = NotchPulseFaceUnlockCoordinator()
    
    let lockMonitor = NotchPulseLockMonitor()
    // In NotchPulse, the Camera and Pipeline can be owned by FaceIDManager or locally. 
    // We will instantiate them locally for the unlock sequence, or reuse them.
    let camera = NotchPulseCamera()
    let pipeline = NotchPulseFaceRecognitionPipeline()

    // Sync state to FaceIDManager for the UI to observe
    private var faceIDManager: FaceIDManager { FaceIDManager.shared }

    private var scanWindowDuration: TimeInterval = 6.0
    private let wrongFaceStreakThreshold = 6

    private(set) var statusMessage = "Idle"
    private(set) var lastOutcome: String?

    private var hasArmedForCurrentLock = false
    private var autoRetryCount = 0
    private let maxAutoRetries = 3
    private var scanTask: Task<Void, Never>?
    private var scanGeneration = 0
    private var lastArmedAt: ContinuousClock.Instant?
    private let rearmDebounce: Duration = .seconds(2)
    private var autoRetryTask: Task<Void, Never>?
    private let baseRetryDelay: Duration = .seconds(1)

    private init() {
        observeLockAndWakeEvents()
    }

    private func observeLockAndWakeEvents() {
        withObservationTracking {
            _ = lockMonitor.isScreenLocked
            _ = lockMonitor.wakeEventCount
            _ = lockMonitor.isSleeping
            _ = lockMonitor.eventCount
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.observeLockAndWakeEvents()
                try? await Task.sleep(nanoseconds: 300_000_000)
                self?.evaluateTrigger()
            }
        }
    }

    private func evaluateTrigger() {
        guard NotchPulseLockMonitor.isScreenActuallyLocked() else {
            hasArmedForCurrentLock = false
            autoRetryCount = 0
            disarmOverlay()
            return
        }
        guard !lockMonitor.isSleeping else { return }

        if lockMonitor.lastEvent == .wake, !isWithinRecentArmBurst {
            hasArmedForCurrentLock = false
        }

        // Only auto-trigger scan on display/system wake (e.g. lid open or wake from sleep).
        // For screen lock during active work session, camera remains off until user hovers/clicks the notch.
        let validTriggers: [LockEventKind] = [.wake, .screenLocked]
        guard let event = lockMonitor.lastEvent, validTriggers.contains(event) else { return }

        // Ensure password exists
        guard NotchPulseVault.hasStoredPassword() else {
            faceIDManager.statusMessage = "Face ID unlock is on, but no password is stored yet."
            return
        }

        hasArmedForCurrentLock = true
        lastArmedAt = .now
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            self?.startScanCycle()
        }
    }

    private var isWithinRecentArmBurst: Bool {
        guard let lastArmedAt else { return false }
        return ContinuousClock.now - lastArmedAt < rearmDebounce
    }

    private func disarmOverlay() {
        scanTask?.cancel()
        scanTask = nil
        scanGeneration &+= 1
        autoRetryTask?.cancel()
        autoRetryTask = nil
        camera.stop()
        
        faceIDManager.isScanning = false
    }

    /// Called by FaceIDManager for manual hover/click retry
    func startScanManually() {
        guard NotchPulseVault.hasStoredPassword() else {
            faceIDManager.statusMessage = "No password stored"
            return
        }
        hasArmedForCurrentLock = true
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

        await camera.requestAccessAndStart()
        defer {
            camera.stop()
            faceIDManager.isScanning = false
        }
        guard generation == scanGeneration else { return }

        if let error = camera.errorMessage {
            faceIDManager.statusMessage = error
            return
        }

        faceIDManager.statusMessage = "Looking for your face…"
        faceIDManager.isScanning = true
        LockScreenFaceIDWindow.shared.ignoresMouseEvents = false

        // Wait for the camera to actually deliver its first frame before starting
        // the scan timer. After sleep/wake the hardware can take 1-3s to initialize;
        // without this the scan window burns through while no frames exist.
        let warmupStart = ContinuousClock.now
        while camera.currentFrame == nil, ContinuousClock.now - warmupStart < .seconds(3) {
            guard generation == scanGeneration, !Task.isCancelled else { return }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        guard generation == scanGeneration else { return }

        let outcome = await observeScanWindow(deadline: Date().addingTimeInterval(scanWindowDuration))

        guard generation == scanGeneration else { return }

        switch outcome {
        case .matched:
            faceIDManager.statusMessage = "Recognized — unlocking…"
            faceIDManager.lastUnlockSuccess = true
            autoRetryCount = 0
            await performMacUnlock()
        case .consistentlyWrongFace:
            print("[FaceID] Scan failed: consistently wrong face (attempt \(autoRetryCount + 1)/\(maxAutoRetries))")
            faceIDManager.statusMessage = "Face Not Recognized"
            LockScreenFaceIDWindow.shared.ignoresMouseEvents = true
            let delay: Duration = .seconds(Double(min(autoRetryCount + 1, 3)))
            scheduleAutoRetryIfEnabled(after: delay)
        case .spoofSuspected:
            print("[FaceID] Scan failed: spoof suspected (attempt \(autoRetryCount + 1)/\(maxAutoRetries))")
            faceIDManager.statusMessage = "Face Not Recognized"
            LockScreenFaceIDWindow.shared.ignoresMouseEvents = true
            let delay: Duration = .seconds(Double(min(autoRetryCount + 1, 3)))
            scheduleAutoRetryIfEnabled(after: delay)
        case .noResolution:
            print("[FaceID] Scan failed: no face detected (attempt \(autoRetryCount + 1)/\(maxAutoRetries))")
            faceIDManager.statusMessage = "No face detected."
            LockScreenFaceIDWindow.shared.ignoresMouseEvents = true
            let delay: Duration = .seconds(Double(min(autoRetryCount + 1, 3)))
            scheduleAutoRetryIfEnabled(after: delay)
        }
    }

    private func scheduleAutoRetryIfEnabled(after delay: Duration) {
        guard autoRetryCount < maxAutoRetries else {
            print("[FaceID] Max retries (\(maxAutoRetries)) exhausted for this lock cycle")
            return
        }
        autoRetryCount += 1
        autoRetryTask?.cancel()
        autoRetryTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            guard NotchPulseLockMonitor.isScreenActuallyLocked(), Defaults[.enableFaceID] else { return }
            print("[FaceID] Auto-retry \(self.autoRetryCount)/\(self.maxAutoRetries) after \(delay)")
            self.startScanCycle()
        }
    }

    private enum ScanOutcome {
        case matched
        case consistentlyWrongFace
        case spoofSuspected
        case noResolution
    }

    private func observeScanWindow(deadline: Date) async -> ScanOutcome {
        let livenessEnabled = true
        let liveness = NotchPulseLivenessAnalyzer()
        // Light mode: deny cues still block spoofs (gloss/glare, device detection) but
        // no positive proof-of-life (blink/3D) is required — auto-confirms after enough
        // clean frames. This means users no longer need to blink to unlock.
        liveness.modeProvider = { .light }
        
        var consecutiveWrongFaceFrames = 0
        var readyMatch: Bool = false
        var livenessConfirmed = !livenessEnabled
        var lastFaceBoundingBox: CGRect?
        var lastProcessedFrameID: UInt64?

        while Date() < deadline, !Task.isCancelled {
            guard NotchPulseLockMonitor.isScreenActuallyLocked() else { return .noResolution }

            guard let frame = camera.currentFrame, frame.id != lastProcessedFrameID else {
                try? await Task.sleep(nanoseconds: 20_000_000)
                continue
            }
            lastProcessedFrameID = frame.id

            let pipeline = self.pipeline
            let previousBoundingBox = lastFaceBoundingBox
            let outcome = await Task.detached(priority: .userInitiated) { () -> (FaceRecognitionResult, LivenessFrame)? in
                guard let result = try? pipeline.recognize(in: frame.image, preferNear: previousBoundingBox) else { return nil }
                let faceCrop = NotchPulseCamera.renderCrop(from: frame, imageRect: result.face.boundingBox)
                return (result, NotchPulseLivenessFeatureExtractor.extract(from: result, frame: frame.image, faceCrop: faceCrop))
            }.value

            guard let (result, livenessFrame) = outcome else {
                consecutiveWrongFaceFrames = 0
                lastFaceBoundingBox = nil
                try? await Task.sleep(nanoseconds: 20_000_000)
                continue
            }
            lastFaceBoundingBox = result.face.normalizedBoundingBox

            if livenessEnabled {
                let snapshot = liveness.observe(livenessFrame)
                switch snapshot.decision {
                case .denied:
                    lastOutcome = snapshot.decision.denialReason
                    return .spoofSuspected
                case .confirmed:
                    livenessConfirmed = true
                case .pending:
                    break
                }
            }

            // `activeIdentities`, not `identities`: someone switched off on the Your Face page stays enrolled but must not unlock.
            let activeIdentities = NotchPulseFaceEnrollmentStore.shared.activeIdentities
            guard !activeIdentities.isEmpty else {
                return .noResolution
            }

            let scored = pipeline.score(result.embedding, against: activeIdentities)
            let threshold: Float = Float(Defaults[.faceIDMatchThreshold])
            let matched = pipeline.bestMatch(in: scored, threshold: threshold)

            if matched != nil {
                consecutiveWrongFaceFrames = 0
                readyMatch = true
            } else {
                readyMatch = false
                consecutiveWrongFaceFrames += 1
                if consecutiveWrongFaceFrames >= wrongFaceStreakThreshold {
                    return .consistentlyWrongFace
                }
            }

            if readyMatch && livenessConfirmed {
                return .matched
            }

            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return .noResolution
    }
    
    // MARK: - Mac Unlock Execution (From FaceIDManager)
    // Lock and state are file-private to avoid MainActor isolation
    
    private func performMacUnlock() async {
        guard let passwordData = try? NotchPulseVault.readPassword(), !passwordData.isEmpty else {
            return
        }
        
        if Defaults[.faceIDSound] {
            NSSound(named: "Glass")?.play()
        }
        
        Task.detached(priority: .userInitiated) {
            do {
                try KeystrokeInjector.typeAndReturn(passwordData)
            } catch {
                print("[FaceID] Keystroke injection error: \(error)")
            }
        }
    }
}
