//
//  FaceIDEnrollmentRingView.swift
//  NotchPulse
//
//  80 ticks tile the circle in 45-degree sectors that illuminate once each pose is captured.
//  The center pose pulses all ticks; directional poses track live head turning.
//

import SwiftUI

struct FaceIDEnrollmentRingView: View {
    let capturedPoses: Set<FaceIDEnrollmentPose>
    let currentTurn: FaceIDEnrollmentController.HeadTurn?
    let isComplete: Bool
    let centerPulse: Bool

    private var diameter: CGFloat { FaceIDMetrics.tickRingOuterDiameter }
    private var radius: CGFloat { diameter / 2 }

    var body: some View {
        ZStack {
            ForEach(0..<FaceIDMetrics.tickCount, id: \.self) { index in
                let intensity = turnIntensity(for: index, turn: currentTurn)
                let length = length(for: index, intensity: intensity)
                Capsule()
                    .fill(color(for: index, intensity: intensity))
                    .frame(width: width(for: index), height: length)
                    .offset(y: -(radius + length / 2))
                    .rotationEffect(.degrees(angle(for: index)))
                    .opacity(isComplete ? 0 : 1)
                    .animation(
                        .easeOut(duration: 0.3).delay(Double(index % FaceIDMetrics.ticksPerSector) * FaceIDMetrics.tickStagger),
                        value: isLit(index)
                    )
                    .animation(.easeOut(duration: 0.22), value: centerPulse)
                    .animation(.easeOut(duration: 0.15), value: intensity)
                    .animation(
                        .easeInOut(duration: 0.45).delay(Double(index) * 0.004),
                        value: isComplete
                    )
            }

            // Outer completion ring that scales in once all poses are done
            Circle()
                .stroke(FaceIDTheme.accent, lineWidth: FaceIDMetrics.completionRingWidth)
                .frame(
                    width: diameter + 2 * (FaceIDMetrics.tickLengthLit - FaceIDMetrics.completionRingRadiusInset) - FaceIDMetrics.completionRingWidth,
                    height: diameter + 2 * (FaceIDMetrics.tickLengthLit - FaceIDMetrics.completionRingRadiusInset) - FaceIDMetrics.completionRingWidth
                )
                .opacity(isComplete ? 1 : 0)
                .scaleEffect(isComplete ? 1 : 0.92)
                .animation(.easeInOut(duration: 0.45), value: isComplete)
        }
        .frame(width: diameter, height: diameter)
    }

    private func angle(for index: Int) -> Double {
        Double(index) * (360.0 / Double(FaceIDMetrics.tickCount))
    }

    private func sectorPose(for index: Int) -> FaceIDEnrollmentPose? {
        let raw = Int((angle(for: index) / 45.0).rounded()) % 8
        let sectorAngle = Double(raw) * 45
        return FaceIDEnrollmentPose.allCases.first { $0.compassAngle == sectorAngle }
    }

    private func isLit(_ index: Int) -> Bool {
        if isComplete { return true }
        guard let pose = sectorPose(for: index) else { return false }
        return capturedPoses.contains(pose)
    }

    private func length(for index: Int, intensity: Double) -> CGFloat {
        if isLit(index) || centerPulse { return FaceIDMetrics.tickLengthLit }
        return FaceIDMetrics.tickLengthUnlit + FaceIDMetrics.turnIndicatorLengthBoost * intensity
    }

    private func width(for index: Int) -> CGFloat {
        isComplete ? FaceIDMetrics.tickWidthComplete : FaceIDMetrics.tickWidth
    }

    private func color(for index: Int, intensity: Double) -> Color {
        if isLit(index) || isComplete { return FaceIDTheme.accent }
        return FaceIDTheme.whiteToAccent(intensity)
    }

    private func turnIntensity(for index: Int, turn: FaceIDEnrollmentController.HeadTurn?) -> Double {
        guard let turn, !isComplete, !isLit(index) else { return 0 }

        var delta = abs(angle(for: index) - turn.angle)
        if delta > 180 { delta = 360 - delta }

        let degreesPerTick = 360.0 / Double(FaceIDMetrics.tickCount)
        let halfSpan = Double(FaceIDMetrics.turnIndicatorTickSpan) / 2
        let falloff = max(0, 1 - (delta / degreesPerTick) / halfSpan)
        return turn.progress * falloff
    }
}
