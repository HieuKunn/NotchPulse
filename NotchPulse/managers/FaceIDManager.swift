//
//  FaceIDManager.swift
//  NotchPulse
//
//  Created for NotchPulse v2.0 - Face ID Unlock (Zero-Overhead + CoreML FaceNet)
//

import AVFoundation
import Cocoa
import Combine
import CoreML
import Defaults
import Foundation
import SwiftUI
import Vision

struct EnrolledFace: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var createdAt: Date = Date()
    var vector: [Double] // Now a 512-dimensional embedding
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
    
    // Threshold for Cosine Distance (0.0 is exact match, 1.0 is orthogonal).
    // Typically < 0.35 means same person for FaceNet models.
    private let matchThreshold: Double = 0.35
    
    private let profilesFileName = "faceid_profiles.json"
    private var profilesURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("NotchPulse", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(profilesFileName)
    }
    
    // CoreML Model Setup
    private lazy var mlModel: VNCoreMLModel? = {
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all
            let model = try FaceNet(configuration: config)
            return try VNCoreMLModel(for: model.model)
        } catch {
            print("Failed to load FaceNet model: \(error)")
            return nil
        }
    }()
    
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
    func startRecognitionOnWake() {
        guard Defaults[.enableFaceID], isEnrolled, !enrolledFaces.isEmpty, KeychainHelper.shared.hasPassword else {
            return
        }
        guard !isScanning else { return }
        
        isEnrollmentMode = false
        isTestingMode = false
        lastUnlockSuccess = false
        lastUnlockSuccess = false
        consecutiveMatches = 0
        lastMatchedFaceName = nil
        statusMessage = "Verifying face…"
        isScanning = true
        
        startCameraSession()
        
        recognitionTimer?.cancel()
        recognitionTimer = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(4000))
            guard let self = self, self.isScanning else { return }
            self.stopCameraSession()
            self.statusMessage = "Face Not Recognized"
            self.isScanning = false
            
            try? await Task.sleep(for: .milliseconds(1200))
            if !self.isScanning {
                self.statusMessage = "Ready"
            }
        }
    }
    
    func startEnrollment(name: String? = nil) {
        pendingFaceName = name ?? (enrolledFaces.isEmpty ? "Face 1" : "Appearance \(enrolledFaces.count + 1)")
        isEnrollmentMode = true
        isTestingMode = false
        lastUnlockSuccess = false
        lastUnlockSuccess = false
        enrollmentSamples.removeAll()
        enrollmentProgress = 0.0
        statusMessage = "Look straight, then slightly left and right…"
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
        lastUnlockSuccess = false
            self.testResultText = "Test complete"
            self.testResultColor = .secondary
        }
    }
    
    func stopTestRecognition() {
        recognitionTimer?.cancel()
        stopCameraSession()
        isScanning = false
        isTestingMode = false
        lastUnlockSuccess = false
        testResultText = ""
        testConfidence = 0
    }
    
    func cancelCurrentSession() {
        recognitionTimer?.cancel()
        stopCameraSession()
        isScanning = false
        isEnrollmentMode = false
        isTestingMode = false
        lastUnlockSuccess = false
        statusMessage = "Cancelled"
    }
    
    private func startCameraSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            let session = AVCaptureSession()
            session.sessionPreset = .vga640x480
            
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                    ?? AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device) else {
                Task { @MainActor in
                    self.statusMessage = "Camera unavailable"
                    self.isScanning = false
                }
                return
            }
            
            if session.canAddInput(input) { session.addInput(input) }
            
            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
            output.setSampleBufferDelegate(self, queue: self.sessionQueue)
            
            if session.canAddOutput(output) { session.addOutput(output) }
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
    
    // MARK: - ML Embedding Extraction
    
    private func extractEmbedding(from pixelBuffer: CVPixelBuffer) async -> [Double]? {
        guard let mlModel = mlModel else { return nil }
        
        let requestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        
        // 1. Detect Face Rectangle
        let faceRequest = VNDetectFaceRectanglesRequest()
        faceRequest.revision = VNDetectFaceRectanglesRequestRevision3
        
        do {
            try requestHandler.perform([faceRequest])
        } catch { return nil }
        
        guard let faceObs = faceRequest.results?.first else { return nil }
        
        // 2. Crop Face accurately
        let imageWidth = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let imageHeight = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        
        // Expand bounding box slightly for better context
        var bbox = faceObs.boundingBox
        bbox.origin.x = max(0, bbox.origin.x - bbox.size.width * 0.1)
        bbox.origin.y = max(0, bbox.origin.y - bbox.size.height * 0.1)
        bbox.size.width = min(1.0 - bbox.origin.x, bbox.size.width * 1.2)
        bbox.size.height = min(1.0 - bbox.origin.y, bbox.size.height * 1.2)
        
        let cropRect = VNImageRectForNormalizedRect(bbox, Int(imageWidth), Int(imageHeight))
        
        guard let cgImage = createCGImage(from: pixelBuffer) else { return nil }
        guard let croppedCGImage = cgImage.cropping(to: cropRect) else { return nil }
        
        // 3. Feed cropped face to CoreML FaceNet
        let coreMLRequest = VNCoreMLRequest(model: mlModel)
        coreMLRequest.imageCropAndScaleOption = .scaleFill
        
        let croppedRequestHandler = VNImageRequestHandler(cgImage: croppedCGImage, options: [:])
        do {
            try croppedRequestHandler.perform([coreMLRequest])
        } catch { return nil }
        
        guard let result = coreMLRequest.results?.first as? VNCoreMLFeatureValueObservation,
              let multiArray = result.featureValue.multiArrayValue else { return nil }
        
        // 4. Extract and L2-Normalize the Vector
        let length = multiArray.count
        var vector: [Double] = []
        vector.reserveCapacity(length)
        
        var sumSquares = 0.0
        for i in 0..<length {
            let val = multiArray[i].doubleValue
            vector.append(val)
            sumSquares += val * val
        }
        
        let norm = sqrt(sumSquares)
        guard norm > 0 else { return nil }
        
        return vector.map { $0 / norm }
    }
    
    private func createCGImage(from pixelBuffer: CVPixelBuffer) -> CGImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext(options: nil)
        return context.createCGImage(ciImage, from: ciImage.extent)
    }
    
    /// Computes Cosine Distance (0.0 is perfect match, 1.0 is orthogonal)
    private func computeCosineDistance(_ v1: [Double], _ v2: [Double]) -> Double {
        guard v1.count == v2.count, !v1.isEmpty else { return 1.0 }
        
        var dotProduct = 0.0
        for i in 0..<v1.count {
            dotProduct += v1[i] * v2[i]
        }
        
        // Since vectors are already L2-normalized, Cosine Similarity is just the dot product.
        // Cosine Distance = 1 - Cosine Similarity
        return max(0.0, 1.0 - dotProduct)
    }
    
    // MARK: - Automatic Mac Unlock Execution
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
        guard let password = KeychainHelper.shared.readPassword(), !password.isEmpty else {
            statusMessage = "Chưa lưu mật khẩu mở máy trong Keychain"
            return
        }
        
        statusMessage = "Face ID Xác thực! Đang mở khoá…"
        lastUnlockSuccess = true
        
        if Defaults[.faceIDSound] {
            NSSound(named: "Glass")?.play()
        }
        
        Task.detached(priority: .high) {
            let source = CGEventSource(stateID: .combinedSessionState)
            
            if let spaceDown = CGEvent(keyboardEventSource: source, virtualKey: 0x31, keyDown: true),
               let spaceUp = CGEvent(keyboardEventSource: source, virtualKey: 0x31, keyDown: false) {
                spaceDown.post(tap: .cghidEventTap)
                try? await Task.sleep(for: .milliseconds(30))
                spaceUp.post(tap: .cghidEventTap)
            }
            
            try? await Task.sleep(for: .milliseconds(380))
            
            if let cmdADown = CGEvent(keyboardEventSource: source, virtualKey: 0x00, keyDown: true),
               let cmdAUp = CGEvent(keyboardEventSource: source, virtualKey: 0x00, keyDown: false) {
                cmdADown.flags = .maskCommand
                cmdADown.post(tap: .cghidEventTap)
                try? await Task.sleep(for: .milliseconds(25))
                cmdAUp.post(tap: .cghidEventTap)
            }
            try? await Task.sleep(for: .milliseconds(30))
            if let delDown = CGEvent(keyboardEventSource: source, virtualKey: 0x33, keyDown: true),
               let delUp = CGEvent(keyboardEventSource: source, virtualKey: 0x33, keyDown: false) {
                delDown.post(tap: .cghidEventTap)
                try? await Task.sleep(for: .milliseconds(25))
                delUp.post(tap: .cghidEventTap)
            }
            try? await Task.sleep(for: .milliseconds(60))
            
            for char in password {
                if let keyInfo = Self.keyEventInfo(for: char) {
                    if let down = CGEvent(keyboardEventSource: source, virtualKey: keyInfo.keyCode, keyDown: true),
                       let up = CGEvent(keyboardEventSource: source, virtualKey: keyInfo.keyCode, keyDown: false) {
                        if keyInfo.shift {
                            down.flags = .maskShift
                            up.flags = .maskShift
                        }
                        let utf16 = Array(String(char).utf16)
                        down.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
                        up.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
                        
                        down.post(tap: .cghidEventTap)
                        try? await Task.sleep(for: .milliseconds(22))
                        up.post(tap: .cghidEventTap)
                        try? await Task.sleep(for: .milliseconds(22))
                    }
                } else {
                    let utf16 = Array(String(char).utf16)
                    if let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                       let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
                        down.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
                        up.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
                        down.post(tap: .cghidEventTap)
                        try? await Task.sleep(for: .milliseconds(22))
                        up.post(tap: .cghidEventTap)
                        try? await Task.sleep(for: .milliseconds(22))
                    }
                }
            }
            
            try? await Task.sleep(for: .milliseconds(300))
            if let returnDown = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: true),
               let returnUp = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: false) {
                returnDown.post(tap: .cghidEventTap)
                try? await Task.sleep(for: .milliseconds(30))
                returnUp.post(tap: .cghidEventTap)
            }
            
            // Post an extra return in case the first one is ignored during animation
            try? await Task.sleep(for: .milliseconds(150))
            if let returnDown2 = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: true),
               let returnUp2 = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: false) {
                returnDown2.post(tap: .cghidEventTap)
                try? await Task.sleep(for: .milliseconds(30))
                returnUp2.post(tap: .cghidEventTap)
            }
        }
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
            
            guard let vector = await self.extractEmbedding(from: pixelBuffer) else { return }
            
            // ----------------------------------------------------
            // MODE 1: Enrollment Mode (Collect 20 diverse samples)
            // ----------------------------------------------------
            if self.isEnrollmentMode {
                self.enrollmentSamples.append(vector)
                // Need 20 frames for robust average
                let targetCount = 20.0
                self.enrollmentProgress = min(1.0, Double(self.enrollmentSamples.count) / targetCount)
                
                if self.enrollmentSamples.count < 7 {
                    self.statusMessage = "Look straight ahead... (\(Int(self.enrollmentProgress * 100))%)"
                } else if self.enrollmentSamples.count < 14 {
                    self.statusMessage = "Turn your head slightly left... (\(Int(self.enrollmentProgress * 100))%)"
                } else {
                    self.statusMessage = "Turn your head slightly right... (\(Int(self.enrollmentProgress * 100))%)"
                }
                
                // Introduce slight intentional delay to force capturing different frames over ~3 seconds
                try? await Task.sleep(for: .milliseconds(150))
                
                if self.enrollmentSamples.count >= Int(targetCount) {
                    // Average the embedding vectors for maximum biometric stability
                    var averaged = [Double](repeating: 0.0, count: vector.count)
                    for sample in self.enrollmentSamples {
                        for i in 0..<vector.count {
                            averaged[i] += sample[i] / targetCount
                        }
                    }
                    
                    // Re-normalize the averaged vector
                    var sumSquares = 0.0
                    for val in averaged { sumSquares += val * val }
                    let norm = sqrt(sumSquares)
                    let normalizedAverage = averaged.map { $0 / norm }
                    
                    let newFace = EnrolledFace(name: self.pendingFaceName, vector: normalizedAverage)
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
                    let dist = self.computeCosineDistance(vector, face.vector)
                    if dist < bestDistance {
                        bestDistance = dist
                        bestName = face.name
                    }
                }
                
                // Map Cosine distance (0.0 -> 100%, 0.5 -> 0%)
                let confidence = max(0, min(100, Int((1.0 - (bestDistance / 0.5)) * 100)))
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
            
            for face in self.enrolledFaces {
                let dist = self.computeCosineDistance(vector, face.vector)
                if dist < bestDistance {
                    bestDistance = dist
                }
            }
            
            // Strict match check: Distance must be strictly under threshold
            if bestDistance <= self.matchThreshold {
                self.consecutiveMatches += 1
                
                // Require 2 consecutive matching frames to prevent any momentary false positive
                if self.consecutiveMatches >= 2 {
                    self.recognitionTimer?.cancel()
                    self.stopCameraSession()
                    self.isScanning = false
                    self.performMacUnlock()
                }
            } else {
                self.consecutiveMatches = 0
            }
        }
    }
}
