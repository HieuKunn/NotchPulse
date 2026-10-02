//
//  NotchHoverDetector.swift
//  NotchPulse
//
//  Created by Alexander on 2026-10-02.
//

import Cocoa
import Combine
import Defaults

@MainActor
final class NotchHoverDetector {
    typealias VoidCallback = () -> Void
    typealias PositionCallback = (_ globalPoint: CGPoint) -> Void

    var onHoverEntersNotchRegion: VoidCallback?
    var onHoverExitsNotchRegion: VoidCallback?
    var onHoverMove: PositionCallback?

    private var globalMouseMovedMonitor: Any?
    private var localMouseMovedMonitor: Any?
    private var globalMouseClickMonitor: Any?
    private var localMouseClickMonitor: Any?

    private var openTimerTask: Task<Void, Never>?
    private var closeDebounceTask: Task<Void, Never>?
    private(set) var isCursorInNotchRegion: Bool = false

    private let closedRegionProvider: () -> CGRect
    private let openRegionProvider: () -> CGRect
    private let isNotchOpenProvider: () -> Bool

    init(
        closedRegionProvider: @escaping () -> CGRect,
        openRegionProvider: @escaping () -> CGRect,
        isNotchOpenProvider: @escaping () -> Bool
    ) {
        self.closedRegionProvider = closedRegionProvider
        self.openRegionProvider = openRegionProvider
        self.isNotchOpenProvider = isNotchOpenProvider
    }

    func startMonitoring() {
        stopMonitoring()

        // Ultra-lightweight event monitors on Main RunLoop
        globalMouseMovedMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            let loc = NSEvent.mouseLocation
            if Thread.isMainThread {
                self?.handleMouseLocation(loc)
            } else {
                DispatchQueue.main.async {
                    self?.handleMouseLocation(loc)
                }
            }
        }

        localMouseMovedMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            self?.handleMouseLocation(NSEvent.mouseLocation)
            return event
        }

        globalMouseClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            let loc = NSEvent.mouseLocation
            if Thread.isMainThread {
                self?.handleMouseLocation(loc)
            } else {
                DispatchQueue.main.async {
                    self?.handleMouseLocation(loc)
                }
            }
        }

        localMouseClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.handleMouseLocation(NSEvent.mouseLocation)
            return event
        }
    }

    func handleMouseLocation(_ mouseLocation: CGPoint) {
        onHoverMove?(mouseLocation)

        let isOpen = isNotchOpenProvider()
        let activeRegion = isOpen ? openRegionProvider() : closedRegionProvider()

        // Fast O(1) vertical early-exit filter: if cursor is well below notch region
        // and wasn't inside, instantly return without calculating intersections
        if mouseLocation.y < (activeRegion.minY - 15) {
            if isCursorInNotchRegion {
                // Exited notch
                isCursorInNotchRegion = false
                openTimerTask?.cancel()
                openTimerTask = nil

                if isOpen {
                    closeDebounceTask?.cancel()
                    closeDebounceTask = Task { @MainActor [weak self] in
                        try? await Task.sleep(for: .milliseconds(120))
                        guard !Task.isCancelled, let self = self else { return }
                        if !self.isCursorInNotchRegion && self.isNotchOpenProvider() {
                            self.onHoverExitsNotchRegion?()
                        }
                    }
                }
            }
            return
        }

        let containsMouse = activeRegion.contains(mouseLocation)

        if containsMouse {
            closeDebounceTask?.cancel()
            closeDebounceTask = nil

            if !isCursorInNotchRegion {
                isCursorInNotchRegion = true

                if !isOpen {
                    // Start hover timer to open notch
                    guard Defaults[.openNotchOnHover] else { return }
                    openTimerTask?.cancel()

                    let hoverDelay = max(0.0, Defaults[.minimumHoverDuration])
                    if hoverDelay <= 0.02 {
                        self.onHoverEntersNotchRegion?()
                    } else {
                        openTimerTask = Task { @MainActor [weak self] in
                            try? await Task.sleep(for: .seconds(hoverDelay))
                            guard !Task.isCancelled, let self = self else { return }
                            if self.isCursorInNotchRegion && !self.isNotchOpenProvider() {
                                self.onHoverEntersNotchRegion?()
                            }
                        }
                    }
                }
            }
        } else {
            openTimerTask?.cancel()
            openTimerTask = nil

            if isCursorInNotchRegion {
                isCursorInNotchRegion = false

                if isOpen {
                    // Debounce exit slightly to avoid flickering on fast edge traversal
                    closeDebounceTask?.cancel()
                    closeDebounceTask = Task { @MainActor [weak self] in
                        try? await Task.sleep(for: .milliseconds(120))
                        guard !Task.isCancelled, let self = self else { return }
                        if !self.isCursorInNotchRegion && self.isNotchOpenProvider() {
                            self.onHoverExitsNotchRegion?()
                        }
                    }
                }
            }
        }
    }

    func cancelPendingTasks() {
        openTimerTask?.cancel()
        openTimerTask = nil
        closeDebounceTask?.cancel()
        closeDebounceTask = nil
    }

    func stopMonitoring() {
        cancelPendingTasks()

        if let monitor = globalMouseMovedMonitor {
            NSEvent.removeMonitor(monitor)
            globalMouseMovedMonitor = nil
        }
        if let monitor = localMouseMovedMonitor {
            NSEvent.removeMonitor(monitor)
            localMouseMovedMonitor = nil
        }
        if let monitor = globalMouseClickMonitor {
            NSEvent.removeMonitor(monitor)
            globalMouseClickMonitor = nil
        }
        if let monitor = localMouseClickMonitor {
            NSEvent.removeMonitor(monitor)
            localMouseClickMonitor = nil
        }
        isCursorInNotchRegion = false
    }

    deinit {
        // Observers removed in stopMonitoring()
    }
}
