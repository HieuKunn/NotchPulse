import Vision
import CoreGraphics

struct DeviceBezelObservation {
    /// Largest device-plausible rectangle found this frame, same pixel space as `DetectedFace.boundingBox`.
    let rectangle: CGRect?
    /// Fraction of the face's bounding box area that falls inside `rectangle`.
    let faceOverlapFraction: CGFloat?

    nonisolated static let none = DeviceBezelObservation(rectangle: nil, faceOverlapFraction: nil)
}

enum NotchPulseDeviceBezelDetector {
    /// Estimates tuned to reliably detect mobile phone and tablet screens/bezels.
    private static func makeRequest() -> VNDetectRectanglesRequest {
        let request = VNDetectRectanglesRequest()
        request.minimumConfidence = 0.45
        // Fraction of the lesser image dimension
        request.minimumSize = 0.08
        request.maximumObservations = 10
        // Covers phone-in-portrait (0.30) through near-square tablet (1.0) and landscape phone/tablet (up to 2.8).
        request.minimumAspectRatio = 0.30
        request.maximumAspectRatio = 2.8
        // Generous so a phone held at an angle still registers.
        request.quadratureTolerance = 40

        return request
    }

    /// Synchronous and CPU-bound — call from a background task, same as `NotchPulseFaceDetector.detectFaces`.
    static func detect(in image: CGImage, faceBoundingBox: CGRect) -> DeviceBezelObservation {
        let request = makeRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil,
              let results = request.results, !results.isEmpty
        else { return .none }

        let imageSize = CGSize(width: image.width, height: image.height)
        let candidates = results.map { NotchPulseFaceDetector.convertToImageSpace($0.boundingBox, imageSize: imageSize) }

        let faceArea = faceBoundingBox.width * faceBoundingBox.height
        guard faceArea > 0 else { return .none }

        // Find candidate rectangles that contain or overlap the face.
        // A phone holding a face photo will enclose or overlap the detected face!
        var bestCandidate: CGRect?
        var maxOverlap: CGFloat = 0

        for candidate in candidates {
            let intersection = candidate.intersection(faceBoundingBox)
            guard !intersection.isEmpty else { continue }
            let overlap = (intersection.width * intersection.height) / faceArea
            if overlap > maxOverlap {
                maxOverlap = overlap
                bestCandidate = candidate
            }
        }

        if let bestCandidate, maxOverlap > 0 {
            return DeviceBezelObservation(rectangle: bestCandidate, faceOverlapFraction: maxOverlap)
        }

        // Fallback: if no candidate overlaps the face, largest candidate
        guard let largest = candidates.max(by: { $0.width * $0.height < $1.width * $1.height }) else {
            return .none
        }
        let intersection = largest.intersection(faceBoundingBox)
        let overlap = (intersection.width * intersection.height) / faceArea
        return DeviceBezelObservation(rectangle: largest, faceOverlapFraction: overlap)
    }
}
