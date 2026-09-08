//
//  FaceIDManager.swift
//  NotchPulse
//

import AVFoundation
import Cocoa
import Combine
import CoreGraphics
import Foundation
import SwiftUI
import CoreVideo

struct EnrolledFace: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var createdAt: Date = Date()
    var vectors: [[Double]] = [] // Unused now, but kept for UI compatibility
}

@MainActor
final class FaceIDManager: NSObject, ObservableObject {
    static let shared = FaceIDManager()
    
    // MARK: - Published State
    @Published var enrolledFaces: [EnrolledFace] = []
    @Published var isEnrolled: Bool = false
    @Published var isScanning: Bool = false
    @Published var enrollmentProgress: Double = 0.0
    @Published var statusMessage: String = "Ready"
    @Published var lastUnlockSuccess: Bool = false
    @Published var hasPasswordSet: Bool = false
    
    // Live Tester State (for Settings UI)
    @Published var isTestingMode: Bool = false
    @Published var testResultText: String = ""
    @Published var testResultColor: Color = .secondary
    @Published var testConfidence: Int = 0
    
    // Core engine
    private let camera = NotchPulseCamera()
    private let enrollmentService = NotchPulseEnrollmentService()
    
    private var recognitionTask: Task<Void, Never>?
    private var unlockTask: Task<Void, Never>?
    private var isEnrollmentMode: Bool = false
    
    // MARK: - Initialization
    override private init() {
        super.init()
        refreshState()
        
        // Setup observer for camera frames
        _ = withObservationTracking {
            self.camera.isRunning
        } onChange: {
            // Camera state changed
        }
    }
    
    func refreshState() {
        hasPasswordSet = NotchPulseVault.hasStoredPassword()
        isEnrolled = NotchPulseEnrollmentService.hasEnrolledFace()
        if isEnrolled {
            enrolledFaces = [EnrolledFace(name: "My Face")]
        } else {
            enrolledFaces = []
        }
    }
    
