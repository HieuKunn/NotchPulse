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

enum FacePose: String, CaseIterable, Identifiable {
    case frontal = "frontal"
    case lookLeft = "lookLeft"
    case lookRight = "lookRight"
    case lookUp = "lookUp"
    case lookDown = "lookDown"
    case smile = "smile"
    
    var id: String { rawValue }
    
    var prompt: String {
        switch self {
        case .frontal: return "Look straight at the camera"
        case .lookLeft: return "Tilt head slightly to the left"
        case .lookRight: return "Tilt head slightly to the right"
        case .lookUp: return "Tilt head slightly up"
        case .lookDown: return "Tilt head slightly down"
        case .smile: return "Smile slightly"
        }
    }
    
    func matches(yaw: Double, roll: Double, faceWidth: CGFloat) -> Bool {
        switch self {
        case .frontal, .smile:
            return abs(yaw) < 0.25 && abs(roll) < 0.25
        case .lookLeft:
            return yaw > 0.15
        case .lookRight:
            return yaw < -0.15
        case .lookUp:
            return roll > 0.12 || abs(yaw) < 0.3
        case .lookDown:
            return roll < -0.12 || abs(yaw) < 0.3
        }
    }
}

enum NotchPulseEnrollmentError: LocalizedError {
    case noFaceDetected
    case multipleFacesDetected
    case alignmentFailed
    case embeddingFailed
    case qualityTooLow
    case sessionLocked
    
    var errorDescription: String? {
        switch self {
        case .noFaceDetected: return "No face detected"
        case .multipleFacesDetected: return "More than one face detected"
        case .alignmentFailed: return "Failed to align face"
        case .embeddingFailed: return "Failed to extract face features"
        case .qualityTooLow: return "Image quality too low"
        case .sessionLocked: return "Security session locked"
        }
    }
}

struct FrameAnalysis {
    let face: DetectedFace
    let embedding: [Float]
    let quality: Float
    let yaw: Double
    let roll: Double
}

struct VerifyResult {
    let matched: Bool
    let similarity: Float
}

final class NotchPulseEnrollmentService: @unchecked Sendable {
    static let minimumCaptureQuality: Float = 0.35
    private var embedder: NotchPulseFaceEmbedder {
        NotchPulseVisionFeaturePrintEmbedder()
    }
    
    static func hasEnrolledFace() -> Bool {
        do {
            let identities = try NotchPulseSecureFaceStore.load()
            return !identities.isEmpty && identities.contains { !$0.samples.isEmpty }
        } catch {
            return false
        }
    }
    
    static func deleteEnrolledFace() throws {
        NotchPulseSecureFaceStore.deleteAll()
    }
    
    func analyzeFrame(_ image: CGImage, includeQuality: Bool = true) throws -> FrameAnalysis {
        let faces = try NotchPulseFaceDetector.detectFaces(in: image)
        guard let face = NotchPulseFaceRecognitionPipeline.selectDominantFace(in: faces) ?? faces.first else {
            throw NotchPulseEnrollmentError.noFaceDetected
        }
        if includeQuality && faces.count > 1 {
            throw NotchPulseEnrollmentError.multipleFacesDetected
        }
        
        guard let aligned = NotchPulseFaceAligner.align(face, from: image) else {
            throw NotchPulseEnrollmentError.alignmentFailed
        }
        
        let embedding = try embedder.embedding(for: aligned.image)
        let quality = face.quality ?? 0.8
        let yaw = Double(face.yaw ?? 0.0)
        let roll = Double(face.roll ?? 0.0)
        
        return FrameAnalysis(face: face, embedding: embedding, quality: quality, yaw: yaw, roll: roll)
    }
    
    func saveEmbeddings(_ embeddings: [[Float]]) throws {
        let samples = embeddings.map { emb in
            FaceSample(embedding: emb, pose: nil, capturedAt: Date(), quality: 0.9)
        }
        let identity = FaceIdentity(
            id: UUID(),
            name: "My Face",
            samples: samples,
            modelIdentifier: embedder.modelIdentifier,
            embeddingDimension: embedder.embeddingDimension,
            createdAt: Date(),
            isEnabled: true
        )
        try NotchPulseSecureFaceStore.save([identity])
    }
    
