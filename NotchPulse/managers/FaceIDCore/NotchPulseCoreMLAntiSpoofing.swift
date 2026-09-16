//
//  NotchPulseCoreMLAntiSpoofing.swift
//  NotchPulse
//
//  AI-based Presentation Attack Detection (Liveness) using an ensemble of
//  two real MiniFASNet CoreML models (MiniFASNetV2 + MiniFASNetV1SE) from
//  Minivision Silent-Face-Anti-Spoofing.
//
//  IMPORTANT: Face crops MUST be generated with a 2.7x bounding box scale
//  for MiniFASNetV2 and 4.0x for MiniFASNetV1SE to match training conditions.
//

import Foundation
import CoreML
import CoreGraphics

enum NotchPulseCoreMLAntiSpoofingError: LocalizedError {
    case modelNotFound(String)
    case preprocessingFailed
    case predictionFailed

    var errorDescription: String? {
        switch self {
        case .modelNotFound(let name):
            return "Anti-spoofing model '\(name)' not found in bundle."
        case .preprocessingFailed:
            return "Couldn't preprocess the face image for anti-spoofing."
        case .predictionFailed:
            return "Anti-spoofing prediction failed."
        }
    }
}

/// Ensemble anti-spoofing: runs MiniFASNetV2 and MiniFASNetV1SE in parallel,
/// requires BOTH to agree the face is live. Thread-safe, lazy-loaded singleton.
final class NotchPulseCoreMLAntiSpoofing: @unchecked Sendable {
    private let modelV2: MLModel
    private let modelV1SE: MLModel
    private let inputSize = 80
    
    private static let lock = NSLock()
    private static var _sharedInstance: NotchPulseCoreMLAntiSpoofing?

    static func shared() throws -> NotchPulseCoreMLAntiSpoofing {
        lock.lock()
        defer { lock.unlock() }
        if let existing = _sharedInstance {
            return existing
        }
        let instance = try NotchPulseCoreMLAntiSpoofing()
        _sharedInstance = instance
        return instance
    }
    
    init() throws {
        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndNeuralEngine

        // Load MiniFASNetV2
        guard let v2 = Self.loadModel(named: "MiniFASNetV2", config: config) else {
            throw NotchPulseCoreMLAntiSpoofingError.modelNotFound("MiniFASNetV2")
        }
        self.modelV2 = v2
        
        // Load MiniFASNetV1SE
        guard let v1se = Self.loadModel(named: "MiniFASNetV1SE", config: config) else {
            throw NotchPulseCoreMLAntiSpoofingError.modelNotFound("MiniFASNetV1SE")
        }
        self.modelV1SE = v1se
    }
    
