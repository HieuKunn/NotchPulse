//
//  NotchPulseHitchDetector.swift
//  NotchPulse
//
//  Lightweight main-thread stall ("hitch") detector for diagnosing notch /
//  FaceID animation jank on user machines. A 30Hz runloop timer measures how
//  late each fire is: when the main thread stalls (heavy work, IPC, excessive
//  SwiftUI body re-evaluation), timer fires arrive late — the lateness IS the
//  dropped-frame budget. Hitches are throttled-logged via NSLog so they show
//  up in Console.app (filter "NotchPulse hitch") and the last 100 are kept in
//  memory for bug reports.
//

import Foundation
import AppKit

@MainActor
final class NotchPulseHitchDetector {
    static let shared = NotchPulseHitchDetector()

    struct Hitch: CustomStringConvertible {
        let at: TimeInterval        // seconds since process start
        let lateBy: TimeInterval    // seconds late vs schedule
        let context: String

        var description: String {
            String(format: "[%8.2fs] hitch %5.0f ms — %@", at, lateBy * 1000, context)
        }
    }

    private(set) var recentHitches: [Hitch] = []

    /// Provides a snapshot of what the notch UI was doing when a hitch happened.
    var contextProvider: (() -> String)?

    private var timer: Timer?
    private var lastScheduledFire: TimeInterval = -1
    private var lastLoggedAt: TimeInterval = -10
    private let interval: TimeInterval = 1.0 / 30.0
    /// 20ms late means animation frames were dropped at 60Hz+ — a real hitch.
    private let hitchThreshold: TimeInterval = 0.020
    private let processStart = ProcessInfo.processInfo.systemUptime

    private init() {}

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        lastScheduledFire = -1
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let scheduled = lastScheduledFire < 0 ? now : lastScheduledFire + interval

        let late = now - scheduled

        // BIG STALL handling: after a multi-second main-thread block the schedule can
        // never catch up (each fire only advances the schedule by one interval), which
        // used to report the stale lateness FOREVER and drowned out later data.
        // Report the stall ONCE with its true duration, then re-anchor to now.
        if late > 2.0 {
            let context = contextProvider?() ?? "unknown"
            let stallStart = scheduled
            let hitch = Hitch(at: stallStart - processStart, lateBy: late, context: context)
            recentHitches.append(hitch)
            if recentHitches.count > 100 {
                recentHitches.removeFirst(recentHitches.count - 100)
            }
            NSLog("🛑 NotchPulse BIG STALL %.1f s (main thread blocked, context: %@) — schedule re-anchored", late, context)
            lastLoggedAt = now
            lastScheduledFire = now
            return
        }

        lastScheduledFire = scheduled
        guard late > hitchThreshold else { return }

        let context = contextProvider?() ?? "unknown"
        let hitch = Hitch(at: now - processStart, lateBy: late, context: context)
        recentHitches.append(hitch)
        if recentHitches.count > 100 {
            recentHitches.removeFirst(recentHitches.count - 100)
        }

        // At most one log line per second for ordinary hitches; big stalls (>200ms)
        // always log so the worst offenders are never swallowed by throttling.
        if late > 0.2 || (now - lastLoggedAt) > 1.0 {
            lastLoggedAt = now
            NSLog("⚠️ NotchPulse hitch %+.0f ms — %@", late * 1000, context)
        }
    }

    /// Copy-paste block for bug reports.
    func dumpRecent() -> String {
        let lines = recentHitches.suffix(30).map { $0.description }
        guard !lines.isEmpty else { return "No hitches recorded." }
        return lines.joined(separator: "\n")
    }
}