    func ensureSessionUnlocked() async -> Bool {
        if NotchPulseVault.isSessionUnlocked { return true }
        if NotchPulseVault.hasSessionKey() {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try NotchPulseVault.unlockSession(reason: "Unlock Face ID Security")
                }.value
                return true
            } catch {
                self.statusMessage = "Biometric authentication required"
                return false
            }
        }
        return true
    }
    
    // MARK: - API
    
    func deleteFace(id: UUID) {
        resetEnrollment()
    }
    
    func resetEnrollment() {
        try? NotchPulseEnrollmentService.deleteEnrolledFace()
        try? NotchPulseVault.deletePassword()
        refreshState()
        statusMessage = "All Face ID data cleared"
    }
    
    func cancelCurrentSession() {
        recognitionTask?.cancel()
        unlockTask?.cancel()
        camera.stop()
        isScanning = false
        isEnrollmentMode = false
        isTestingMode = false
        lastUnlockSuccess = false
        statusMessage = "Cancelled"
        enrollmentProgress = 0.0
    }
    
    func startRecognitionOnWake() {
        guard Defaults[.enableFaceID], isEnrolled, hasPasswordSet else { return }
        guard !isScanning else { return }
        
        isEnrollmentMode = false
        isTestingMode = false
        lastUnlockSuccess = false
        statusMessage = "Verifying face..."
        isScanning = true
        
        recognitionTask?.cancel()
        recognitionTask = Task { [weak self] in
            guard let self = self else { return }
            
            // First ensure we have access to the session key
            let unlocked = await self.ensureSessionUnlocked()
            if !unlocked {
                self.isScanning = false
                return
            }
            
            await self.camera.requestAccessAndStart()
            
            let startTime = Date()
            var consecutiveMatches = 0
            
            while !Task.isCancelled && Date().timeIntervalSince(startTime) < 4.0 {
                guard let buffer = self.camera.currentFrame() else {
                    try? await Task.sleep(for: .milliseconds(50))
                    continue
                }
                
                do {
                    let analysis = try self.enrollmentService.analyzeFrame(buffer, includeQuality: false)
                    
                    // ArcFace embeddings are [Float] not [Double], verify using the service
                    let result = try self.enrollmentService.verify(currentEmbedding: analysis.embedding)
                    
                    if result.matched {
                        consecutiveMatches += 1
                        if consecutiveMatches >= 2 { // Require 2 frames
                            self.camera.stop()
                            self.isScanning = false
                            self.performMacUnlock()
                            return
                        }
                    } else {
                        consecutiveMatches = 0
                    }
                } catch {
                    // Ignore transient errors (no face, etc)
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
            
            if !Task.isCancelled {
                self.camera.stop()
                self.statusMessage = "Face Not Recognized"
                self.isScanning = false
                try? await Task.sleep(for: .milliseconds(1200))
                if !self.isScanning {
                    self.statusMessage = "Ready"
                }
            }
        }
    }
    
    func startEnrollment(name: String? = nil) {
        isEnrollmentMode = true
        isTestingMode = false
        lastUnlockSuccess = false
        enrollmentProgress = 0.0
        isScanning = true
        statusMessage = "Starting enrollment..."
        
        recognitionTask?.cancel()
        recognitionTask = Task { [weak self] in
            guard let self = self else { return }
            
            // Ensure session key is created/unlocked before we save embeddings
            _ = await self.ensureSessionUnlocked()
            
            await self.camera.requestAccessAndStart()
            
            var collectedEmbeddings: [[Float]] = []
            let requiredPoses = FacePose.allCases
            let totalPoses = requiredPoses.count
            
            // We capture 3 valid frames per pose to average out noise
            let framesPerPose = 3
            
            for (index, pose) in requiredPoses.enumerated() {
                self.statusMessage = pose.prompt
                self.enrollmentProgress = Double(index) / Double(totalPoses)
                
                var poseFramesCaptured = 0
                var poseEmbeddings: [[Float]] = []
                let poseStartTime = Date()
                
                while !Task.isCancelled && poseFramesCaptured < framesPerPose {
                    // Timeout per pose: 15s
                    if Date().timeIntervalSince(poseStartTime) > 15.0 {
                        self.statusMessage = "Enrollment timed out"
                        self.camera.stop()
                        self.isScanning = false
                        self.isEnrollmentMode = false
                        return
                    }
                    
                    guard let buffer = self.camera.currentFrame() else {
                        try? await Task.sleep(for: .milliseconds(50))
                        continue
                    }
                    
                    do {
                        // For enrollment, we enforce quality checks and bbox constraints
                        let analysis = try self.enrollmentService.analyzeFrame(buffer, includeQuality: true)
                        
                        if analysis.quality < NotchPulseEnrollmentService.minimumCaptureQuality {
                            self.statusMessage = "Quality too low. Improve lighting."
                        } else if !pose.matches(yaw: analysis.yaw, roll: analysis.roll, faceWidth: analysis.face.boundingBox.width) {
                            self.statusMessage = pose.prompt
                        } else {
                            poseEmbeddings.append(analysis.embedding)
                            poseFramesCaptured += 1
                            self.statusMessage = "Hold still... (\(poseFramesCaptured)/\(framesPerPose))"
                        }
                    } catch {
                        if let error = error as? NotchPulseEnrollmentError {
                            self.statusMessage = error.localizedDescription
                        }
                    }
                    
                    try? await Task.sleep(for: .milliseconds(150))
                }
                
                if Task.isCancelled { return }
                
                // Average the 3 frames for this pose
                if !poseEmbeddings.isEmpty {
                    var mean = [Float](repeating: 0, count: poseEmbeddings[0].count)
                    for e in poseEmbeddings {
                        for i in 0..<e.count {
                            mean[i] += e[i]
                        }
                    }
                    let avgEmbedding = NotchPulseFaceEmbedder.l2Normalize(mean)
                    collectedEmbeddings.append(avgEmbedding)
                }
            }
            
            if Task.isCancelled { return }
            
            // Save embeddings
            do {
                try self.enrollmentService.saveEmbeddings(collectedEmbeddings)
                self.refreshState()
                self.statusMessage = "Enrollment complete! 🎉"
                if Defaults[.faceIDSound] { NSSound(named: "Ping")?.play() }
            } catch {
                self.statusMessage = "Failed to save: \(error.localizedDescription)"
            }
            
            self.enrollmentProgress = 1.0
            self.camera.stop()
            self.isScanning = false
            self.isEnrollmentMode = false
            try? await Task.sleep(for: .seconds(2))
            if !self.isScanning { self.statusMessage = "Ready" }
        }
    }
    
    func startTestRecognition() {
        guard isEnrolled else {
            testResultText = "⚠️ Please enroll a face first"
            testResultColor = .orange
            return
        }
        
        isTestingMode = true
        isEnrollmentMode = false
        lastUnlockSuccess = false
        testResultText = "Looking for face..."
        testResultColor = .secondary
        testConfidence = 0
        isScanning = true
        
        recognitionTask?.cancel()
        recognitionTask = Task { [weak self] in
            guard let self = self else { return }
            
            let unlocked = await self.ensureSessionUnlocked()
            if !unlocked {
                self.testResultText = "Session locked"
                self.isScanning = false
                return
            }
            
            await self.camera.requestAccessAndStart()
            
            let startTime = Date()
            while !Task.isCancelled && Date().timeIntervalSince(startTime) < 8.0 {
                guard let buffer = self.camera.currentFrame() else {
                    try? await Task.sleep(for: .milliseconds(50))
                    continue
                }
                
                do {
                    let analysis = try self.enrollmentService.analyzeFrame(buffer, includeQuality: false)
                    let result = try self.enrollmentService.verify(currentEmbedding: analysis.embedding)
                    
                    let sim = result.similarity
                    let confidence = max(0, min(100, Int(((sim - 0.4) / (1.0 - 0.4)) * 100)))
                    self.testConfidence = confidence
                    
                    if result.matched {
                        self.testResultText = "✅ Matched: (\(confidence)%)"
                        self.testResultColor = .green
                    } else {
                        self.testResultText = "❌ Unrecognized Face (Score: \(confidence)%)"
                        self.testResultColor = .red
                    }
                } catch {
                    self.testResultText = "Searching..."
                    self.testResultColor = .secondary
                }
                try? await Task.sleep(for: .milliseconds(150))
            }
            
            if !Task.isCancelled {
                self.camera.stop()
                self.isScanning = false
                self.isTestingMode = false
                self.testResultText = "Test complete"
                self.testResultColor = .secondary
            }
        }
    }
    
    func stopTestRecognition() {
        cancelCurrentSession()
    }
    
    // MARK: - Mac Unlock Execution
    
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
    
    private func performMacUnlock() {
        guard let passwordData = try? NotchPulseVault.readPassword(),
              let password = String(data: passwordData, encoding: .utf8), !password.isEmpty else {
            statusMessage = "Chưa lưu mật khẩu mở máy trong Keychain"
            return
        }
        
        statusMessage = "Face ID Xác thực! Đang mở khoá…"
        lastUnlockSuccess = true
        
        if Defaults[.faceIDSound] {
            NSSound(named: "Glass")?.play()
        }
        
        unlockTask?.cancel()
        unlockTask = Task.detached(priority: .high) {
            let source = CGEventSource(stateID: .hidSystemState)
            
            let mouseLoc = CGEvent(source: nil)?.location ?? CGPoint(x: 500, y: 500)
            if let moveEvent = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: CGPoint(x: mouseLoc.x + 1, y: mouseLoc.y), mouseButton: .left) {
                moveEvent.post(tap: .cghidEventTap)
            }
            try? await Task.sleep(for: .milliseconds(50))
            if Task.isCancelled || !LockScreenWakeObserver.isSessionLocked { return }
            
            for _ in 0..<15 {
                if Task.isCancelled || !LockScreenWakeObserver.isSessionLocked { return }
                if let delDown = CGEvent(keyboardEventSource: source, virtualKey: 0x33, keyDown: true),
                   let delUp = CGEvent(keyboardEventSource: source, virtualKey: 0x33, keyDown: false) {
                    delDown.flags = []
                    delUp.flags = []
                    delDown.post(tap: .cghidEventTap)
                    delUp.post(tap: .cghidEventTap)
                }
                try? await Task.sleep(for: .milliseconds(6))
            }
            try? await Task.sleep(for: .milliseconds(40))
            if Task.isCancelled || !LockScreenWakeObserver.isSessionLocked { return }
            
            for char in password {
                if Task.isCancelled || !LockScreenWakeObserver.isSessionLocked { return }
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
                        try? await Task.sleep(for: .milliseconds(12))
                        up.post(tap: .cghidEventTap)
                        try? await Task.sleep(for: .milliseconds(12))
                    }
                }
            }
            
            try? await Task.sleep(for: .milliseconds(100))
            if Task.isCancelled || !LockScreenWakeObserver.isSessionLocked { return }
            
            func sendReturn() async {
                if let returnDown = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: true),
                   let returnUp = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: false) {
                    returnDown.flags = []
                    returnUp.flags = []
                    let returnUnicode: [UniChar] = [0x000D]
                    returnDown.keyboardSetUnicodeString(stringLength: 1, unicodeString: returnUnicode)
                    returnUp.keyboardSetUnicodeString(stringLength: 1, unicodeString: returnUnicode)
                    returnDown.post(tap: .cghidEventTap)
                    try? await Task.sleep(for: .milliseconds(30))
                    returnUp.post(tap: .cghidEventTap)
                }
                
                let script = NSAppleScript(source: "tell application \"System Events\" to key code 36")
                script?.executeAndReturnError(nil)
            }
            
            let pressCount = max(1, min(5, Defaults[.faceIDEnterPressCount]))
            for i in 0..<pressCount {
                if Task.isCancelled || !LockScreenWakeObserver.isSessionLocked { return }
                if i > 0 { try? await Task.sleep(for: .milliseconds(120)) }
                await sendReturn()
            }
            
            try? await Task.sleep(for: .milliseconds(2500))
            if LockScreenWakeObserver.isSessionLocked {
                await MainActor.run {
                    FaceIDManager.shared.lastUnlockSuccess = false
                    FaceIDManager.shared.statusMessage = "Ready"
                }
            }
        }
    }
}
