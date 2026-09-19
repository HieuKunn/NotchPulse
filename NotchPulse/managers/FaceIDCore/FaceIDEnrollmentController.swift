//
//  FaceIDEnrollmentController.swift
//  NotchPulse
//
//  State machine for guided 9-pose face enrollment:
//  Center + 8 compass head turn poses, live yaw/pitch tracking,
//  and ArcFace 512D multi-sample template generation.
//

import Foundation
import CoreGraphics
import SwiftUI
import Observation

enum FaceIDEnrollmentPose: Int, CaseIterable, Identifiable {
    case center, left, topLeft, top, topRight, right, bottomRight, bottom, bottomLeft

    var id: Int { rawValue }

    enum YawBand { case left, none, right }
    enum PitchBand { case up, none, down }

    var yawBand: YawBand {
        switch self {
        case .left, .topLeft, .bottomLeft: return .left
        case .right, .topRight, .bottomRight: return .right
        case .center, .top, .bottom: return .none
        }
    }

    var pitchBand: PitchBand {
        switch self {
        case .top, .topLeft, .topRight: return .up
        case .bottom, .bottomLeft, .bottomRight: return .down
        case .center, .left, .right: return .none
        }
    }

    /// Compass angle (0 = up, clockwise) this pose's ring sector is centered on.
    var compassAngle: Double? {
        switch self {
        case .center: return nil
        case .left: return 270
        case .topLeft: return 315
        case .top: return 0
        case .topRight: return 45
        case .right: return 90
        case .bottomRight: return 135
        case .bottom: return 180
        case .bottomLeft: return 225
        }
    }

    var instruction: String {
        switch self {
        case .center: return "Look straight at the camera"
        case .left: return "Turn your head slightly left"
        case .topLeft: return "Turn your head to the top left"
        case .top: return "Turn your head slightly up"
        case .topRight: return "Turn your head to the top right"
        case .right: return "Turn your head slightly right"
        case .bottomRight: return "Turn your head to the bottom right"
        case .bottom: return "Turn your head slightly down"
        case .bottomLeft: return "Turn your head to the bottom left"
        }
    }

    var matchLeniency: Float {
        switch self {
        case .bottomLeft, .bottomRight: return 1.5
        case .bottom: return 1.2
        default: return 1.0
        }
    }

    var name: String {
        switch self {
        case .center: return "center"
        case .left: return "left"
        case .topLeft: return "top_left"
        case .top: return "top"
        case .topRight: return "top_right"
        case .right: return "right"
        case .bottomRight: return "bottom_right"
        case .bottom: return "bottom"
        case .bottomLeft: return "bottom_left"
        }
    }
}

@Observable
@MainActor
final class FaceIDEnrollmentController {
    let camera = NotchPulseCamera()
    let pipeline = NotchPulseFaceRecognitionPipeline()
    private let store = NotchPulseFaceEnrollmentStore.shared

    // MARK: - State
    var currentPoseIndex: Int = 0
    var capturedPoses: Set<FaceIDEnrollmentPose> = []
    var enrollmentComplete: Bool = false
    var centerPulseTick: Bool = false
    var isTooFar: Bool = false
    var faceDetected: Bool = false
    var currentYaw: Float?
    var currentPitch: Float?
    var debugError: String?

    var onFinished: (() -> Void)?
    var onCancelled: (() -> Void)?

    private var collectedSamples: [FaceSample] = []
    private var isProcessingFrame = false
    private var poseHoldStartedAt: ContinuousClock.Instant?
    private let poseHoldDuration: Duration = .milliseconds(380)

