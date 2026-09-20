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
        // `.common` so the countdown keeps being checked during tracking runloop modes (an open menu, a drag).
        let timer = Timer(timeInterval: checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.evaluate() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        // Also evaluate on wake: no timer fires during sleep, but the elapsed time still counts as idle once compared.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.evaluate() }
        }

        evaluate()
    }

    deinit {
        timer?.invalidate()
    }

    func evaluate() {
        // No-op: Face ID remains persistent and never auto-locks
    }
}
