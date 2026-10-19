import Foundation
import CoreGraphics
import Observation

struct FaceRecognitionResult {
    let embedding: [Float]
    /// What was actually fed to the embedder, for debug UIs to inspect.
    let alignedImage: CGImage
    let alignmentTier: AlignmentTier
    let quality: Float?
    let face: DetectedFace
}

enum NotchPulseFaceRecognitionPipelineError: LocalizedError {
    case noFaceDetected
    case alignmentFailed

    var errorDescription: String? {
        switch self {
        case .noFaceDetected: return "No face detected in frame."
        case .alignmentFailed: return "Could not align the detected face."
        }
    }
}

typealias NotchPulseNotchPulseFaceRecognitionPipelineError = NotchPulseFaceRecognitionPipelineError

/// `@Observable` so the debug UI can surface which embedder is active.
@Observable
@MainActor
final class NotchPulseFaceRecognitionPipeline {
    nonisolated var embedder: FaceEmbedder {
        if let arcFace = ArcFaceEmbedder.shared {
            return arcFace
        }
        return VisionFeaturePrintEmbedder()
    }

    /// Set when ArcFace failed to load and the weaker Vision feature-print embedder is in use instead.
    var usingFallbackEmbedder: Bool {
        ArcFaceEmbedder.shared == nil
    }
    var fallbackReason: String? {
        usingFallbackEmbedder ? "ArcFace model not available" : nil
    }

    nonisolated static var activeModelIdentifier: String {
        ArcFaceEmbedder.shared?.modelIdentifier ?? "vision-feature-print-v1"
    }

    init() {}

    /// `nonisolated` so callers can run detect/align/embed from a background task instead of blocking the main actor.
    /// - Parameters:
    ///   - frame: The camera frame to analyze.
    ///   - previousBoundingBox: previous frame's selected box, if any — lets continuous tracking stay locked to the user.
    nonisolated func recognize(
        in frame: CGImage,
        preferNear previousBoundingBox: CGRect? = nil
    ) throws -> FaceRecognitionResult {
        let faces = try NotchPulseFaceDetector.detectFaces(in: frame)
        guard let face = Self.selectDominantFace(in: faces, preferNear: previousBoundingBox) else {
            throw NotchPulseFaceRecognitionPipelineError.noFaceDetected
        }
        return try recognize(face, in: frame)
    }

    /// Aligns and embeds an already-chosen face; enrollment uses this to bypass the prominence filter so a too-small face reads as "move closer" rather than "nobody there".
    nonisolated func recognize(_ face: DetectedFace, in frame: CGImage) throws -> FaceRecognitionResult {
        let inputImage: CGImage
        let tier: AlignmentTier
        if embedder.requiresAlignment {
            guard let aligned = NotchPulseFaceAligner.align(face, from: frame) else {
                throw NotchPulseFaceRecognitionPipelineError.alignmentFailed
            }
            inputImage = aligned.image
            tier = aligned.tier
        } else {
            guard let cropped = NotchPulseFaceDetector.crop(face, from: frame) else {
                throw NotchPulseFaceRecognitionPipelineError.alignmentFailed
            }
            inputImage = cropped
            tier = .paddedCrop
        }

        let embedding = try embedder.embedding(for: inputImage)
        return FaceRecognitionResult(embedding: embedding, alignedImage: inputImage, alignmentTier: tier, quality: face.quality, face: face)
    }

    /// Largest face by area with no prominence cutoff — unlike `selectDominantFace`, so enrollment can tell "too far" apart from "no face".
    nonisolated static func largestFace(in faces: [DetectedFace]) -> DetectedFace? {
        faces.max { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }
    }

    /// Below this fraction of frame width, a face is treated as a bystander, not a candidate — shared with onboarding's "move closer" prompt. `nonisolated(unsafe)` because it's read from a background-task static func that can't touch NotchPulseFaceIDSettings' MainActor-isolated storage.
    nonisolated(unsafe) static var minimumProminentFaceWidth: Float = 0.18

    /// Max normalized-coordinate drift between frames still counted as "the same person".
    nonisolated private static let continuityDistanceTolerance: CGFloat = 0.3

