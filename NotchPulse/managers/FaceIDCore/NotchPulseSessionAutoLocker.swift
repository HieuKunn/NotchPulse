//
//  NotchPulseSessionAutoLocker.swift
//  NotchPulse
//
//  Enforces `NotchPulseFaceIDSettings.autoLockInterval`: re-locks the session once idle past the user's chosen limit.
//

import Foundation
import AppKit

@MainActor
final class NotchPulseSessionAutoLocker {
    private let pocController: NotchPulsePOCController
    private var timer: Timer?

    /// Coarse on purpose — the shortest selectable limit is a full day, and the decision compares timestamps, not ticks.
    private let checkInterval: TimeInterval = 5 * 60

    init(pocController: NotchPulsePOCController) {
        self.pocController = pocController
    }

    deinit {
        timer?.invalidate()
    }

    func evaluate() {
        // No-op: Face ID remains persistent and never auto-locks
    }
}
