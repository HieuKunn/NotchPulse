//
//  PanGesture.swift
//  NotchPulse
//
//  Created by Richard Kunkli on 21/08/2024.
//

import AppKit
import SwiftUI

enum PanDirection {
    case left, right, up, down

    var isHorizontal: Bool { self == .left || self == .right }
    var sign: CGFloat { (self == .right || self == .down) ? 1 : -1 }

    func signed(from translation: CGSize) -> CGFloat { (isHorizontal ? translation.width : translation.height) * sign }
    func signed(deltaX: CGFloat, deltaY: CGFloat) -> CGFloat { (isHorizontal ? deltaX : deltaY) * sign }
}

extension View {
    func panGesture(direction: PanDirection, threshold: CGFloat = 4, action: @escaping (CGFloat, NSEvent.Phase) -> Void) -> some View {
        self
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { value in
                        let s = direction.signed(from: value.translation)
                        guard s > 0, s.magnitude >= threshold else { return }
                        action(s.magnitude, .changed)
                    }
                    .onEnded { _ in action(0, .ended) }
            )
            .background(ScrollMonitor(direction: direction, threshold: threshold, action: action))
    }
}

private struct ScrollMonitor: NSViewRepresentable {
    let direction: PanDirection
    let threshold: CGFloat
    let action: (CGFloat, NSEvent.Phase) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.installMonitor(on: view)
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) { coordinator.removeMonitor() }

    func makeCoordinator() -> Coordinator { 
        Coordinator(direction: direction, threshold: threshold, action: action) 
    }

    @MainActor final class Coordinator: NSObject {
        private let direction: PanDirection
        private let threshold: CGFloat
        private let action: (CGFloat, NSEvent.Phase) -> Void
        private var monitor: Any?
        private var accumulated: CGFloat = 0
        private var active = false
            private var endTask: Task<Void, Never>?
        private let noiseThreshold: CGFloat = 0.2

        init(direction: PanDirection, threshold: CGFloat, action: @escaping (CGFloat, NSEvent.Phase) -> Void) {
            self.direction = direction
            self.threshold = threshold
            self.action = action
        }

        private func scheduleEndTimeout() {
            // Cancel any existing scheduled end and schedule a new one.
            endTask?.cancel()
            endTask = Task { @MainActor in
                // If no new scroll event arrives within this window, consider the gesture ended.
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                if active {
                    action(accumulated.magnitude, .ended)
                } else {
                    action(0, .ended)
                }
                active = false
                accumulated = 0
            }
        }

        func installMonitor(on view: NSView) {
            removeMonitor()
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self, weak view] event in
                guard let self = self, event.window === view?.window else { return event }
                if self.shouldIgnoreScrollForNestedScrollView(event: event, in: view) {
                    if self.active {
                        self.action(0, .ended)
                        self.active = false
                    }
                    self.accumulated = 0
                    return event
                }
                self.handleScroll(event)
                return event
            }
        }

        private func shouldIgnoreScrollForNestedScrollView(event: NSEvent, in rootNSView: NSView?) -> Bool {
            guard let window = rootNSView?.window,
                  let contentView = window.contentView else { return false }

            let localPoint = contentView.convert(event.locationInWindow, from: nil)
            guard let hitView = contentView.hitTest(localPoint) else { return false }

            // Find enclosing NSScrollView if the cursor is hovering over a scrollable component
            var current: NSView? = hitView
            var targetScrollView: NSScrollView?
            while let v = current {
                if let sv = v as? NSScrollView {
                    targetScrollView = sv
                    break
                }
                current = v.superview
            }

            guard let scrollView = targetScrollView,
                  let docView = scrollView.documentView else { return false }

            let clipView = scrollView.contentView
            let docRect = docView.bounds
            let clipBounds = clipView.bounds

            if direction == .up || direction == .down {
                let isVerticallyScrollable = docRect.height > (clipBounds.height + 4.0)
                guard isVerticallyScrollable else { return false }

                let isFlipped = clipView.isFlipped
                let maxY = max(0, docRect.height - clipBounds.height)
                let currentY = clipBounds.origin.y

                if direction == .up {
                    // Swiping up (moving towards bottom of document)
                    // If not yet at the bottom boundary, let the scroll view scroll its contents
                    let isAtBottom = isFlipped ? (currentY >= maxY - 4.0) : (currentY <= 4.0)
                    return !isAtBottom
                } else if direction == .down {
                    // Swiping down (moving towards top of document)
                    // If not yet at the top boundary, let the scroll view scroll its contents
                    let isAtTop = isFlipped ? (currentY <= 4.0) : (currentY >= maxY - 4.0)
                    return !isAtTop
                }
            } else if direction == .left || direction == .right {
                let isHorizontallyScrollable = docRect.width > (clipBounds.width + 4.0)
                guard isHorizontallyScrollable else { return false }

                let maxX = max(0, docRect.width - clipBounds.width)
                let currentX = clipBounds.origin.x

                if direction == .left {
                    let isAtRight = currentX >= maxX - 4.0
                    return !isAtRight
                } else if direction == .right {
                    let isAtLeft = currentX <= 4.0
                    return !isAtLeft
                }
            }

            return false
        }

        func removeMonitor() {
            if let monitor = monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            accumulated = 0
            active = false
            endTask?.cancel()
            endTask = nil
        }

        private func handleScroll(_ event: NSEvent) {
            if event.phase == .ended || event.momentumPhase == .ended {
                if active {
                    action(accumulated.magnitude, .ended)
                } else {
                    action(0, .ended)
                }
                active = false
                accumulated = 0
                return
            }

            // Only consider scroll events that are primarily along the configured axis.
            let absDX = abs(event.scrollingDeltaX)
            let absDY = abs(event.scrollingDeltaY)
            // Require the movement along the gesture axis to be at least 1.5x the orthogonal axis.
            let axisDominanceFactor: CGFloat = 1.5
            let isAxisDominant: Bool = direction.isHorizontal ? (absDX >= axisDominanceFactor * absDY) : (absDY >= axisDominanceFactor * absDX)
            guard isAxisDominant else { return }

            // Scale non-precise (mouse wheel) scrolling deltas so they feel similar to
            // trackpad gestures.
            let raw = direction.signed(deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY)
            let scale: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 8
            let s = raw * scale
            guard s.magnitude > noiseThreshold else { return }
            accumulated = s > 0 ? accumulated + s : 0

            if !active && accumulated >= threshold {
                active = true
                action(accumulated.magnitude, .began)
            } else if active {
                action(accumulated.magnitude, .changed)
            }
            // Schedule a timeout to end the gesture if no further scroll events arrive.
            scheduleEndTimeout()
        }
    }
}
