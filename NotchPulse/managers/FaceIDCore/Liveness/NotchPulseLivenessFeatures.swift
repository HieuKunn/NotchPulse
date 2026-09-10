//
//  NotchPulseLivenessFeatures.swift
//  NotchPulse
//
//  Vision-facing half of liveness: turns a `FaceRecognitionResult` into a plain,
//  Vision-free `LivenessFrame` — keeps the decision logic compilable standalone.
//  Ported from Glance's LivenessFeatures.swift with NotchPulse naming.
//

import Vision
import CoreGraphics

nonisolated enum NotchPulseLivenessFeatureExtractor {
    /// Never fails — a face with no landmarks still yields a frame; cues that need landmarks abstain.
    ///
    /// - Parameter frame: the full camera frame, not `result.alignedImage` (a tightly-cropped
    ///   112x112 warp with no room around the face for `NotchPulseDeviceBezelDetector` to see a device edge).
    static func extract(
        from result: FaceRecognitionResult, frame: CGImage, faceCrop: CGImage? = nil, timestamp: Date = Date()
    ) -> LivenessFrame {
        let face = result.face
        let deviceOverlap = NotchPulseDeviceBezelDetector.detect(in: frame, faceBoundingBox: face.boundingBox).faceOverlapFraction
        let glare = faceCrop.flatMap { NotchPulseGlareCueExtractor.extract(faceCrop: $0) }

        guard let landmarks = face.landmarks else {
            return LivenessFrame(
                timestamp: timestamp, landmarks: [], interocularDistance: nil,
                yaw: face.yaw,
                leftEyeAspectRatio: nil, rightEyeAspectRatio: nil,
                noseOffsetRatio: nil,
                hasReliableLandmarks: false,
                deviceOverlapFraction: deviceOverlap,
                glare: glare
            )
        }

        let imageSize = face.imageSize
        let points = NotchPulseLandmarkGeometry.allPoints(from: landmarks, imageSize: imageSize)
        let interocular = NotchPulseLandmarkGeometry.interocularDistance(from: landmarks, imageSize: imageSize)
        let leftEAR = landmarks.leftEye.flatMap { NotchPulseLandmarkGeometry.eyeAspectRatio(of: $0, imageSize: imageSize) }
        let rightEAR = landmarks.rightEye.flatMap { NotchPulseLandmarkGeometry.eyeAspectRatio(of: $0, imageSize: imageSize) }

        let eyeLeft = NotchPulseLandmarkGeometry.eyeCenter(pupil: landmarks.leftPupil, eye: landmarks.leftEye, imageSize: imageSize)
        let eyeRight = NotchPulseLandmarkGeometry.eyeCenter(pupil: landmarks.rightPupil, eye: landmarks.rightEye, imageSize: imageSize)

        var noseOffsetRatio: CGFloat?
        if let interocular, interocular > 0, let eyeLeft, let eyeRight,
           let nose = landmarks.nose, let noseCenter = NotchPulseLandmarkGeometry.centroid(of: nose, imageSize: imageSize) {
            let eyeMidX = (eyeLeft.x + eyeRight.x) / 2
            noseOffsetRatio = (noseCenter.x - eyeMidX) / interocular
        }

        return LivenessFrame(
            timestamp: timestamp,
            landmarks: points,
            interocularDistance: interocular,
            yaw: face.yaw,
            leftEyeAspectRatio: leftEAR, rightEyeAspectRatio: rightEAR,
            noseOffsetRatio: noseOffsetRatio,
            hasReliableLandmarks: result.alignmentTier == .fivePoint,
            deviceOverlapFraction: deviceOverlap,
            glare: glare
        )
    }
}