    // MARK: - Enrollment pose matching thresholds (aligned with glance)
    /// Yaw offset from straight-ahead at which a "left" or "right" pose is counted — mirrors glance's `yawInnerThreshold`.
    private let yawInnerThreshold: Float = 0.25
    /// Yaw tolerance for the center pose and center-band poses — mirrors glance's `yawCenterTolerance`.
    private let yawCenterTolerance: Float = 0.18
    /// Maximum accepted yaw — beyond this the pose is too extreme and alignment quality drops — mirrors glance's `yawOuterCap`.
    private let yawOuterCap: Float = 1.2
    /// Pitch offset from level at which an "up" or "down" pose is counted — mirrors glance's `pitchInnerThreshold`.
    private let pitchInnerThreshold: Float = 0.20
    /// Pitch tolerance for level/center-pitch poses — mirrors glance's `pitchCenterTolerance`.
    private let pitchCenterTolerance: Float = 0.15
    /// Maximum accepted pitch magnitude — mirrors glance's `pitchOuterCap`.
    private let pitchOuterCap: Float = 0.9
    /// 9 poses × 2 samples = 18 total, enough for a stable template — mirrors glance's `samplesPerPose`.
    private let samplesPerPose = 2
    /// How many samples have been captured for the currently active pose.
    private var capturedForCurrentPose = 0

    var currentPose: FaceIDEnrollmentPose? {
        let poses = FaceIDEnrollmentPose.allCases
        guard currentPoseIndex >= 0 && currentPoseIndex < poses.count else { return nil }
        return poses[currentPoseIndex]
    }

    var enrollmentInstruction: String {
        if enrollmentComplete { return "Face ID Setup Complete!" }
        if isTooFar { return "Bring your face closer to the camera" }
        guard let pose = currentPose else { return "Align your face in the circle" }
        return pose.instruction
    }

    struct HeadTurn: Equatable {
        let angle: Double
        let progress: Double
    }

    private let headTurnDeadzone: Double = 0.15

    var headTurn: HeadTurn? {
        guard !enrollmentComplete, faceDetected, !isTooFar,
              let pose = currentPose, pose != .center,
              let yaw = currentYaw, let pitch = currentPitch else { return nil }

        let leniency: Double = Double(pose.matchLeniency)
        let x: Double = Double(-yaw) / (Double(yawInnerThreshold) / leniency)
        let y: Double = Double(-pitch) / (Double(pitchInnerThreshold) / leniency)

        let magnitude: Double = sqrt(x * x + y * y)
        guard magnitude > headTurnDeadzone else { return nil }

        let degrees = atan2(x, y) * 180.0 / .pi
        return HeadTurn(angle: degrees < 0 ? degrees + 360.0 : degrees, progress: min(magnitude, 1.0))
    }

    var progress: Double {
        Double(capturedPoses.count) / Double(FaceIDEnrollmentPose.allCases.count)
    }

    init(onFinished: (() -> Void)? = nil, onCancelled: (() -> Void)? = nil) {
        self.onFinished = onFinished
        self.onCancelled = onCancelled
        observeCameraFrames()
    }

    func start() {
        reset()
        Task { @MainActor in
            await camera.requestAccessAndStart()
            updateDirectionSweep()
        }
    }

    func cancel() {
        FaceIDDirectionSweepWindowController.shared.dismiss()
        camera.stop()
        onCancelled?()
    }

    private func reset() {
        currentPoseIndex = 0
        capturedPoses.removeAll()
        collectedSamples.removeAll()
        capturedForCurrentPose = 0
        enrollmentComplete = false
        centerPulseTick = false
        poseHoldStartedAt = nil
    }