    func verify(currentEmbedding: [Float]) throws -> VerifyResult {
        let identities = try NotchPulseSecureFaceStore.load()
        guard let identity = identities.first(where: { $0.isEnabled && !$0.samples.isEmpty }) else {
            return VerifyResult(matched: false, similarity: 0)
        }
        
        let sampleSimilarities = identity.samples.map { FaceEmbedding.cosineSimilarity(currentEmbedding, $0.embedding) }
        let maxSampleSim = sampleSimilarities.max() ?? 0
        let centroidSim = identity.template.map { FaceEmbedding.cosineSimilarity(currentEmbedding, $0) } ?? 0
        let bestSimilarity = max(maxSampleSim, centroidSim)
        
        // ArcFace 512D threshold: 0.33 allows secure recognition without compromising security
        let threshold: Float = (embedder.embeddingDimension == 512) ? 0.33 : 0.52
        let matched = bestSimilarity >= threshold
        return VerifyResult(matched: matched, similarity: bestSimilarity)
    }
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
    private let pipeline = NotchPulseFaceRecognitionPipeline()
    
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
            NotchPulseFaceEnrollmentStore.shared.reloadIfUnlocked()
        } else {
            enrolledFaces = []
        }
        if hasPasswordSet {
            Task.detached(priority: .background) {
                _ = try? NotchPulseVault.readPassword()
            }
        }
    }
    
    func ensureSessionUnlocked() async -> Bool {
        if NotchPulseVault.isSessionUnlocked { return true }
        if NotchPulseVault.hasSessionKey() {
            do {
                try await Task.detached(priority: .userInitiated) { () -> Void in
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
        NotchPulseFaceEnrollmentStore.shared.deleteAll()
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
    
    /// Dedicated face verification for macOS system authorization & Touch ID prompts (SecurityAgent & LocalAuthentication).
    /// Operates while the desktop is unlocked without invoking lock screen wake mechanisms.
    func verifyForSystemPrompt(timeoutSeconds: Double = 6.0) async -> Bool {
        guard isEnrolled, hasPasswordSet else { return false }
        
        let unlocked = await ensureSessionUnlocked()
        guard unlocked else { return false }
        
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
        guard !activeIdentities.isEmpty else { return false }
        
        isScanning = true
        lastUnlockSuccess = false
        statusMessage = "Looking for your face…"
        
        await camera.requestAccessAndStart()
        defer {
            camera.stop()
            isScanning = false
        }
        
        let startTime = ContinuousClock.now
        let threshold: Float = (pipeline.embedder.embeddingDimension == 512) ? 0.33 : 0.52
        var lastProcessedFrameID: UInt64?
        
        let liveness = NotchPulseLivenessAnalyzer()
        liveness.modeProvider = { .light }
        var livenessConfirmed = false
        
        while ContinuousClock.now - startTime < .seconds(timeoutSeconds), !Task.isCancelled {
            guard let frame = camera.currentFrame, frame.id != lastProcessedFrameID else {
                try? await Task.sleep(nanoseconds: 20_000_000)
                continue
            }
            lastProcessedFrameID = frame.id
            
            let pipeline = self.pipeline
            let outcome = await Task.detached(priority: .userInitiated) { () -> (FaceRecognitionResult, LivenessFrame)? in
                guard let result = try? pipeline.recognize(in: frame.image) else { return nil }
                let faceCrop = NotchPulseCamera.renderCrop(from: frame, imageRect: result.face.boundingBox)
                return (result, NotchPulseLivenessFeatureExtractor.extract(from: result, frame: frame.image, faceCrop: faceCrop))
            }.value
            
            guard let (result, livenessFrame) = outcome else {
                try? await Task.sleep(nanoseconds: 20_000_000)
                continue
            }
            
            let snapshot = liveness.observe(livenessFrame)
            switch snapshot.decision {
            case .denied(by: let cue):
                print("[FaceID SystemAuth] Liveness denied: \(cue)")
                try? await Task.sleep(nanoseconds: 80_000_000)
                continue
            case .confirmed(by: _):
                livenessConfirmed = true
            default:
                break
            }
            
            let scored = pipeline.score(result.embedding, against: activeIdentities)
            if let _ = pipeline.bestMatch(in: scored, threshold: threshold) {
                if !livenessConfirmed {
                    try? await Task.sleep(nanoseconds: 30_000_000)
                    continue
                }
                
                lastUnlockSuccess = true
                statusMessage = "Recognized"
                if Defaults[.faceIDSound] {
                    NSSound(named: "Glass")?.play()
                }
                return true
            }
            
            try? await Task.sleep(nanoseconds: 30_000_000)
        }
        
        statusMessage = "Face Not Recognized"
        return false
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
            defer {
                self.camera.stop()
                self.isScanning = false
                self.isEnrollmentMode = false
            }
            
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
                    
                    guard let buffer = self.camera.currentFrame?.image else {
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
                    
                    try? await Task.sleep(for: .milliseconds(40))
                }
                
                if Task.isCancelled { return }
                
                // Average the frames for this pose + save key pose samples for rich representation
                if !poseEmbeddings.isEmpty {
                    if let avgEmbedding = FaceEmbedding.average(poseEmbeddings) {
                        collectedEmbeddings.append(avgEmbedding)
                    }
                    
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
                NotchPulseFaceEnrollmentStore.shared.reloadIfUnlocked()
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
            defer {
                self.camera.stop()
                self.isScanning = false
                self.isTestingMode = false
                if self.testResultText == "Looking for face..." || self.testResultText == "Searching..." {
                    self.testResultText = "Test complete"
                    self.testResultColor = .secondary
                }
            }
            
            let startTime = Date()
            while !Task.isCancelled && Date().timeIntervalSince(startTime) < 8.0 {
                guard let buffer = self.camera.currentFrame?.image else {
                    try? await Task.sleep(for: .milliseconds(50))
                    continue
                }
                
                do {
                    let analysis = try self.enrollmentService.analyzeFrame(buffer, includeQuality: false)
                    let result = try self.enrollmentService.verify(currentEmbedding: analysis.embedding)
                    
                    let sim = result.similarity
                    let threshold: Float = (self.pipeline.embedder.embeddingDimension == 512) ? 0.33 : 0.52
                    let confidenceVal: Int
                    if sim >= threshold {
                        confidenceVal = 70 + Int(((sim - threshold) / max(0.01, 1.0 - threshold)) * 30)
                    } else {
                        confidenceVal = Int(max(0, (sim / threshold) * 69))
                    }
                    let confidence = max(0, min(100, confidenceVal))
                    self.testConfidence = confidence
                    
                    if result.matched {
                        self.testResultText = "✅ Matched (\(confidence)%)"
                        self.testResultColor = .green
                    } else {
                        self.testResultText = "❌ Unrecognized (Score: \(confidence)%)"
                        self.testResultColor = .red
                    }
                } catch {
                    self.testResultText = "Looking for face..."
                    self.testResultColor = .secondary
                }
                try? await Task.sleep(for: .milliseconds(40))
            }
        }
    }
    
    func stopTestRecognition() {
        cancelCurrentSession()
    }
    
    // MARK: - Mac Unlock Execution handled by NotchPulseFaceUnlockCoordinator
}
