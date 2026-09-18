//
//  FaceIDDirectionSweep.swift
//  NotchPulse
//
//  Layered blurred light ribbons that sweep toward the instructed head turn direction.
//

import SwiftUI
import AppKit

enum FaceIDSweepDirection: CaseIterable, Hashable {
    case left, right, up, down, topLeft, topRight, bottomLeft, bottomRight

    var travel: CGVector {
        let d = CGFloat(1 / sqrt(2.0))
        switch self {
        case .left:        return CGVector(dx: -1, dy:  0)
        case .right:       return CGVector(dx:  1, dy:  0)
        case .up:          return CGVector(dx:  0, dy: -1)
        case .down:        return CGVector(dx:  0, dy:  1)
        case .topLeft:     return CGVector(dx: -d, dy: -d)
        case .topRight:    return CGVector(dx:  d, dy: -d)
        case .bottomLeft:  return CGVector(dx: -d, dy:  d)
        case .bottomRight: return CGVector(dx:  d, dy:  d)
        }
    }

    init?(pose: FaceIDEnrollmentPose) {
        switch pose {
        case .center:      return nil
        case .left:        self = .left
        case .right:       self = .right
        case .top:         self = .up
        case .bottom:      self = .down
        case .topLeft:     self = .topLeft
        case .topRight:    self = .topRight
        case .bottomLeft:  self = .bottomLeft
        case .bottomRight: self = .bottomRight
        }
    }
}

struct FaceIDDirectionSweepView: View {
    let direction: FaceIDSweepDirection

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(Self.specs) { spec in
                    SweepStreak(
                        spec: spec,
                        direction: direction,
                        canvasSize: geo.size
                    )
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .opacity(FaceIDMetrics.sweepMasterOpacity)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct StreakSpec: Identifiable {
    let id: Int
    let thickness: CGFloat
    let lengthFactor: CGFloat
    let blurScale: CGFloat
    let peakOpacity: Double
    let duration: Double
    let delay: Double
    let lateral: CGFloat
    let bow: CGFloat
    let fadeOutAt: Double
    let hasHighlight: Bool
    let isVivid: Bool
}

extension FaceIDDirectionSweepView {
    private static let specs: [StreakSpec] = [
        StreakSpec(id: 0, thickness: 56, lengthFactor: 0.90, blurScale: 1.0, peakOpacity: 0.85, duration: 1.15, delay: 0.00, lateral:  0.00, bow:  0.00, fadeOutAt: 0.95, hasHighlight: true,  isVivid: true),
        StreakSpec(id: 1, thickness: 36, lengthFactor: 0.70, blurScale: 0.8, peakOpacity: 0.65, duration: 1.05, delay: 0.04, lateral: -0.06, bow: -0.04, fadeOutAt: 0.85, hasHighlight: false, isVivid: true),
        StreakSpec(id: 2, thickness: 40, lengthFactor: 0.75, blurScale: 0.8, peakOpacity: 0.65, duration: 1.10, delay: 0.06, lateral:  0.07, bow:  0.05, fadeOutAt: 0.88, hasHighlight: false, isVivid: true),
        StreakSpec(id: 3, thickness: 80, lengthFactor: 1.10, blurScale: 1.3, peakOpacity: 0.40, duration: 1.30, delay: 0.02, lateral:  0.02, bow: -0.02, fadeOutAt: 1.00, hasHighlight: false, isVivid: false),
    ]
}

private struct SweepStreak: View {
    let spec: StreakSpec
    let direction: FaceIDSweepDirection
    let canvasSize: CGSize

    @State private var progress: CGFloat = 0

    var body: some View {
        let path = streakPath(at: progress)
        let strokeColor = spec.isVivid ? FaceIDTheme.accentBright : FaceIDTheme.accent
        ZStack {
            path
                .stroke(
                    strokeColor.opacity(streakOpacity),
                    style: StrokeStyle(lineWidth: spec.thickness, lineCap: .round)
                )
                .blur(radius: spec.thickness * 0.4 * spec.blurScale)

            if spec.hasHighlight {
                path
                    .stroke(
                        FaceIDTheme.accentPale.opacity(streakOpacity * 0.9),
                        style: StrokeStyle(lineWidth: spec.thickness * 0.35, lineCap: .round)
                    )
                    .blur(radius: spec.thickness * 0.15)
            }
        }
        .onAppear {
            withAnimation(
                .easeInOut(duration: spec.duration)
                .delay(spec.delay)
                .repeatForever(autoreverses: false)
            ) {
                progress = 1.0
            }
        }
    }

    private var streakOpacity: Double {
        if progress < 0.25 {
            return spec.peakOpacity * Double(progress / 0.25)
        } else if progress > CGFloat(spec.fadeOutAt) {
            let remain = 1.0 - progress
            let span = 1.0 - CGFloat(spec.fadeOutAt)
            return spec.peakOpacity * Double(max(0, remain / span))
        }
        return spec.peakOpacity
    }

    private func streakPath(at t: CGFloat) -> Path {
        let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        let travel = direction.travel
        let maxDist = max(canvasSize.width, canvasSize.height) * 0.85
        let start = CGPoint(x: center.x - travel.dx * maxDist * 0.5, y: center.y - travel.dy * maxDist * 0.5)
        let end   = CGPoint(x: center.x + travel.dx * maxDist * 0.5, y: center.y + travel.dy * maxDist * 0.5)

        let currStart = CGPoint(
            x: start.x + (end.x - start.x) * t,
            y: start.y + (end.y - start.y) * t
        )
        let length = maxDist * spec.lengthFactor * 0.35
        let currEnd = CGPoint(
            x: currStart.x + travel.dx * length,
            y: currStart.y + travel.dy * length
        )

        var p = Path()
        p.move(to: currStart)
        p.addLine(to: currEnd)
        return p
    }
}

// MARK: - Fullscreen Direction Sweep Window Controller

@MainActor
final class FaceIDDirectionSweepWindowController {
    static let shared = FaceIDDirectionSweepWindowController()

    private var window: NSPanel?
    private var currentDirection: FaceIDSweepDirection?

    func present(direction: FaceIDSweepDirection) {
        guard currentDirection != direction else { return }
        currentDirection = direction

        guard let screen = NSScreen.main else { return }
        dismiss()

        let hostingView = NSHostingView(rootView: FaceIDDirectionSweepView(direction: direction))
        hostingView.sizingOptions = []
        hostingView.frame = NSRect(origin: .zero, size: screen.frame.size)

        let panel = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = hostingView
        panel.setFrame(screen.frame, display: true)
        panel.orderFrontRegardless()

        self.window = panel
    }

    func dismiss() {
        window?.orderOut(nil)
        window = nil
        currentDirection = nil
    }
}