    private func observeCameraFrames() {
        _ = withObservationTracking {
            camera.currentFrame
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.observeCameraFrames()
                self?.processCurrentFrame()
            }
        }
    }

    private func processCurrentFrame() {
        guard !enrollmentComplete, !isProcessingFrame,
              let frame = camera.currentFrame else { return }

        isProcessingFrame = true
        let image = frame.image

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let faces = try? NotchPulseFaceDetector.detectFaces(in: image),
                  let face = NotchPulseFaceRecognitionPipeline.selectDominantFace(in: faces) ?? faces.first else {
                await MainActor.run {
                    guard let self = self else { return }
                    self.isProcessingFrame = false
                    self.faceDetected = false
                    self.currentYaw = nil
                    self.currentPitch = nil
                    self.poseHoldStartedAt = nil
                }
                return
            }

            await MainActor.run {
                guard let self = self, !self.enrollmentComplete else { return }
                defer { self.isProcessingFrame = false }

                self.faceDetected = true
                self.currentYaw = face.yaw
                self.currentPitch = face.pitch ?? face.roll

                // Check distance / prominence — enrollment needs closer proximity than unlock
                // so the template samples have enough pixel detail. Mirrors glance's `enrollmentMinimumFaceWidth`.
                let faceWidth = Float(face.normalizedBoundingBox.width)
                if faceWidth < max(NotchPulseFaceRecognitionPipeline.minimumProminentFaceWidth, 0.20) {
                    self.isTooFar = true
                    self.poseHoldStartedAt = nil
                    return
                }
                self.isTooFar = false

                guard let targetPose = self.currentPose else { return }

                if self.matches(pose: targetPose, yaw: face.yaw ?? 0, pitch: face.pitch ?? face.roll ?? 0) {
                    if let started = self.poseHoldStartedAt {
                        if ContinuousClock.now - started >= self.poseHoldDuration {
                            self.capturePose(targetPose, face: face, frame: image)
                        }
                    } else {
                        self.poseHoldStartedAt = .now
                    }
                } else {
                    self.poseHoldStartedAt = nil
                }
            }
        }
    }

    private func matches(pose: FaceIDEnrollmentPose, yaw: Float, pitch: Float) -> Bool {
        let factor: Float = pose.matchLeniency

        switch pose.yawBand {
        case .left:  guard yaw > yawInnerThreshold / factor && yaw < yawOuterCap else { return false }
        case .right: guard yaw < -yawInnerThreshold / factor && yaw > -yawOuterCap else { return false }
        case .none:  guard abs(yaw) < yawCenterTolerance * factor else { return false }
        }

        switch pose.pitchBand {
        case .up:   guard pitch < -pitchInnerThreshold / factor && pitch > -pitchOuterCap else { return false }
        case .down: guard pitch > pitchInnerThreshold / factor && pitch < pitchOuterCap else { return false }
        case .none: guard abs(pitch) < pitchCenterTolerance * factor else { return false }
        }

        return true
    }

    private func capturePose(_ pose: FaceIDEnrollmentPose, face: DetectedFace, frame: CGImage) {
        poseHoldStartedAt = nil

        do {
            let result = try pipeline.recognize(face, in: frame)
            self.debugError = nil
            
            let sample = FaceSample(
                embedding: result.embedding,
                pose: pose.name,
                capturedAt: Date(),
                quality: face.quality ?? 0.95
            )
            collectedSamples.append(sample)
            capturedForCurrentPose += 1
            
            if capturedForCurrentPose >= samplesPerPose {
                capturedPoses.insert(pose)
                capturedForCurrentPose = 0
                if pose == .center { triggerCenterPulse() }
                currentPoseIndex += 1
                if currentPoseIndex >= FaceIDEnrollmentPose.allCases.count { finishEnrollment() } else { updateDirectionSweep() }
            }
        } catch {
            self.debugError = "\(error)"
            print("[FaceID] Pipeline recognize error: \(error)")
        }
    }

    private func triggerCenterPulse() {
        centerPulseTick = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            centerPulseTick = false
        }
    }

    private func updateDirectionSweep() {
        guard let pose = currentPose, let sweepDir = FaceIDSweepDirection(pose: pose) else {
            FaceIDDirectionSweepWindowController.shared.dismiss()
            return
        }
        FaceIDDirectionSweepWindowController.shared.present(direction: sweepDir)
    }

    private func finishEnrollment() {
        FaceIDDirectionSweepWindowController.shared.dismiss()
        enrollmentComplete = true

        let embedder = pipeline.embedder

        // Save to secure face store and reload
        do {
            try store.commitEnrollment(
                replacing: nil,
                name: "My Face",
                samples: collectedSamples,
                embedder: embedder
            )
        } catch {
            print("[FaceID] Enrollment save failed: \(error)")
        }
        FaceIDManager.shared.refreshState()

        NSSound(named: "Ping")?.play()

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            camera.stop()
            onFinished?()
        }
    }
}
