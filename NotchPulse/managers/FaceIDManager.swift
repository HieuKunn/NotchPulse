//
//  FaceIDManager.swift
//  NotchPulse
//
//  Created for NotchPulse v2.0 - Face ID Unlock (Zero-Overhead)
//

import AVFoundation
import Cocoa
import Combine
import Defaults
import Foundation
import Vision

struct EnrolledFace: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var createdAt: Date = Date()
    var vector: [Double]
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
    
    // MARK: - Camera & Vision Properties
    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private let sessionQueue = DispatchQueue(label: "com.notchpulse.faceid.session", qos: .userInitiated)
    
    private var isProcessingFrame: Bool = false
    private var recognitionTimer: Task<Void, Never>?
    private var enrollmentSamples: [[Double]] = []
    private var isEnrollmentMode: Bool = false
    private var pendingFaceName: String = "Face 1"
    
    private let profilesFileName = "faceid_profiles.json"
    private var profilesURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("NotchPulse", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(profilesFileName)
    }
    
    // MARK: - Initialization
    override private init() {
        super.init()
        loadEnrolledFaces()
        hasPasswordSet = KeychainHelper.shared.hasPassword
    }
    
    // MARK: - Template Management
    private func loadEnrolledFaces() {
        if let data = try? Data(contentsOf: profilesURL),
           let faces = try? JSONDecoder().decode([EnrolledFace].self, from: data) {
            self.enrolledFaces = faces
            self.isEnrolled = !faces.isEmpty
            return
        }
        
        // Backward compatibility migration from legacy template file
        let legacyURL = profilesURL.deletingLastPathComponent().appendingPathComponent("faceid_template.dat")
        if let data = try? Data(contentsOf: legacyURL),
           let legacyTemplate = try? JSONDecoder().decode([Double].self, from: data),
           !legacyTemplate.isEmpty {
            let migratedFace = EnrolledFace(name: "Face 1", vector: legacyTemplate)
            self.enrolledFaces = [migratedFace]
            self.isEnrolled = true
            saveEnrolledFaces()
            try? FileManager.default.removeItem(at: legacyURL)
            return
        }
        
        self.enrolledFaces = []
        self.isEnrolled = false
    }
    
    private func saveEnrolledFaces() {
        if let data = try? JSONEncoder().encode(enrolledFaces) {
            try? data.write(to: profilesURL, options: .atomic)
        }
        self.isEnrolled = !enrolledFaces.isEmpty
    }
    
    func addEnrolledFace(_ face: EnrolledFace) {
        enrolledFaces.append(face)
        saveEnrolledFaces()
        statusMessage = "Added \(face.name) successfully"
    }
    
    func deleteFace(id: UUID) {
        enrolledFaces.removeAll { $0.id == id }
        saveEnrolledFaces()
        if enrolledFaces.isEmpty {
            KeychainHelper.shared.deletePassword()
            hasPasswordSet = false
            statusMessage = "All Face IDs cleared"
        } else {
            statusMessage = "Face ID removed"
        }
    }
    
    func resetEnrollment() {
        enrolledFaces.removeAll()
        saveEnrolledFaces()
        try? FileManager.default.removeItem(at: profilesURL)
        let legacyURL = profilesURL.deletingLastPathComponent().appendingPathComponent("faceid_template.dat")
        try? FileManager.default.removeItem(at: legacyURL)
        KeychainHelper.shared.deletePassword()
        hasPasswordSet = false
        isEnrolled = false
        statusMessage = "All Face ID data cleared"
    }
    
    // MARK: - Zero-Overhead Camera Control
    
    /// Starts recognition for exactly 1.5s upon screen wake
    func startRecognitionOnWake() {
        guard Defaults[.enableFaceID], isEnrolled, !enrolledFaces.isEmpty, KeychainHelper.shared.hasPassword else {
            return
        }
        
        guard !isScanning else { return }
        
        isEnrollmentMode = false
        statusMessage = "Verifying face…"
        isScanning = true
        
        startCameraSession()
        
        // Anti-drain Hard Timeout Safeguard: cancel after 1.5s max!
        recognitionTimer?.cancel()
        recognitionTimer = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            guard let self = self, self.isScanning else { return }
            self.stopCameraSession()
            self.statusMessage = "Verification timed out"
            self.isScanning = false
        }
    }
    
    /// Starts enrollment mode from Settings
    func startEnrollment(name: String? = nil) {
        pendingFaceName = name ?? (enrolledFaces.isEmpty ? "Face 1" : "Alternative Appearance \(enrolledFaces.count + 1)")
        isEnrollmentMode = true
        enrollmentSamples.removeAll()
        enrollmentProgress = 0.0
        statusMessage = "Look directly at the camera…"
        isScanning = true
        
        startCameraSession()
        
        // Enrollment timeout: 15 seconds max
        recognitionTimer?.cancel()
        recognitionTimer = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard let self = self, self.isScanning, self.isEnrollmentMode else { return }
            self.stopCameraSession()
            self.statusMessage = "Enrollment timed out. Please try again."
            self.isScanning = false
        }
    }
    
    func cancelCurrentSession() {
        recognitionTimer?.cancel()
        stopCameraSession()
        isScanning = false
        statusMessage = "Cancelled"
    }
    
    private func startCameraSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            let session = AVCaptureSession()
            session.sessionPreset = .vga640x480 // Ultra-fast buffer, minimal latency and ~10MB RAM footprint
            
            // Find front-facing or default video device
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                    ?? AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device) else {
                Task { @MainActor in
                    self.statusMessage = "Camera unavailable"
                    self.isScanning = false
                }
                return
            }
            
            if session.canAddInput(input) {
                session.addInput(input)
            }
            
            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            output.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
            ]
            output.setSampleBufferDelegate(self, queue: self.sessionQueue)
            
            if session.canAddOutput(output) {
                session.addOutput(output)
            }
            
            session.startRunning()
            
            Task { @MainActor in
                self.captureSession = session
                self.videoOutput = output
            }
        }
    }
    
    private func stopCameraSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if let session = self.captureSession, session.isRunning {
                session.stopRunning()
            }
            Task { @MainActor in
                self.captureSession = nil
                self.videoOutput = nil
                self.isProcessingFrame = false
            }
        }
    }
    
    // MARK: - Facial Landmark Vector Extraction
    private func extractFacialVector(from pixelBuffer: CVPixelBuffer) -> [Double]? {
        let requestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        
        let landmarksRequest = VNDetectFaceLandmarksRequest()
        landmarksRequest.usesCPUOnly = false // Leverage Apple Neural Engine (NPU) / Apple Silicon GPU!
        
        let qualityRequest = VNDetectFaceCaptureQualityRequest()
        qualityRequest.usesCPUOnly = false
        
        do {
            try requestHandler.perform([landmarksRequest, qualityRequest])
        } catch {
            return nil
        }
        
        guard let faceObservation = landmarksRequest.results?.first,
              let landmarks = faceObservation.landmarks else {
            return nil
        }
        
        // Ensure face capture quality is acceptable
        if let qualityObs = qualityRequest.results?.first, qualityObs.faceCaptureQuality ?? 0 < 0.25 {
            return nil
        }
        
        // Extract normalized geometric ratios from facial landmarks
        guard let leftEye = landmarks.leftEye,
              let rightEye = landmarks.rightEye,
              let nose = landmarks.nose,
              let outerLips = landmarks.outerLips else {
            return nil
        }
        
        let lEyeCenter = centroid(of: leftEye.normalizedPoints)
        let rEyeCenter = centroid(of: rightEye.normalizedPoints)
        let noseCenter = centroid(of: nose.normalizedPoints)
        let mouthCenter = centroid(of: outerLips.normalizedPoints)
        
        let eyeDistance = distance(lEyeCenter, rEyeCenter)
        guard eyeDistance > 0.05 else { return nil } // Face too small
        
        let noseToMouth = distance(noseCenter, mouthCenter)
        let leftEyeToNose = distance(lEyeCenter, noseCenter)
        let rightEyeToNose = distance(rEyeCenter, noseCenter)
        let leftEyeToMouth = distance(lEyeCenter, mouthCenter)
        let rightEyeToMouth = distance(rEyeCenter, mouthCenter)
        
        // Normalize geometric distances relative to inter-pupillary distance (eye distance)
        let featureVector: [Double] = [
            Double(noseToMouth / eyeDistance),
            Double(leftEyeToNose / eyeDistance),
            Double(rightEyeToNose / eyeDistance),
            Double(leftEyeToMouth / eyeDistance),
            Double(rightEyeToMouth / eyeDistance),
            Double(faceObservation.boundingBox.width / faceObservation.boundingBox.height),
            Double(abs(leftEyeToNose - rightEyeToNose) / eyeDistance) // Symmetry metric
        ]
        
        return featureVector
    }
    
    // MARK: - Cosine Similarity Verification
    private func computeSimilarity(_ v1: [Double], _ v2: [Double]) -> Double {
        guard v1.count == v2.count, !v1.isEmpty else { return 0.0 }
        
        var dot: Double = 0.0
        var mag1: Double = 0.0
        var mag2: Double = 0.0
        
        for i in 0..<v1.count {
            dot += v1[i] * v2[i]
            mag1 += v1[i] * v1[i]
            mag2 += v2[i] * v2[i]
        }
        
        let denominator = (sqrt(mag1) * sqrt(mag2))
        guard denominator > 0 else { return 0.0 }
        return dot / denominator
    }
    
    // MARK: - Automatic Mac Unlock Execution
    private func performMacUnlock() {
        guard let password = KeychainHelper.shared.readPassword(), !password.isEmpty else {
            statusMessage = "No unlock password stored"
            return
        }
        
        statusMessage = "Face ID Verified! Unlocking…"
        lastUnlockSuccess = true
        
        // Play Face ID chime sound if enabled
        if Defaults[.faceIDSound] {
            NSSound(named: "Glass")?.play()
        }
        
        // Post password keystrokes to lock screen password prompt
        Task.detached(priority: .high) {
            // Short delay to ensure lock screen input is ready
            try? await Task.sleep(for: .milliseconds(50))
            
            for char in password {
                let str = String(char)
                let utf16Chars = Array(str.utf16)
                if let eventDown = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
                   let eventUp = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) {
                    eventDown.keyboardSetUnicodeString(stringLength: utf16Chars.count, unicodeString: utf16Chars)
                    eventUp.keyboardSetUnicodeString(stringLength: utf16Chars.count, unicodeString: utf16Chars)
                    eventDown.post(tap: .cghidEventTap)
                    eventUp.post(tap: .cghidEventTap)
                }
                try? await Task.sleep(for: .milliseconds(15))
            }
            
            // Press Return key (0x24)
            if let returnDown = CGEvent(keyboardEventSource: nil, virtualKey: 0x24, keyDown: true),
               let returnUp = CGEvent(keyboardEventSource: nil, virtualKey: 0x24, keyDown: false) {
                returnDown.post(tap: .cghidEventTap)
                returnUp.post(tap: .cghidEventTap)
            }
        }
    }
    
    // MARK: - Mathematical Helpers
    private func centroid(of points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else { return .zero }
        let sum = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        return CGPoint(x: sum.x / CGFloat(points.count), y: sum.y / CGFloat(points.count))
    }
    
    private func distance(_ p1: CGPoint, _ p2: CGPoint) -> CGFloat {
        hypot(p1.x - p2.x, p1.y - p2.y)
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension FaceIDManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        Task { @MainActor [weak self] in
            guard let self = self, self.isScanning, !self.isProcessingFrame else { return }
            self.isProcessingFrame = true
            defer { self.isProcessingFrame = false }
            
            guard let vector = self.extractFacialVector(from: pixelBuffer) else { return }
            
            if self.isEnrollmentMode {
                // Enrollment mode: collect 5 consistent samples
                self.enrollmentSamples.append(vector)
                self.enrollmentProgress = min(1.0, Double(self.enrollmentSamples.count) / 5.0)
                self.statusMessage = "Scanning face: \(Int(self.enrollmentProgress * 100))%"
                
                if self.enrollmentSamples.count >= 5 {
                    // Average the vectors
                    var averaged = [Double](repeating: 0.0, count: vector.count)
                    for sample in self.enrollmentSamples {
                        for i in 0..<vector.count {
                            averaged[i] += sample[i] / Double(self.enrollmentSamples.count)
                        }
                    }
                    let newFace = EnrolledFace(name: self.pendingFaceName, vector: averaged)
                    self.addEnrolledFace(newFace)
                    self.recognitionTimer?.cancel()
                    self.stopCameraSession()
                    self.isScanning = false
                    self.isEnrollmentMode = false
                    self.statusMessage = "Face ID (\(newFace.name)) Enrolled! 🎉"
                    if Defaults[.faceIDSound] {
                        NSSound(named: "Ping")?.play()
                    }
                }
            } else {
                // Verification mode: match against all enrolled faces
                for face in self.enrolledFaces {
                    let similarity = self.computeSimilarity(vector, face.vector)
                    if similarity >= 0.94 {
                        self.recognitionTimer?.cancel()
                        self.stopCameraSession()
                        self.isScanning = false
                        self.performMacUnlock()
                        return
                    }
                }
            }
        }
    }
}
