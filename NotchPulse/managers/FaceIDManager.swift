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
import Defaults

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
        NotchPulseFaceUnlockCoordinator.shared.startScanManually()
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
            
            // We capture 6 valid frames per pose to deeply cover face features
            let framesPerPose = 6
            
            for (index, pose) in requiredPoses.enumerated() {
                self.statusMessage = pose.prompt
                self.enrollmentProgress = Double(index) / Double(totalPoses)
                
                var poseFramesCaptured = 0
                var poseEmbeddings: [[Float]] = []
                let poseStartTime = Date()
                
                while !Task.isCancelled && poseFramesCaptured < framesPerPose {
                    // Timeout per pose: 20s
                    if Date().timeIntervalSince(poseStartTime) > 20.0 {
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
                            self.statusMessage = "Giữ nguyên... (\(poseFramesCaptured)/\(framesPerPose))"
                        }
                    } catch {
                        if let error = error as? NotchPulseEnrollmentError {
                            self.statusMessage = error.localizedDescription
                        }
                    }
                    
                    try? await Task.sleep(for: .milliseconds(120))
                }
                
                if Task.isCancelled { return }
                
                // Average the frames for this pose + save key pose samples for rich representation
                if !poseEmbeddings.isEmpty {
                    var mean = [Float](repeating: 0, count: poseEmbeddings[0].count)
                    for e in poseEmbeddings {
                        for i in 0..<e.count {
                            mean[i] += e[i]
                        }
                    }
                    let avgEmbedding = NotchPulseFaceEmbedder.l2Normalize(mean)
                    collectedEmbeddings.append(avgEmbedding)
                    
                    // Also include 1st and last frame to capture micro angle/lighting variations
                    if poseEmbeddings.count >= 3 {
                        collectedEmbeddings.append(poseEmbeddings.first!)
                        collectedEmbeddings.append(poseEmbeddings.last!)
                    }
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
    
    // MARK: - Mac Unlock Execution handled by NotchPulseFaceUnlockCoordinator
}
