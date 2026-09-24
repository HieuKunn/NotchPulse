//
//  ArcFaceEmbedder.swift
//  NotchPulse
//
//  Requires a canonically-aligned 112x112 input (see NotchPulseFaceAligner) — unlike VisionFeaturePrintEmbedder, accuracy depends on alignment.
//

import CoreML
import CoreGraphics
import CoreVideo

enum ArcFaceEmbedderError: LocalizedError {
    case modelNotFound
    case modelLoadFailed(String)
    case pixelBufferCreationFailed
    case unexpectedInputSize(got: (Int, Int), expected: Int)
    case unexpectedOutput(String)

    var errorDescription: String? {
        switch self {
        case .modelNotFound:
            return "ArcFace.mlpackage/mlmodelc not found in the app bundle. Run tools/convert_arcface.py, then add NotchPulse/Models/ArcFace.mlpackage to the Xcode project."
        case .modelLoadFailed(let detail):
            return "Failed to load the ArcFace Core ML model: \(detail)"
        case .pixelBufferCreationFailed:
            return "Couldn't prepare the aligned face image for Core ML."
        case .unexpectedInputSize(let got, let expected):
            return "ArcFaceEmbedder expects a \(expected)x\(expected) aligned image, got \(got.0)x\(got.1). Run the face through NotchPulseFaceAligner first."
        case .unexpectedOutput(let detail):
            return "ArcFace model produced an unexpected output: \(detail)"
        }
    }
}

final class ArcFaceEmbedder: FaceEmbedder, @unchecked Sendable {
    static let defaultModelIdentifier = "arcface-w600k_mbf-v1"

