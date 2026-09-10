//
//  NotchPulseFaceUnlockCoordinator.swift
//  NotchPulse
//
//  Connects face recognition to the actual unlock path. Handles lock states and liveness checks.
//  Ported from Glance's FaceUnlockCoordinator.swift with NotchPulse naming and integration.
//

import Foundation
import CoreGraphics
import Observation
import Defaults
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

    private var scanWindowDuration: TimeInterval = 4.0
    private let wrongFaceStreakThreshold = 6

    private(set) var statusMessage = "Idle"
    private(set) var lastOutcome: String?

    private var hasArmedForCurrentLock = false
    private var hasAutoRetriedForCurrentLock = false
    private var scanTask: Task<Void, Never>?
    private var scanGeneration = 0
    private var lastArmedAt: ContinuousClock.Instant?
    private let rearmDebounce: Duration = .seconds(2)
    private var autoRetryTask: Task<Void, Never>?
    private let headlessRetryDelay: Duration = .seconds(1)

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
            hasAutoRetriedForCurrentLock = false
            disarmOverlay()
            return
        }
        guard !lockMonitor.isSleeping else { return }

        if lockMonitor.lastEvent == .wake, !isWithinRecentArmBurst {
            hasArmedForCurrentLock = false
        }

        guard Defaults[.enableFaceID], !hasArmedForCurrentLock else { return }
        
        let validTriggers: [LockEventKind] = [.wake, .screenLocked]
        guard let event = lockMonitor.lastEvent, validTriggers.contains(event) else { return }

        // Ensure session key is unlocked and password exists
        guard NotchPulseVault.hasStoredPassword() else {
            faceIDManager.statusMessage = "Face ID unlock is on, but no password is stored yet."
            return
        }
        
        // In NotchPulse, we can unlock the Vault session using TouchID if needed, but for automated wake
        // it should already be unlocked or we fail gracefully if it needs prompt.
        if !NotchPulseVault.isSessionUnlocked {
            // Can't auto-unlock without session key
            return
        }

        hasArmedForCurrentLock = true
        lastArmedAt = .now
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
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
        // Hide if needed
    }

    /// Called by FaceIDManager for manual hover/click retry
    func startScanManually() {
        if !faceIDManager.isScanning {
            hasArmedForCurrentLock = true
            startScanCycle()
        }
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
        guard generation == scanGeneration else { return }

        if let error = camera.errorMessage {
            faceIDManager.statusMessage = error
            camera.stop()
            faceIDManager.isScanning = false
            return
        }

        faceIDManager.statusMessage = "Looking for your face…"
        faceIDManager.isScanning = true

        let outcome = await observeScanWindow(deadline: Date().addingTimeInterval(scanWindowDuration))

        guard generation == scanGeneration else { return }

        camera.stop()
        faceIDManager.isScanning = false

        switch outcome {
        case .matched:
            faceIDManager.statusMessage = "Recognized — unlocking…"
            faceIDManager.lastUnlockSuccess = true
            // Call performMacUnlock
            await performMacUnlock()
        case .consistentlyWrongFace:
            faceIDManager.statusMessage = "Face Not Recognized"
            scheduleAutoRetryIfEnabled(after: headlessRetryDelay)
        case .spoofSuspected:
            faceIDManager.statusMessage = "Face Not Recognized" // UI checks for this string
            scheduleAutoRetryIfEnabled(after: headlessRetryDelay)
        case .noResolution:
            faceIDManager.statusMessage = "No face detected."
            scheduleAutoRetryIfEnabled(after: headlessRetryDelay)
        }
    }

    private func scheduleAutoRetryIfEnabled(after delay: Duration) {
        // Just retry once if failed
        guard !hasAutoRetriedForCurrentLock else { return }
        hasAutoRetriedForCurrentLock = true
        autoRetryTask?.cancel()
        autoRetryTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            guard NotchPulseLockMonitor.isScreenActuallyLocked(), Defaults[.enableFaceID] else { return }
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
        let livenessEnabled = true // Configurable?
        let liveness = NotchPulseLivenessAnalyzer()
        liveness.modeProvider = { .heavy } // Or light based on settings
        
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

            // In NotchPulse we currently fetch the single enrolled face via EnrollmentStore
            let activeIdentities = NotchPulseFaceEnrollmentStore.shared.activeIdentities
            let scored = pipeline.score(result.embedding, against: activeIdentities)
            let matched = pipeline.bestMatch(in: scored, threshold: 0.8) // Use Defaults match threshold

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
    
    nonisolated private static func keyEventInfo(for char: Character) -> (keyCode: CGKeyCode, shift: Bool)? {
        switch char {
        case "a": return (0x00, false); case "A": return (0x00, true)
        case "b": return (0x0B, false); case "B": return (0x0B, true)
        case "c": return (0x08, false); case "C": return (0x08, true)
        case "d": return (0x02, false); case "D": return (0x02, true)
        case "e": return (0x0E, false); case "E": return (0x0E, true)
        case "f": return (0x03, false); case "F": return (0x03, true)
        case "g": return (0x05, false); case "G": return (0x05, true)
        case "h": return (0x04, false); case "H": return (0x04, true)
        case "i": return (0x22, false); case "I": return (0x22, true)
        case "j": return (0x26, false); case "J": return (0x26, true)
        case "k": return (0x28, false); case "K": return (0x28, true)
        case "l": return (0x25, false); case "L": return (0x25, true)
        case "m": return (0x2E, false); case "M": return (0x2E, true)
        case "n": return (0x2D, false); case "N": return (0x2D, true)
        case "o": return (0x1F, false); case "O": return (0x1F, true)
        case "p": return (0x23, false); case "P": return (0x23, true)
        case "q": return (0x0C, false); case "Q": return (0x0C, true)
        case "r": return (0x0F, false); case "R": return (0x0F, true)
        case "s": return (0x01, false); case "S": return (0x01, true)
        case "t": return (0x11, false); case "T": return (0x11, true)
        case "u": return (0x20, false); case "U": return (0x20, true)
        case "v": return (0x09, false); case "V": return (0x09, true)
        case "w": return (0x0D, false); case "W": return (0x0D, true)
        case "x": return (0x07, false); case "X": return (0x07, true)
        case "y": return (0x10, false); case "Y": return (0x10, true)
        case "z": return (0x06, false); case "Z": return (0x06, true)
        case "1": return (0x12, false); case "!": return (0x12, true)
        case "2": return (0x13, false); case "@": return (0x13, true)
        case "3": return (0x14, false); case "#": return (0x14, true)
        case "4": return (0x15, false); case "$": return (0x15, true)
        case "5": return (0x17, false); case "%": return (0x17, true)
        case "6": return (0x16, false); case "^": return (0x16, true)
        case "7": return (0x1A, false); case "&": return (0x1A, true)
        case "8": return (0x1C, false); case "*": return (0x1C, true)
        case "9": return (0x19, false); case "(": return (0x19, true)
        case "0": return (0x1D, false); case ")": return (0x1D, true)
        case " ": return (0x31, false); case "-": return (0x1B, false)
        case "_": return (0x1B, true); case "=": return (0x18, false)
        case "+": return (0x18, true); case "[": return (0x21, false)
        case "{": return (0x21, true); case "]": return (0x1E, false)
        case "}": return (0x1E, true); case "\\": return (0x2A, false)
        case "|": return (0x2A, true); case ";": return (0x29, false)
        case ":": return (0x29, true); case "'": return (0x27, false)
        case "\"": return (0x27, true); case ",": return (0x2B, false)
        case "<": return (0x2B, true); case ".": return (0x2F, false)
        case ">": return (0x2F, true); case "/": return (0x2C, false)
        case "?": return (0x2C, true); case "`": return (0x32, false)
        case "~": return (0x32, true)
        default: return nil
        }
    }
    
    private func performMacUnlock() async {
        guard let passwordData = try? NotchPulseVault.readPassword(),
              let password = String(data: passwordData, encoding: .utf8), !password.isEmpty else {
            return
        }
        
        if Defaults[.faceIDSound] {
            NSSound(named: "Glass")?.play()
        }
        
        let pressCount = max(1, min(5, Defaults[.faceIDEnterPressCount]))
        
        DispatchQueue.global(qos: .userInteractive).async {
            Self.injectUnlockEvents(password: password, pressCount: pressCount)
        }
    }
    
    nonisolated private static func injectUnlockEvents(password: String, pressCount: Int) {
        let source = CGEventSource(stateID: .hidSystemState)
        
        let mouseLoc = CGEvent(source: nil)?.location ?? CGPoint(x: 500, y: 500)
        if let moveEvent = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: CGPoint(x: mouseLoc.x + 1, y: mouseLoc.y), mouseButton: .left) {
            moveEvent.post(tap: .cghidEventTap)
        }
        Thread.sleep(forTimeInterval: 0.05)
        if !NotchPulseLockMonitor.isScreenActuallyLocked() { return }
        
        for _ in 0..<15 {
            if !NotchPulseLockMonitor.isScreenActuallyLocked() { return }
            if let delDown = CGEvent(keyboardEventSource: source, virtualKey: 0x33, keyDown: true),
               let delUp = CGEvent(keyboardEventSource: source, virtualKey: 0x33, keyDown: false) {
                delDown.flags = []
                delUp.flags = []
                delDown.post(tap: .cghidEventTap)
                delUp.post(tap: .cghidEventTap)
            }
            Thread.sleep(forTimeInterval: 0.006)
        }
        Thread.sleep(forTimeInterval: 0.04)
        if !NotchPulseLockMonitor.isScreenActuallyLocked() { return }
        
        for char in password {
            if !NotchPulseLockMonitor.isScreenActuallyLocked() { return }
            if let keyInfo = Self.keyEventInfo(for: char) {
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
                    Thread.sleep(forTimeInterval: 0.012)
                    up.post(tap: .cghidEventTap)
                    Thread.sleep(forTimeInterval: 0.012)
                }
            }
        }
        
        Thread.sleep(forTimeInterval: 0.1)
        if !NotchPulseLockMonitor.isScreenActuallyLocked() { return }
        
        func sendReturn() {
            if let returnDown = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: true),
               let returnUp = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: false) {
                returnDown.flags = []
                returnUp.flags = []
                let returnUnicode: [UniChar] = [0x000D]
                returnDown.keyboardSetUnicodeString(stringLength: 1, unicodeString: returnUnicode)
                returnUp.keyboardSetUnicodeString(stringLength: 1, unicodeString: returnUnicode)
                returnDown.post(tap: .cghidEventTap)
                Thread.sleep(forTimeInterval: 0.03)
                returnUp.post(tap: .cghidEventTap)
            }
            
            let script = NSAppleScript(source: "tell application \"System Events\" to key code 36")
            script?.executeAndReturnError(nil)
        }
        
        for i in 0..<pressCount {
            if !NotchPulseLockMonitor.isScreenActuallyLocked() { return }
            if i > 0 { Thread.sleep(forTimeInterval: 0.12) }
            sendReturn()
        }

        Thread.sleep(forTimeInterval: 2.5)
        if NotchPulseLockMonitor.isScreenActuallyLocked() {
            DispatchQueue.main.async {
                FaceIDManager.shared.lastUnlockSuccess = false
                FaceIDManager.shared.statusMessage = "Ready"
            }
        }
    }
}

