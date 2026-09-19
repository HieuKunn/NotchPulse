//
//  FaceIDGuidedSetupModalView.swift
//  NotchPulse
//
//  iOS-style circular guided Face ID setup modal with 80-tick animated ring,
//  compass pose tracking, and full-screen directional sweeps.
//

import SwiftUI

struct FaceIDGuidedSetupModalView: View {
    var onFinished: () -> Void
    var onCancelled: () -> Void

    @State private var controller: FaceIDEnrollmentController?

    var body: some View {
        ZStack {
            FaceIDVisualEffectView(material: .popover, blendingMode: .behindWindow)
                .ignoresSafeArea()
            Color.black.opacity(0.4) // Subtle dark tint over the glass
                .ignoresSafeArea()

            VStack(spacing: 24) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Set Up Face ID")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("Center your face, then slowly turn in the indicated directions")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }

                    Spacer()

                    Button {
                        controller?.cancel()
                        onCancelled()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 28)
                .padding(.top, 24)

                Spacer()

                // Circular Camera & 80-Tick Ring
                ZStack {
                    if let ctrl = controller, let image = ctrl.camera.currentFrame?.image {
                        Image(decorative: image, scale: 1.0, orientation: .up)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .scaleEffect(x: -1, y: 1) // Mirror selfie view
                            .frame(width: 175, height: 175)
                            .clipShape(Circle())
                    } else {
                        Circle()
                            .fill(Color.white.opacity(0.08))
                            .frame(width: 175, height: 175)
                        ProgressView()
                            .tint(.white)
                    }

                    if let ctrl = controller {
                        FaceIDEnrollmentRingView(
                            capturedPoses: ctrl.capturedPoses,
                            currentTurn: ctrl.headTurn,
                            isComplete: ctrl.enrollmentComplete,
                            centerPulse: ctrl.centerPulseTick
                        )
                    }
                }
                .frame(width: FaceIDMetrics.tickRingOuterDiameter + 40, height: FaceIDMetrics.tickRingOuterDiameter + 40)

                Spacer()

                // Instruction Prompt & Progress
                VStack(spacing: 12) {
                    if let ctrl = controller {
                        Text(ctrl.enrollmentInstruction)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                            .animation(.easeInOut(duration: 0.2), value: ctrl.enrollmentInstruction)

                        // 9-dots pose indicator
                        HStack(spacing: 8) {
                            ForEach(FaceIDEnrollmentPose.allCases) { pose in
                                Circle()
                                    .fill(ctrl.capturedPoses.contains(pose) ? FaceIDTheme.accent : Color.white.opacity(0.2))
                                    .frame(width: 8, height: 8)
                            }
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.bottom, 32)
            }
        }
        .frame(width: 480, height: 460)
        .onAppear {
            let ctrl = FaceIDEnrollmentController(
                onFinished: onFinished,
                onCancelled: onCancelled
            )
            self.controller = ctrl
            ctrl.start()
        }
        .onDisappear {
            controller?.cancel()
        }
    }
}