    static var isModelBundled: Bool {
        for name in ["ArcFace", "w600k_mbf"] {
            for ext in ["mlmodelc", "mlpackage"] {
                if Bundle.main.url(forResource: name, withExtension: ext) != nil { return true }
                if Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Models") != nil { return true }
                if Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "FaceIDCore") != nil { return true }
            }
        }
        return false
    }

    nonisolated let name = "ArcFace (w600k_mbf)"
    nonisolated let modelIdentifier = ArcFaceEmbedder.defaultModelIdentifier
    nonisolated let embeddingDimension = 512
    nonisolated let requiresAlignment = true

    private static let inputSize = NotchPulseFaceAligner.outputSize
    private static let inputName = "input_image"
    private static let outputName = "embedding"

    private static let instanceLock = NSLock()
    private static var _sharedInstance: ArcFaceEmbedder?
    private static var unloadWorkItem: DispatchWorkItem?

    /// Lazily loads ArcFace model on demand; call scheduleUnload() or unload() to release memory when unlock session is over.
    static var shared: ArcFaceEmbedder? {
        instanceLock.lock()
        defer { instanceLock.unlock() }
        unloadWorkItem?.cancel()
        unloadWorkItem = nil
        if let existing = _sharedInstance {
            return existing
        }
        do {
            let instance = try ArcFaceEmbedder()
            _sharedInstance = instance
            return instance
        } catch {
            NSLog("[ArcFaceEmbedder] Failed to initialize shared instance: \(error.localizedDescription)")
            return nil
        }
    }

    /// Asynchronously pre-warms the ArcFace ML model on a background task so it is ready before camera frames arrive.
    static func warmUp() {
        instanceLock.lock()
        unloadWorkItem?.cancel()
        unloadWorkItem = nil
        let isLoaded = (_sharedInstance != nil)
        instanceLock.unlock()

        if !isLoaded {
            Task.detached(priority: .userInitiated) {
                _ = shared
            }
        }
    }

    /// Releases the MLModel and CVPixelBufferPool from RAM after an idle delay (e.g. 30s of inactivity).
    /// Prevents repeated model loading/unloading overhead across rapid retries or testing.
    static func scheduleUnload(after delay: TimeInterval = 30.0) {
        instanceLock.lock()
        defer { instanceLock.unlock() }
        unloadWorkItem?.cancel()
        let item = DispatchWorkItem {
            instanceLock.lock()
            defer { instanceLock.unlock() }
            _sharedInstance = nil
            NSLog("[ArcFaceEmbedder] Model unloaded from RAM after idle period.")
        }
        unloadWorkItem = item
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay, execute: item)
    }

    /// Immediately releases the MLModel and CVPixelBufferPool from RAM
    static func unload() {
        instanceLock.lock()
        defer { instanceLock.unlock() }
        unloadWorkItem?.cancel()
        unloadWorkItem = nil
        _sharedInstance = nil
    }

    // Loaded once and reused — model load dominates a single inference.
    private let model: MLModel
    private let pixelBufferPool: CVPixelBufferPool

    /// Throws immediately if the model isn't bundled, so callers can fall back to `VisionFeaturePrintEmbedder`.
    init() throws {
        guard let modelURL = Self.locateModel() else {
            NSLog("[ArcFaceEmbedder] Model file not found in any bundle.")
            throw ArcFaceEmbedderError.modelNotFound
        }

        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all

        do {
            model = try MLModel(contentsOf: modelURL, configuration: configuration)
        } catch {
            NSLog("[ArcFaceEmbedder] CoreML model load failed at \(modelURL): \(error.localizedDescription)")
            throw ArcFaceEmbedderError.modelLoadFailed(error.localizedDescription)
        }

        guard let pool = Self.makePixelBufferPool(size: Self.inputSize) else {
            throw ArcFaceEmbedderError.pixelBufferCreationFailed
        }
        pixelBufferPool = pool
    }

    /// Both names are checked in case the file was added under a different name.
    /// Supports precompiled .mlmodelc, raw .mlpackage (compiled on demand), and bundle subdirectories.
    private static func locateModel() -> URL? {
        let bundles = [Bundle.main, Bundle(for: ArcFaceEmbedder.self)]
        for bundle in bundles {
            for name in ["ArcFace", "w600k_mbf"] {
                if let url = bundle.url(forResource: name, withExtension: "mlmodelc") {
                    return url
                }
                if let url = bundle.url(forResource: name, withExtension: "mlpackage") {
                    if let compiled = try? MLModel.compileModel(at: url) {
                        return compiled
                    }
                }
                if let url = bundle.url(forResource: name, withExtension: "mlmodelc", subdirectory: "Models") {
                    return url
                }
                if let url = bundle.url(forResource: name, withExtension: "mlpackage", subdirectory: "Models") {
                    if let compiled = try? MLModel.compileModel(at: url) {
                        return compiled
                    }
                }
                if let url = bundle.url(forResource: name, withExtension: "mlmodelc", subdirectory: "FaceIDCore") {
                    return url
                }
                if let url = bundle.url(forResource: name, withExtension: "mlpackage", subdirectory: "FaceIDCore") {
                    if let compiled = try? MLModel.compileModel(at: url) {
                        return compiled
                    }
                }
            }
        }
        return nil
    }

    private static func makePixelBufferPool(size: Int) -> CVPixelBufferPool? {
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: size,
            kCVPixelBufferHeightKey as String: size,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
        ]
        var pool: CVPixelBufferPool?
        CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attributes as CFDictionary, &pool)
        return pool
    }

    /// `MLModel.prediction(from:)` is synchronous/blocking — callers run embedders off the main actor.
    nonisolated func embedding(for face: CGImage) throws -> [Float] {
        guard face.width == Self.inputSize, face.height == Self.inputSize else {
            throw ArcFaceEmbedderError.unexpectedInputSize(got: (face.width, face.height), expected: Self.inputSize)
        }

        var pixelBufferOut: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pixelBufferPool, &pixelBufferOut)
        guard status == kCVReturnSuccess, let pixelBuffer = pixelBufferOut else {
            throw ArcFaceEmbedderError.pixelBufferCreationFailed
        }
        try Self.render(face, into: pixelBuffer)

        let input = try MLDictionaryFeatureProvider(dictionary: [Self.inputName: MLFeatureValue(pixelBuffer: pixelBuffer)])
        let output = try model.prediction(from: input)

        guard let multiArray = output.featureValue(for: Self.outputName)?.multiArrayValue else {
            throw ArcFaceEmbedderError.unexpectedOutput("no '\(Self.outputName)' output found")
        }
        guard multiArray.count == embeddingDimension else {
            throw ArcFaceEmbedderError.unexpectedOutput("expected \(embeddingDimension) floats, got \(multiArray.count)")
        }

        let raw = Self.floatVector(from: multiArray)
        return FaceEmbedding.l2Normalized(raw)
    }

    private static func render(_ image: CGImage, into pixelBuffer: CVPixelBuffer) throws {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            throw ArcFaceEmbedderError.pixelBufferCreationFailed
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }

    /// `MLMultiArray` storage isn't guaranteed to be a flat, stride-1 buffer, so this indexes via the array's own subscript.
    private static func floatVector(from array: MLMultiArray) -> [Float] {
        var result = [Float](repeating: 0, count: array.count)
        for i in 0..<array.count {
            result[i] = array[i].floatValue
        }
        return result
    }
}
