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
        case .frontal: return "Nhìn thẳng vào camera"
        case .lookLeft: return "Nghiêng nhẹ sang trái"
        case .lookRight: return "Nghiêng nhẹ sang phải"
        case .lookUp: return "Hơi ngước đầu lên"
        case .lookDown: return "Hơi cúi đầu xuống"
        case .smile: return "Mỉm cười một chút"
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
        case .noFaceDetected: return "Không tìm thấy khuôn mặt"
        case .multipleFacesDetected: return "Phát hiện nhiều hơn 1 khuôn mặt"
        case .alignmentFailed: return "Không thể căn chỉnh khuôn mặt"
        case .embeddingFailed: return "Trích xuất đặc trưng thất bại"
        case .qualityTooLow: return "Chất lượng hình ảnh quá thấp"
        case .sessionLocked: return "Phiên bảo mật đang bị khoá"
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
    private let embedder: NotchPulseFaceEmbedder = (try? NotchPulseArcFaceEmbedder()) ?? NotchPulseVisionFeaturePrintEmbedder()
    
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
        guard let face = faces.first else {
            throw NotchPulseEnrollmentError.noFaceDetected
        }
        guard faces.count == 1 else {
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
        guard let identity = identities.first(where: { $0.isEnabled && !$0.samples.isEmpty }),
              let template = identity.template else {
            return VerifyResult(matched: false, similarity: 0)
        }
        
        let similarity = FaceEmbedding.cosineSimilarity(currentEmbedding, template)
        let threshold: Float = (embedder.embeddingDimension == 512) ? 0.40 : 0.60
        let matched = similarity >= threshold
        return VerifyResult(matched: matched, similarity: similarity)
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
                guard let buffer = self.camera.currentFrame?.image else {
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
