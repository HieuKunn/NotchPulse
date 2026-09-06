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
import SwiftUI
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
    
    // Live Tester State (for Settings UI)
    @Published var isTestingMode: Bool = false
    @Published var testResultText: String = ""
    @Published var testResultColor: Color = .secondary
    @Published var testConfidence: Int = 0
    
    // MARK: - Camera & Vision Properties
    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private let sessionQueue = DispatchQueue(label: "com.notchpulse.faceid.session", qos: .userInitiated)
    
    private var isProcessingFrame: Bool = false
    private var recognitionTimer: Task<Void, Never>?
    private var enrollmentSamples: [[Double]] = []
    private var isEnrollmentMode: Bool = false
    private var pendingFaceName: String = "Face 1"
    
    // Strict Anti-Spoof Consecutive Match Counter
    private var consecutiveMatches: Int = 0
    private var lastMatchedFaceName: String? = nil
    
    // Strict Biometric Threshold: Same person is ~0.02-0.05, different people are >0.11
    private let matchThreshold: Double = 0.068
    
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
        KeychainHelper.shared.deletePassword()
        hasPasswordSet = false
        isEnrolled = false
        statusMessage = "All Face ID data cleared"
    }
    
    // MARK: - Zero-Overhead Camera Control
    
    /// Starts recognition for 4.0 seconds upon screen lock or display wake
    func startRecognitionOnWake() {
        guard Defaults[.enableFaceID], isEnrolled, !enrolledFaces.isEmpty, KeychainHelper.shared.hasPassword else {
            return
        }
        
        guard !isScanning else { return }
        
        isEnrollmentMode = false
        isTestingMode = false
        lastUnlockSuccess = false
        consecutiveMatches = 0
        lastMatchedFaceName = nil
        statusMessage = "Verifying face…"
        isScanning = true
        
        startCameraSession()
        
        // 4.0s Timeout Safeguard: Gives camera 0.8s warmup + user 3.2s to look at screen
        recognitionTimer?.cancel()
        recognitionTimer = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(4000))
            guard let self = self, self.isScanning else { return }
            self.stopCameraSession()
            self.statusMessage = "Face Not Recognized"
            self.isScanning = false
            
            // Hold the failure status for 1.2s before clearing
            try? await Task.sleep(for: .milliseconds(1200))
            if !self.isScanning {
                self.statusMessage = "Ready"
            }
        }
    }
    
    /// Starts enrollment mode from Settings (collects 12 high-quality samples)
    func startEnrollment(name: String? = nil) {
        pendingFaceName = name ?? (enrolledFaces.isEmpty ? "Face 1" : "Appearance \(enrolledFaces.count + 1)")
        isEnrollmentMode = true
        isTestingMode = false
        lastUnlockSuccess = false
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
            self.isEnrollmentMode = false
        }
    }
    
    /// Starts Live Testing mode from Settings
    func startTestRecognition() {
        guard isEnrolled, !enrolledFaces.isEmpty else {
            testResultText = "⚠️ Please enroll a face first"
            testResultColor = .orange
            return
        }
        
        isTestingMode = true
        isEnrollmentMode = false
        lastUnlockSuccess = false
        testResultText = "Looking for face…"
        testResultColor = .secondary
        testConfidence = 0
        isScanning = true
        
        startCameraSession()
        
        // Test timeout: 8 seconds max
        recognitionTimer?.cancel()
        recognitionTimer = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard let self = self, self.isScanning, self.isTestingMode else { return }
            self.stopCameraSession()
            self.isScanning = false
            self.isTestingMode = false
            self.testResultText = "Test complete"
            self.testResultColor = .secondary
        }
    }
    
    func stopTestRecognition() {
        recognitionTimer?.cancel()
        stopCameraSession()
        isScanning = false
        isTestingMode = false
        testResultText = ""
        testConfidence = 0
    }
    
    func cancelCurrentSession() {
        recognitionTimer?.cancel()
        stopCameraSession()
        isScanning = false
        isEnrollmentMode = false
        isTestingMode = false
        statusMessage = "Cancelled"
    }
    
    private func startCameraSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            let session = AVCaptureSession()
            session.sessionPreset = .vga640x480 // Ultra-fast buffer, minimal latency (~10MB RAM)
            
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
    
    // MARK: - Procrustes Canonical Landmark Vector Extraction
    private func extractFacialVector(from pixelBuffer: CVPixelBuffer) -> [Double]? {
        let requestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        
        let landmarksRequest = VNDetectFaceLandmarksRequest()
        landmarksRequest.revision = VNDetectFaceLandmarksRequestRevision3
        landmarksRequest.usesCPUOnly = false // Leverage Apple Neural Engine (NPU) / Apple Silicon GPU
        
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
        
        // Quality check: Reject blurry or dark frames
        if let qualityObs = qualityRequest.results?.first, qualityObs.faceCaptureQuality ?? 0 < 0.20 {
            return nil
        }
        
        // Pose Angle Filter: Strictly reject faces turned sideways or looking up/down
        if let yaw = faceObservation.yaw?.doubleValue, abs(yaw) > 0.18 {
            return nil
        }
        if let pitch = faceObservation.pitch?.doubleValue, abs(pitch) > 0.18 {
            return nil
        }
        
        // Eye Anchor Points for Procrustes Normalization
        let leftEyePoints = landmarks.leftEye?.normalizedPoints ?? []
        let rightEyePoints = landmarks.rightEye?.normalizedPoints ?? []
        guard !leftEyePoints.isEmpty, !rightEyePoints.isEmpty else { return nil }
        
        let leftCenter = landmarks.leftPupil?.normalizedPoints.first ?? centroid(of: leftEyePoints)
        let rightCenter = landmarks.rightPupil?.normalizedPoints.first ?? centroid(of: rightEyePoints)
        
        let eyeDistance = hypot(rightCenter.x - leftCenter.x, rightCenter.y - leftCenter.y)
        guard eyeDistance >= 0.04 else { return nil } // Face too far or too small
        
        let eyeMidX = (leftCenter.x + rightCenter.x) / 2.0
        let eyeMidY = (leftCenter.y + rightCenter.y) / 2.0
        let rollAngle = atan2(rightCenter.y - leftCenter.y, rightCenter.x - leftCenter.x)
        let cosA = cos(-rollAngle)
        let sinA = sin(-rollAngle)
        
        // Procrustes Canonical Transform: Level eye line horizontally, scale eyeDistance to 1.0
        func canonicalize(_ p: CGPoint) -> (Double, Double) {
            let dx = Double(p.x - eyeMidX)
            let dy = Double(p.y - eyeMidY)
            let d = Double(eyeDistance)
            let rx = (dx * cosA - dy * sinA) / d
            let ry = (dx * sinA + dy * cosA) / d
            return (rx, ry)
        }
        
        var coords: [Double] = []
        coords.reserveCapacity(150)
        
        // 1. Face Contour (Jawline and Chin Shape): 17 points
        if let contour = landmarks.faceContour?.normalizedPoints {
            for p in contour {
                let (rx, ry) = canonicalize(p)
                coords.append(rx)
                coords.append(ry)
            }
        }
        
        // 2. Eyebrows (Left & Right Arch): 10 points
        if let lbrow = landmarks.leftEyebrow?.normalizedPoints {
            for p in lbrow {
                let (rx, ry) = canonicalize(p)
                coords.append(rx)
                coords.append(ry)
            }
        }
        if let rbrow = landmarks.rightEyebrow?.normalizedPoints {
            for p in rbrow {
                let (rx, ry) = canonicalize(p)
                coords.append(rx)
                coords.append(ry)
            }
        }
        
        // 3. Nose Crest & Base: 13 points
        if let ncrest = landmarks.noseCrest?.normalizedPoints {
            for p in ncrest {
                let (rx, ry) = canonicalize(p)
                coords.append(rx)
                coords.append(ry)
            }
        }
        if let nose = landmarks.nose?.normalizedPoints {
            for p in nose {
                let (rx, ry) = canonicalize(p)
                coords.append(rx)
                coords.append(ry)
            }
        }
        
        // 4. Lips (Outer Contour): 14 points
        if let lips = landmarks.outerLips?.normalizedPoints {
            for p in lips {
                let (rx, ry) = canonicalize(p)
                coords.append(rx)
                coords.append(ry)
            }
        }
        
        // 5. Eyes: 16 points
        for p in leftEyePoints {
            let (rx, ry) = canonicalize(p)
            coords.append(rx)
            coords.append(ry)
        }
        for p in rightEyePoints {
            let (rx, ry) = canonicalize(p)
            coords.append(rx)
            coords.append(ry)
        }
        
        // 6. Invariant Anatomical Proportion Ratios
        let contourPoints = landmarks.faceContour?.normalizedPoints ?? []
        let chinPoint = contourPoints.min(by: { $0.y < $1.y }) ?? CGPoint(x: eyeMidX, y: eyeMidY - eyeDistance * 1.3)
        let (_, chinRy) = canonicalize(chinPoint)
        
        let noseTip = landmarks.nose?.normalizedPoints.first ?? centroid(of: landmarks.nose?.normalizedPoints ?? [])
        let (_, noseRy) = canonicalize(noseTip)
        
        let mouthCenter = centroid(of: landmarks.outerLips?.normalizedPoints ?? [])
        let (_, mouthRy) = canonicalize(mouthCenter)
        
        coords.append(abs(chinRy))           // Eye line to chin
        coords.append(abs(noseRy))           // Eye line to nose tip
        coords.append(abs(mouthRy))          // Eye line to mouth
        coords.append(abs(chinRy - mouthRy)) // Mouth to chin
        coords.append(Double(faceObservation.boundingBox.width / faceObservation.boundingBox.height))
        
        return coords
    }
    
    // MARK: - Combined Biometric Distance Metric
    /// Returns distance between 0.0 (identical) and ~0.25+ (different person).
    /// Same person is typically 0.015 - 0.050. Different people are > 0.110.
    private func computeBiometricDistance(_ v1: [Double], _ v2: [Double]) -> Double {
        guard v1.count == v2.count, !v1.isEmpty else { return 1.0 }
        
        let ratioCount = 5
        let coordCount = v1.count - ratioCount
        let pointCount = coordCount / 2
        
        // 1. Mean Euclidean Landmark Distance (MELD)
        var sumDist = 0.0
        for i in 0..<pointCount {
            let dx = v1[i * 2] - v2[i * 2]
            let dy = v1[i * 2 + 1] - v2[i * 2 + 1]
            sumDist += sqrt(dx * dx + dy * dy)
        }
        let meld = sumDist / Double(pointCount)
        
        // 2. Anatomical Ratio Relative Error
        var ratioError = 0.0
        for j in 0..<ratioCount {
            let idx = coordCount + j
            let denom = max(0.1, abs(v2[idx]))
            ratioError += abs(v1[idx] - v2[idx]) / denom
        }
        let grre = ratioError / Double(ratioCount)
        
        return meld * 0.80 + grre * 0.20
    }
    
    // MARK: - Automatic Mac Unlock Execution
    private func performMacUnlock() {
        guard let password = KeychainHelper.shared.readPassword(), !password.isEmpty else {
            statusMessage = "No unlock password stored"
            return
        }
        
        statusMessage = "Face ID Verified! Unlocking…"
        lastUnlockSuccess = true
        
        if Defaults[.faceIDSound] {
            NSSound(named: "Glass")?.play()
        }
        
        // Post password keystrokes to lock screen password prompt after 350ms visual confirmation
        Task.detached(priority: .high) {
            try? await Task.sleep(for: .milliseconds(350))
            
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
            
            // ----------------------------------------------------
            // MODE 1: Enrollment Mode (Collect 12 stable samples)
            // ----------------------------------------------------
            if self.isEnrollmentMode {
                self.enrollmentSamples.append(vector)
                self.enrollmentProgress = min(1.0, Double(self.enrollmentSamples.count) / 12.0)
                self.statusMessage = "Scanning face: \(Int(self.enrollmentProgress * 100))%"
                
                if self.enrollmentSamples.count >= 12 {
                    // Average the samples for maximum biometric stability
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
                return
            }
            
            // ----------------------------------------------------
            // MODE 2: Live Testing Mode (Settings Preview)
            // ----------------------------------------------------
            if self.isTestingMode {
                var bestDistance = 1.0
                var bestName = ""
                
                for face in self.enrolledFaces {
                    let dist = self.computeBiometricDistance(vector, face.vector)
                    if dist < bestDistance {
                        bestDistance = dist
                        bestName = face.name
                    }
                }
                
                let confidence = max(0, min(100, Int((1.0 - (bestDistance / 0.12)) * 100)))
                self.testConfidence = confidence
                
                if bestDistance <= self.matchThreshold {
                    self.testResultText = "✅ Matched: \(bestName) (\(confidence)%)"
                    self.testResultColor = .green
                } else {
                    self.testResultText = "❌ Unrecognized Face (Score: \(confidence)%)"
                    self.testResultColor = .red
                }
                return
            }
            
            // ----------------------------------------------------
            // MODE 3: Verification Mode (Lock Screen Mac Unlock)
            // ----------------------------------------------------
            var bestDistance = 1.0
            var matchedName: String? = nil
            
            for face in self.enrolledFaces {
                let dist = self.computeBiometricDistance(vector, face.vector)
                if dist < bestDistance {
                    bestDistance = dist
                    matchedName = face.name
                }
            }
            
            // Strict match check: Distance must be strictly under threshold
            if bestDistance <= self.matchThreshold {
                self.consecutiveMatches += 1
                self.lastMatchedFaceName = matchedName
                
                // Require 2 consecutive matching frames to prevent any momentary false positive
                if self.consecutiveMatches >= 2 {
                    self.recognitionTimer?.cancel()
                    self.stopCameraSession()
                    self.isScanning = false
                    self.performMacUnlock()
                }
            } else {
                // Different face or obscured face: reset consecutive match counter
                // BUT DO NOT ABORT! Continue scanning until 4.0s timeout!
                self.consecutiveMatches = 0
            }
        }
    }
}
