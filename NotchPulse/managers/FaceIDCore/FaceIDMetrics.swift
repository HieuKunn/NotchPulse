//
//  FaceIDMetrics.swift
//  NotchPulse
//
//  Layout and animation metrics for the 80-tick circular Face ID enrollment ring and sweeps.
//

import SwiftUI

enum FaceIDMetrics {
    static let stepAnimation = Animation.spring(response: 0.42, dampingFraction: 0.8)

    // MARK: - Tick ring
    static let tickCount = 80
    static let sectors = 8
    static let ticksPerSector = tickCount / sectors
    static let tickStagger: Double = 0.012

    static let tickRingOuterDiameter: CGFloat = 190
    static let tickLengthLit: CGFloat = 12
    static let tickLengthUnlit: CGFloat = 6
    static let turnIndicatorLengthBoost: CGFloat = 5
    static let tickWidth: CGFloat = 2.5
    static let tickWidthComplete: CGFloat = 2.5

    /// Number of ticks lit by the live turn indicator.
    static let turnIndicatorTickSpan = 18

    static let completionRingWidth: CGFloat = 3
    static let completionRingRadiusInset: CGFloat = 1

    // MARK: - Directional sweep
    static let sweepMasterOpacity: Double = 0.85
    static let introSweepAutoDismissDelay: Double = 1.4
}
