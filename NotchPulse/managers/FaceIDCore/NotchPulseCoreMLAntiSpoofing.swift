//
//  NotchPulseCoreMLAntiSpoofing.swift
//  NotchPulse
//
//  AI-based Presentation Attack Detection (Liveness) using a CoreML model.
//

import Foundation
import CoreML
import CoreGraphics

enum NotchPulseCoreMLAntiSpoofingError: LocalizedError {
    case modelNotFound
    case preprocessingFailed
    case predictionFailed

    var errorDescription: String? {
        switch self {
        case .modelNotFound:
            return "Anti-spoofing model (Liveness.mlpackage/mlmodelc) not found."
        case .preprocessingFailed:
            return "Couldn't preprocess the face image for the anti-spoofing model."
        case .predictionFailed:
            return "Anti-spoofing prediction failed."
        }
    }
}

final class NotchPulseCoreMLAntiSpoofing: @unchecked Sendable {
    private let model: MLModel
    private let inputSize = 80 // Typical size for MiniFASNet
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
        let candidates = ["Liveness", "MiniFASNet"]
        var loaded: MLModel? = nil
        let config = MLModelConfiguration()
        // Use ANE/GPU to prevent CPU spikes during Liveness check
        config.computeUnits = .cpuAndNeuralEngine
        
        for name in candidates {
            var modelURL = Bundle.main.url(forResource: name, withExtension: "mlmodelc")
            if modelURL == nil, let packageURL = Bundle.main.url(forResource: name, withExtension: "mlpackage") {
                modelURL = try? MLModel.compileModel(at: packageURL)
            }
            guard let url = modelURL else {
                continue
            }
            do {
                loaded = try MLModel(contentsOf: url, configuration: config)
                break
            } catch {
                continue
            }
        }

        guard let model = loaded else {
            throw NotchPulseCoreMLAntiSpoofingError.modelNotFound
        }
        
        self.model = model
    }

    /// Evaluates if a given face crop is a real person (live) or a spoof (photo/video).
    /// - Returns: True if live, False if spoof.
    nonisolated func isLive(face: CGImage) throws -> Bool {
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
        
        // Example logic assuming output is [class0_prob, class1_prob, class2_prob]
        let count = outputArray.count
        guard count >= 1 else {
            throw NotchPulseCoreMLAntiSpoofingError.predictionFailed
        }
        
        let ptr = outputArray.dataPointer.assumingMemoryBound(to: Float32.self)
        let logits = Array(UnsafeBufferPointer(start: ptr, count: count))
        
        // Find argmax
        var maxIndex = 0
        var maxValue = logits[0]
        for i in 1..<count {
            if logits[i] > maxValue {
                maxValue = logits[i]
                maxIndex = i
            }
        }
        
        // Return true if maxIndex represents Live (assuming class 2 or 1 for this mock)
        return maxIndex == 2 || maxIndex == 1
    }
    
    private func makeInputArray(from cgImage: CGImage) throws -> MLMultiArray {
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
                // Normalize to [0, 1]
                let r = Float(pixels[i]) / 255.0
                let g = Float(pixels[i + 1]) / 255.0
                let b = Float(pixels[i + 2]) / 255.0
                
                let pixelIdx = y * size + x
                ptr[0 * plane + pixelIdx] = r
                ptr[1 * plane + pixelIdx] = g
                ptr[2 * plane + pixelIdx] = b
            }
        }
        
        return array
    }
}
