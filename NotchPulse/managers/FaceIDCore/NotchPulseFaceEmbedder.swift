//
//  NotchPulseFaceEmbedder.swift
//  NotchPulse
//
//  Protocol-based face embedder system with two implementations:
//  - NotchPulseArcFaceEmbedder: ArcFace Deep Metric Model (primary, high-accuracy 512D embeddings)
//  - NotchPulseVisionFeaturePrintEmbedder: Apple Vision fallback
//

import Foundation
import CoreML
import CoreGraphics
import Vision
import CoreVideo

// MARK: - Protocol

/// `nonisolated` so implementations can run on a background task despite the project's default main-actor isolation.
protocol NotchPulseFaceEmbedder: Sendable {
    /// Name shown in the debug UI so it's obvious which embedder produced a given saved sample.
    nonisolated var name: String { get }
    /// Persisted alongside every sample; used to refuse comparing across different embedders.
    nonisolated var modelIdentifier: String { get }
    /// Declared output length, for cross-model mismatch detection without running an embedding first.
    nonisolated var embeddingDimension: Int { get }
    /// Whether this embedder needs a canonically-aligned input (ArcFace) vs. tolerating a loose crop (Vision feature-print).
    nonisolated var requiresAlignment: Bool { get }
    nonisolated func embedding(for face: CGImage) throws -> [Float]
}

// MARK: - Shared Utilities

enum FaceEmbedding {
    /// Scales `vector` to unit length; matters once vectors are combined (see `average` below).
    static func l2Normalized(_ vector: [Float]) -> [Float] {
        let norm = sqrt(vector.reduce(Float(0)) { $0 + $1 * $1 })
        guard norm > 0 else { return vector }
        return vector.map { $0 / norm }
    }

    /// Cosine similarity, range -1...1.
    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        guard normA > 0, normB > 0 else { return 0 }
        return dot / (normA.squareRoot() * normB.squareRoot())
    }

    /// For UI display: converts cosine similarity to intuitive percentage.
    static func similarityPercent(_ a: [Float], _ b: [Float]) -> Double {
        let similarity = cosineSimilarity(a, b)
        return Double((similarity + 1) / 2) * 100
    }

    /// Normalize each sample, average, then renormalize.
    static func average(_ vectors: [[Float]]) -> [Float]? {
        guard let first = vectors.first, !first.isEmpty else { return nil }
        let count = Float(vectors.count)
        var sum = [Float](repeating: 0, count: first.count)
        for vector in vectors where vector.count == first.count {
            let normalized = l2Normalized(vector)
            for i in 0..<normalized.count { sum[i] += normalized[i] }
        }
        let mean = sum.map { $0 / count }
        return l2Normalized(mean)
    }
}

// MARK: - Errors

enum NotchPulseFaceEmbedderError: LocalizedError {
    case modelNotFound
    case modelLoadFailed(String)
    case pixelBufferCreationFailed
    case unexpectedInputSize(got: (Int, Int), expected: Int)
    case unexpectedOutput(String)
    case noObservation
    case unsupportedElementType

    var errorDescription: String? {
        switch self {
        case .modelNotFound:
            return "ArcFace.mlpackage/mlmodelc not found in the app bundle."
        case .modelLoadFailed(let detail):
            return "Failed to load the ArcFace Core ML model: \(detail)"
        case .pixelBufferCreationFailed:
            return "Couldn't prepare the aligned face image for Core ML."
        case .unexpectedInputSize(let got, let expected):
            return "ArcFace expects a \(expected)×\(expected) aligned image, got \(got.0)×\(got.1)."
        case .unexpectedOutput(let detail):
            return "ArcFace model produced an unexpected output: \(detail)"
        case .noObservation:
            return "Vision did not produce a feature print for this image."
        case .unsupportedElementType:
            return "Feature print used an unexpected element type."
        }
    }
}

// MARK: - ArcFace Embedder (Primary — Clean Core ML Inference)

final class NotchPulseArcFaceEmbedder: NotchPulseFaceEmbedder, @unchecked Sendable {
    nonisolated let name = "ArcFace (w600k_mbf)"
    nonisolated let modelIdentifier = "arcface-w600k_mbf-v1"
    nonisolated let embeddingDimension = 512
    nonisolated let requiresAlignment = true

    private static let inputSize = NotchPulseFaceAligner.outputSize
    private static let inputName = "input_image"
    private static let outputName = "embedding"