    private static func loadModel(named name: String, config: MLModelConfiguration) -> MLModel? {
        // Try compiled model first
        if let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc") {
            return try? MLModel(contentsOf: url, configuration: config)
        }
        // Try mlpackage (will compile on first load)
        if let packageURL = Bundle.main.url(forResource: name, withExtension: "mlpackage"),
           let compiledURL = try? MLModel.compileModel(at: packageURL) {
            return try? MLModel(contentsOf: compiledURL, configuration: config)
        }
        return nil
    }

    // MARK: - Ensemble Liveness Check

    /// Evaluates if a given face crop is a real person (live) or a spoof.
    /// Uses ensemble voting: BOTH models must agree the face is live.
    ///
    /// - Parameters:
    ///   - faceImage: The full camera frame or a wide crop containing the face.
    ///   - faceBoundingBox: The detected face bounding box in pixel coordinates.
    /// - Returns: `true` if the ensemble agrees the face is live.
    nonisolated func isLive(faceImage: CGImage, faceBoundingBox: CGRect) throws -> Bool {
        // Create crops with different scales matching each model's training
        let crop2_7 = Self.cropFace(from: faceImage, bbox: faceBoundingBox, scale: 2.7)
        let crop4_0 = Self.cropFace(from: faceImage, bbox: faceBoundingBox, scale: 4.0)
        
        let v2Live = try predict(model: modelV2, face: crop2_7 ?? faceImage)
        let v1seLive = try predict(model: modelV1SE, face: crop4_0 ?? faceImage)
        
        // Ensemble: BOTH must agree it's live
        return v2Live && v1seLive
    }
    
    /// Simplified version for when only a pre-cropped face image is available.
    nonisolated func isLive(face: CGImage) throws -> Bool {
        let v2Live = try predict(model: modelV2, face: face)
        let v1seLive = try predict(model: modelV1SE, face: face)
        return v2Live && v1seLive
    }
    
    // MARK: - Prediction
    
    private nonisolated func predict(model: MLModel, face: CGImage) throws -> Bool {
        let input = try makeInputArray(from: face)
        let provider = try MLDictionaryFeatureProvider(dictionary: [
            "input": MLFeatureValue(multiArray: input)
        ])
        
        let output: MLFeatureProvider
        do {
            output = try model.prediction(from: provider)
        } catch {
            throw NotchPulseCoreMLAntiSpoofingError.predictionFailed
        }
        
        guard let outputArray = output.featureValue(for: "output")?.multiArrayValue else {
            throw NotchPulseCoreMLAntiSpoofingError.predictionFailed
        }
        
        let count = outputArray.count
        guard count >= 2 else {
            throw NotchPulseCoreMLAntiSpoofingError.predictionFailed
        }
        
        let ptr = outputArray.dataPointer.assumingMemoryBound(to: Float32.self)
        let logits = Array(UnsafeBufferPointer(start: ptr, count: count))
        
        // MiniFASNet output: 3 classes
        // Class 0: Real/Live (real face)
        // Class 1: Spoof type 1 (print attack)
        // Class 2: Spoof type 2 (replay attack)
        //
        // The model outputs raw logits, softmax to get probabilities
        let maxLogit = logits.max() ?? 0
        let expLogits = logits.map { exp($0 - maxLogit) }
        let sumExp = expLogits.reduce(0, +)
        let probs = expLogits.map { $0 / sumExp }
        
        // Live probability is class index 1 (real face in MiniFASNet convention)
        // In the Silent-Face-Anti-Spoofing codebase:
        //   label == 1 means REAL
        //   label == 0 or label == 2 means SPOOF
        let liveProb = probs.count > 1 ? probs[1] : 0
        
        // Threshold: 0.5 is standard, but we use 0.8 for extra strictness
        return liveProb > 0.8
    }
    
    // MARK: - Face Cropping with Scale
    
    /// Crops a face region from the full image with a specified scale factor.
    /// Scale 2.7 means the crop is 2.7x the bounding box size.
    private static nonisolated func cropFace(from image: CGImage, bbox: CGRect, scale: CGFloat) -> CGImage? {
        let w = bbox.width
        let h = bbox.height
        let centerX = bbox.midX
        let centerY = bbox.midY
        
        let newW = w * scale
        let newH = h * scale
        
        var cropRect = CGRect(
            x: centerX - newW / 2,
            y: centerY - newH / 2,
            width: newW,
            height: newH
        )
        
        // Clamp to image bounds
        cropRect = cropRect.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard !cropRect.isEmpty else { return nil }
        
        return image.cropping(to: cropRect)
    }
    
    // MARK: - Preprocessing
    
    private nonisolated func makeInputArray(from cgImage: CGImage) throws -> MLMultiArray {
        let size = inputSize
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        guard let context = CGContext(
            data: &pixels,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw NotchPulseCoreMLAntiSpoofingError.preprocessingFailed
        }
        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))
        
        let array = try MLMultiArray(
            shape: [1, 3, NSNumber(value: size), NSNumber(value: size)],
            dataType: .float32
        )
        
        let ptr = array.dataPointer.assumingMemoryBound(to: Float32.self)
        let plane = size * size
        
        for y in 0..<size {
            for x in 0..<size {
                let i = (y * size + x) * 4
                // BGR normalization matching training (ImageNet-style)
                let b = (Float(pixels[i + 2]) - 127.5) / 128.0
                let g = (Float(pixels[i + 1]) - 127.5) / 128.0
                let r = (Float(pixels[i])     - 127.5) / 128.0
                
                let pixelIdx = y * size + x
                ptr[0 * plane + pixelIdx] = b  // Channel 0: Blue
                ptr[1 * plane + pixelIdx] = g  // Channel 1: Green
                ptr[2 * plane + pixelIdx] = r  // Channel 2: Red
            }
        }
        
        return array
    }
}
