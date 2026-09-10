//
//  NotchPulseFaceEmbedder.swift
//  NotchPulse
//
//  Protocol-based face embedder system with two implementations:
//  - NotchPulseArcFaceEmbedder: ArcFace with TTA + CLAHE + Gamma correction (primary, highest accuracy)
//  - NotchPulseVisionFeaturePrintEmbedder: Apple Vision fallback (lower accuracy, no alignment needed)
//
//  The protocol pattern is ported from Glance; the TTA/CLAHE/Gamma preprocessing is NotchPulse's
//  original contribution that Glance does not have.
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
    /// Persisted alongside every sample; used to refuse comparing across different embedders
    /// (which wouldn't error, just produce confident nonsense).
    nonisolated var modelIdentifier: String { get }
    /// Declared output length, for cross-model mismatch detection without running an embedding first.
    nonisolated var embeddingDimension: Int { get }
    /// Whether this embedder needs a canonically-aligned input (ArcFace) vs. tolerating a loose crop (Vision feature-print).
    nonisolated var requiresAlignment: Bool { get }
    nonisolated func embedding(for face: CGImage) throws -> [Float]
}

// MARK: - Shared Utilities

nonisolated enum FaceEmbedding {
    /// Scales `vector` to unit length; matters once vectors are combined (see `average` below).
    static func l2Normalized(_ vector: [Float]) -> [Float] {
        let norm = sqrt(vector.reduce(Float(0)) { $0 + $1 * $1 })
        guard norm > 0 else { return vector }
        return vector.map { $0 / norm }
    }

    /// Cosine similarity, range -1...1. The raw value ArcFace thresholds are quoted in (typical cutoffs ~0.28-0.40).
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

    /// For the legacy Vision-feature-print UI only. Don't use to tune ArcFace thresholds — use `cosineSimilarity` directly.
    static func similarityPercent(_ a: [Float], _ b: [Float]) -> Double {
        let similarity = cosineSimilarity(a, b)
        return Double((similarity + 1) / 2) * 100
    }

    /// Normalize each sample, average, then renormalize — a plain element-wise mean would let a larger-magnitude
    /// sample silently dominate.
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
    case preprocessingFailed
    case predictionFailed
    case modelLoadFailed(underlying: Error)
    case pixelBufferCreationFailed
    case unexpectedInputSize(got: (Int, Int), expected: Int)
    case unexpectedOutput(String)
    case noObservation
    case unsupportedElementType

    var errorDescription: String? {
        switch self {
        case .modelNotFound:
            return "ArcFace.mlpackage/mlmodelc not found in the app bundle."
        case .preprocessingFailed:
            return "Couldn't preprocess the face image for the model."
        case .predictionFailed:
            return "Face embedding prediction failed."
        case .modelLoadFailed(let error):
            return "Couldn't load FaceEmbedding model: \(error.localizedDescription)"
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

// MARK: - ArcFace Embedder (Primary — with TTA + CLAHE + Gamma)

/// NotchPulse's enhanced ArcFace embedder — keeps all the preprocessing that makes it
/// significantly more accurate than Glance's raw-pixel approach:
/// - Global gamma correction (target mean luminance = 127)
/// - CLAHE 8×8 tiles (local contrast equalization)
/// - Test-Time Augmentation (original + horizontal flip → average)
nonisolated final class NotchPulseArcFaceEmbedder: NotchPulseFaceEmbedder, @unchecked Sendable {
    nonisolated let name = "ArcFace (w600k_mbf) + TTA"
    nonisolated let modelIdentifier = "arcface-notchpulse-tta-v1"
    nonisolated let embeddingDimension = 512
    nonisolated let requiresAlignment = true

    private static let inputSize = NotchPulseFaceAligner.outputSize
    private let model: MLModel
    private let inputName: String
    private let outputName: String
    let modelName: String

    init() throws {
        let candidates = ["ArcFace", "FaceEmbedding", "FaceNet"]
        var loaded: (MLModel, String)? = nil
        let config = MLModelConfiguration()
        config.computeUnits = .all

        for name in candidates {
            guard let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc") else {
                continue
            }
            do {
                let m = try MLModel(contentsOf: url, configuration: config)
                loaded = (m, name)
                break
            } catch {
                continue
            }
        }

        guard let (model, name) = loaded else {
            throw NotchPulseFaceEmbedderError.modelNotFound
        }

        self.model = model
        self.modelName = name

        let description = model.modelDescription
        guard let firstInput = description.inputDescriptionsByName.keys.first else {
            throw NotchPulseFaceEmbedderError.predictionFailed
        }
        self.inputName = firstInput

        let outputs = description.outputDescriptionsByName
        if outputs["embedding"] != nil {
            self.outputName = "embedding"
        } else if let firstOutput = outputs.keys.first {
            self.outputName = firstOutput
        } else {
            throw NotchPulseFaceEmbedderError.predictionFailed
        }
    }

    nonisolated func embedding(for face: CGImage) throws -> [Float] {
        // Step 1: render the aligned face to a 112×112 RGBA byte buffer, then apply
        // CLAHE to normalize lighting. Both TTA passes below share this buffer.
        let normalizedPixels = try renderAndNormalizePixels(from: face)

        // Step 2: Test-Time Augmentation — original + horizontal mirror.
        let embOriginal = try predictEmbedding(from: normalizedPixels, flipped: false)
        let embFlipped  = try predictEmbedding(from: normalizedPixels, flipped: true)

        guard embOriginal.count == embFlipped.count else {
            return embOriginal
        }
        var mean = [Float](repeating: 0, count: embOriginal.count)
        for i in 0..<embOriginal.count {
            mean[i] = (embOriginal[i] + embFlipped[i]) * 0.5
        }
        return FaceEmbedding.l2Normalized(mean)
    }

    private func renderAndNormalizePixels(from cgImage: CGImage) throws -> [UInt8] {
        let size = Self.inputSize
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
            throw NotchPulseFaceEmbedderError.preprocessingFailed
        }
        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))

        Self.normalizeGlobalExposure(pixels: &pixels, size: size)
        Self.applyCLAHE(pixels: &pixels, size: size)
        return pixels
    }

    // MARK: - Global exposure normalization

    private static func normalizeGlobalExposure(pixels: inout [UInt8], size: Int) {
        var totalLuma: Int = 0
        let pixelCount = size * size
        for p in 0..<pixelCount {
            let base = p * 4
            totalLuma += (299 * Int(pixels[base])
                        + 587 * Int(pixels[base + 1])
                        + 114 * Int(pixels[base + 2])
                        + 500) / 1000
        }
        let mean = Float(totalLuma) / Float(pixelCount)
        let target: Float = 127.0

        guard mean > 5, abs(mean - target) > 8 else { return }

        let gamma = log(target / 255.0) / log(mean / 255.0)

        var lut = [UInt8](repeating: 0, count: 256)
        for i in 0..<256 {
            let corrected = powf(Float(i) / 255.0, gamma) * 255.0
            lut[i] = UInt8(min(255, max(0, Int(corrected + 0.5))))
        }

        for p in 0..<pixelCount {
            let base = p * 4
            pixels[base]     = lut[Int(pixels[base])]
            pixels[base + 1] = lut[Int(pixels[base + 1])]
            pixels[base + 2] = lut[Int(pixels[base + 2])]
        }
    }

    private func predictEmbedding(from pixels: [UInt8], flipped: Bool) throws -> [Float] {
        let input = try makeInputArray(from: pixels, flipped: flipped)
        let provider = try MLDictionaryFeatureProvider(dictionary: [
            inputName: MLFeatureValue(multiArray: input)
        ])
        let output: MLFeatureProvider
        do {
            output = try model.prediction(from: provider)
        } catch {
            throw NotchPulseFaceEmbedderError.predictionFailed
        }
        guard let multiArray = output.featureValue(for: outputName)?.multiArrayValue else {
            throw NotchPulseFaceEmbedderError.predictionFailed
        }
        let raw = Self.float32Array(from: multiArray)
        return FaceEmbedding.l2Normalized(raw)
    }

    private func makeInputArray(from pixels: [UInt8], flipped: Bool) throws -> MLMultiArray {
        let size = Self.inputSize
        let array: MLMultiArray
        do {
            array = try MLMultiArray(
                shape: [1, 3, NSNumber(value: size), NSNumber(value: size)],
                dataType: .float32
            )
        } catch {
            throw NotchPulseFaceEmbedderError.preprocessingFailed
        }
        let ptr = array.dataPointer.assumingMemoryBound(to: Float32.self)
        let plane = size * size
        for y in 0..<size {
            for x in 0..<size {
                let srcX = flipped ? (size - 1 - x) : x
                let i = (y * size + srcX) * 4
                let r = (Float(pixels[i])     - 127.5) / 127.5
                let g = (Float(pixels[i + 1]) - 127.5) / 127.5
                let b = (Float(pixels[i + 2]) - 127.5) / 127.5
                let pixelIdx = y * size + x
                ptr[0 * plane + pixelIdx] = r
                ptr[1 * plane + pixelIdx] = g
                ptr[2 * plane + pixelIdx] = b
            }
        }
        return array
    }

    // MARK: - CLAHE

    private static func applyCLAHE(pixels: inout [UInt8], size: Int) {
        let numTiles = 8
        let tileSize = size / numTiles
        let pixelsPerTile = tileSize * tileSize
        let clipLimit = max(2, (4 * pixelsPerTile) / 256)

        var luma = [UInt8](repeating: 0, count: size * size)
        for p in 0..<(size * size) {
            let base = p * 4
            let y = (299 * Int(pixels[base])
                   + 587 * Int(pixels[base + 1])
                   + 114 * Int(pixels[base + 2])
                   + 500) / 1000
            luma[p] = UInt8(min(255, max(0, y)))
        }

        var luts = [UInt8](repeating: 0, count: numTiles * numTiles * 256)
        for ty in 0..<numTiles {
            for tx in 0..<numTiles {
                var hist = [Int](repeating: 0, count: 256)
                let y0 = ty * tileSize
                let x0 = tx * tileSize
                for yy in y0..<(y0 + tileSize) {
                    let rowBase = yy * size
                    for xx in x0..<(x0 + tileSize) {
                        hist[Int(luma[rowBase + xx])] += 1
                    }
                }
                var excess = 0
                for i in 0..<256 {
                    if hist[i] > clipLimit {
                        excess += hist[i] - clipLimit
                        hist[i] = clipLimit
                    }
                }
                let addPerBin = excess / 256
                let leftover = excess % 256
                for i in 0..<256 {
                    hist[i] += addPerBin + (i < leftover ? 1 : 0)
                }
                let lutBase = (ty * numTiles + tx) * 256
                var cum = 0
                for i in 0..<256 {
                    cum += hist[i]
                    luts[lutBase + i] = UInt8(min(255, (cum * 255) / pixelsPerTile))
                }
            }
        }

        let tsF = Float(tileSize)
        let halfTile = tsF * 0.5
        let lastTile = numTiles - 1
        for y in 0..<size {
            let tyF = (Float(y) - halfTile) / tsF
            var ty0 = Int(floor(tyF))
            let dy = tyF - Float(ty0)
            var ty1 = ty0 + 1
            if ty0 < 0 { ty0 = 0 } else if ty0 > lastTile { ty0 = lastTile }
            if ty1 < 0 { ty1 = 0 } else if ty1 > lastTile { ty1 = lastTile }

            let rowBase = y * size
            for x in 0..<size {
                let txF = (Float(x) - halfTile) / tsF
                var tx0 = Int(floor(txF))
                let dx = txF - Float(tx0)
                var tx1 = tx0 + 1
                if tx0 < 0 { tx0 = 0 } else if tx0 > lastTile { tx0 = lastTile }
                if tx1 < 0 { tx1 = 0 } else if tx1 > lastTile { tx1 = lastTile }

                let yValue = Int(luma[rowBase + x])
                let v00 = Float(luts[(ty0 * numTiles + tx0) * 256 + yValue])
                let v01 = Float(luts[(ty0 * numTiles + tx1) * 256 + yValue])
                let v10 = Float(luts[(ty1 * numTiles + tx0) * 256 + yValue])
                let v11 = Float(luts[(ty1 * numTiles + tx1) * 256 + yValue])
                let a = v00 * (1 - dx) + v01 * dx
                let b = v10 * (1 - dx) + v11 * dx
                let newY = a * (1 - dy) + b * dy

                let oldY = Float(yValue)
                let gain: Float = oldY > 1 ? newY / oldY : 1
                let pi = (rowBase + x) * 4
                let r  = min(255, max(0, Float(pixels[pi])     * gain))
                let g  = min(255, max(0, Float(pixels[pi + 1]) * gain))
                let bc = min(255, max(0, Float(pixels[pi + 2]) * gain))
                pixels[pi]     = UInt8(r + 0.5)
                pixels[pi + 1] = UInt8(g + 0.5)
                pixels[pi + 2] = UInt8(bc + 0.5)
            }
        }
    }

    private static func float32Array(from array: MLMultiArray) -> [Float] {
        let count = array.count
        let ptr = array.dataPointer.assumingMemoryBound(to: Float32.self)
        return Array(UnsafeBufferPointer(start: ptr, count: count))
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