    private let model: MLModel
    private let pixelBufferPool: CVPixelBufferPool

    private static let lock = NSLock()
    private static var _sharedInstance: NotchPulseArcFaceEmbedder?

    static func shared() throws -> NotchPulseArcFaceEmbedder {
        lock.lock()
        defer { lock.unlock() }
        if let existing = _sharedInstance {
            return existing
        }
        let instance = try NotchPulseArcFaceEmbedder()
        _sharedInstance = instance
        return instance
    }

    static func purgeCache() {
        lock.lock()
        defer { lock.unlock() }
        _sharedInstance = nil
    }

    init() throws {
        guard let modelURL = Self.locateModel() else {
            throw NotchPulseFaceEmbedderError.modelNotFound
        }

        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all

        do {
            model = try MLModel(contentsOf: modelURL, configuration: configuration)
        } catch {
            throw NotchPulseFaceEmbedderError.modelLoadFailed(error.localizedDescription)
        }

        guard let pool = Self.makePixelBufferPool(size: Self.inputSize) else {
            throw NotchPulseFaceEmbedderError.pixelBufferCreationFailed
        }
        pixelBufferPool = pool
    }

    private static func locateModel() -> URL? {
        for name in ["ArcFace", "w600k_mbf", "FaceEmbedding"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc") {
                return url
            }
            if let packageURL = Bundle.main.url(forResource: name, withExtension: "mlpackage") {
                if let compiled = try? MLModel.compileModel(at: packageURL) {
                    return compiled
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

    nonisolated func embedding(for face: CGImage) throws -> [Float] {
        guard face.width == Self.inputSize, face.height == Self.inputSize else {
            throw NotchPulseFaceEmbedderError.unexpectedInputSize(got: (face.width, face.height), expected: Self.inputSize)
        }

        var pixelBufferOut: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pixelBufferPool, &pixelBufferOut)
        guard status == kCVReturnSuccess, let pixelBuffer = pixelBufferOut else {
            throw NotchPulseFaceEmbedderError.pixelBufferCreationFailed
        }
        try Self.render(face, into: pixelBuffer)

        let input = try MLDictionaryFeatureProvider(dictionary: [Self.inputName: MLFeatureValue(pixelBuffer: pixelBuffer)])
        let output = try model.prediction(from: input)

        guard let multiArray = output.featureValue(for: Self.outputName)?.multiArrayValue ?? output.featureValue(for: "var_1054")?.multiArrayValue else {
            throw NotchPulseFaceEmbedderError.unexpectedOutput("no '\(Self.outputName)' output found")
        }
        guard multiArray.count == embeddingDimension else {
            throw NotchPulseFaceEmbedderError.unexpectedOutput("expected \(embeddingDimension) floats, got \(multiArray.count)")
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
            throw NotchPulseFaceEmbedderError.pixelBufferCreationFailed
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }

    private static func floatVector(from array: MLMultiArray) -> [Float] {
        var result = [Float](repeating: 0, count: array.count)
        for i in 0..<array.count {
            result[i] = array[i].floatValue
        }
        return result
    }
}

// MARK: - Vision Feature Print Embedder (Fallback)

struct NotchPulseVisionFeaturePrintEmbedder: NotchPulseFaceEmbedder {
    nonisolated let name = "Vision Feature Print"
    nonisolated let modelIdentifier = "vision-feature-print-v1"
    nonisolated let embeddingDimension = 2048
    nonisolated let requiresAlignment = false

    nonisolated func embedding(for face: CGImage) throws -> [Float] {
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: face, options: [:])
        try handler.perform([request])

        guard let observation = request.results?.first as? VNFeaturePrintObservation else {
            throw NotchPulseFaceEmbedderError.noObservation
        }
        return try Self.floatVector(from: observation)
    }

    nonisolated private static func floatVector(from observation: VNFeaturePrintObservation) throws -> [Float] {
        let count = observation.elementCount
        switch observation.elementType {
        case .float:
            var result = [Float](repeating: 0, count: count)
            observation.data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                let buffer = raw.bindMemory(to: Float.self)
                for i in 0..<count { result[i] = buffer[i] }
            }
            return result
        case .double:
            var result = [Float](repeating: 0, count: count)
            observation.data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                let buffer = raw.bindMemory(to: Double.self)
                for i in 0..<count { result[i] = Float(buffer[i]) }
            }
            return result
        default:
            throw NotchPulseFaceEmbedderError.unsupportedElementType
        }
    }
}