    /// Returns candidate faces ordered by likelihood of being the primary user:
    /// filters out bystander faces below `minimumProminentFaceWidth`, then sorts by proximity to `previousBoundingBox`
    /// (if tracking) or by bounding box area (largest first).
    nonisolated static func prominentFaces(in faces: [DetectedFace], preferNear previousBoundingBox: CGRect? = nil) -> [DetectedFace] {
        var candidates = faces.filter { $0.normalizedBoundingBox.width >= CGFloat(minimumProminentFaceWidth) }
        if candidates.isEmpty {
            candidates = faces
        }
        guard !candidates.isEmpty else { return [] }

        if let previous = previousBoundingBox {
            let previousCenter = CGPoint(x: previous.midX, y: previous.midY)
            return candidates.sorted { a, b in
                let distA = distance(from: a, to: previousCenter)
                let distB = distance(from: b, to: previousCenter)
                let aClose = distA < continuityDistanceTolerance
                let bClose = distB < continuityDistanceTolerance
                if aClose != bClose {
                    return aClose && !bClose
                }
                if aClose && bClose {
                    return distA < distB
                }
                return (a.boundingBox.width * a.boundingBox.height) > (b.boundingBox.width * b.boundingBox.height)
            }
        }

        return candidates.sorted {
            ($0.boundingBox.width * $0.boundingBox.height) > ($1.boundingBox.width * $1.boundingBox.height)
        }
    }

    /// Picks the person actually at the camera, not a bystander: filters out faces below `minimumProminentFaceWidth`, then prefers continuity with `previousBoundingBox` over raw largest-by-area so two similarly-sized faces can't flip-flop the selection frame to frame and starve the liveness/wrong-face streaks of agreement.
    nonisolated static func selectDominantFace(in faces: [DetectedFace], preferNear previousBoundingBox: CGRect? = nil) -> DetectedFace? {
        prominentFaces(in: faces, preferNear: previousBoundingBox).first
    }

    nonisolated private static func distance(from face: DetectedFace, to point: CGPoint) -> CGFloat {
        let center = CGPoint(x: face.normalizedBoundingBox.midX, y: face.normalizedBoundingBox.midY)
        return hypot(center.x - point.x, center.y - point.y)
    }
}

struct ScoredIdentity {
    let identity: FaceIdentity
    /// Similarity against the identity's averaged template.
    let centroidSimilarity: Float
    /// Similarity against the single closest individual sample — catches
    /// cases where averaging blurred together poses that shouldn't be
    /// blended.
    let maxSampleSimilarity: Float
}

extension NotchPulseFaceRecognitionPipeline {
    /// Sorted by best overall similarity (max of centroid or closest sample) descending; includes stale identities (different embedder) since `bestMatch` is what excludes them from actually matching.
    nonisolated func score(_ embedding: [Float], against identities: [FaceIdentity]) -> [ScoredIdentity] {
        identities.compactMap { identity in
            guard let template = identity.template, !identity.samples.isEmpty else { return nil }
            let centroidSim = FaceEmbedding.cosineSimilarity(embedding, template)
            let maxSim = identity.samples
                .map { FaceEmbedding.cosineSimilarity(embedding, $0.embedding) }
                .max() ?? centroidSim
            return ScoredIdentity(identity: identity, centroidSimilarity: centroidSim, maxSampleSimilarity: maxSim)
        }.sorted {
            max($0.centroidSimilarity, $0.maxSampleSimilarity) > max($1.centroidSimilarity, $1.maxSampleSimilarity)
        }
    }

    /// Shared by Face Lab and NotchPulseFaceUnlockCoordinator so tuning stays consistent. Allows matching when either the averaged centroid meets threshold, or an individual enrolled pose sample matches strongly.
    nonisolated func bestMatch(in scored: [ScoredIdentity], threshold: Float) -> ScoredIdentity? {
        guard let first = scored.first, !first.identity.isStale(comparedTo: embedder) else { return nil }
        let matched = (first.centroidSimilarity >= threshold) || (first.maxSampleSimilarity >= threshold)
        guard matched else { return nil }
        return first
    }
}
