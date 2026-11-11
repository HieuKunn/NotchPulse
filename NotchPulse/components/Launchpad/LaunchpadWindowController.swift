import AppKit
import Combine
import Defaults
import SwiftUI

/// Borderless panel that accepts key events and text input without switching
/// the host app out of accessory (LSUIElement) activation policy.
final class LaunchpadPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Manages the fullscreen Launchpad Home window lifecycle, screen placement,
/// optional Hot Corner monitoring, and AppKit swipe/keyboard event monitors.
@MainActor
final class LaunchpadWindowController: NSObject, ObservableObject {
    static let shared = LaunchpadWindowController()

    @Published private(set) var isPresented: Bool = false
    @Published var liveSwipeOffset: CGFloat = 0

    private var panel: LaunchpadPanel?
    private var hasInstalledContent = false
    private weak var previousFrontmostApp: NSRunningApplication?
    private var defaultsCancellable: AnyCancellable?
    private var presentationGeneration: Int = 0
    private var lastShownAt: Date = .distantPast

    // Local event monitors while Launchpad is open
    private var keyMonitor: Any?
    private var scrollMonitor: Any?
    private var magnifyMonitor: Any?
    private var mouseResignObserver: Any?

    // Trackpad swipe / scroll wheel paging state
    private var isTrackingHorizontalSwipe = false
    private var accumulatedSwipeX: CGFloat = 0
    private var lastWheelStepTime: Date = .distantPast
    private var accumulatedMagnification: CGFloat = 0

    // Hot Corner monitor state
    private var hotCornerGlobalMonitor: Any?
    private var hotCornerLocalMonitor: Any?
    private var hotCornerDwellTask: Task<Void, Never>?
    private var isPointerInHotCorner = false

    private override init() {
        super.init()
        defaultsCancellable = Defaults.publisher(.launchpadHotCorner)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.configureHotCornerMonitor()
            }
    }

    // MARK: - Public Presentation API

    func toggle() {
        guard Defaults[.enableLaunchpad] else { return }
        if isPresented {
            dismiss(restorePreviousApp: true)
        } else {
            show()
        }
    }

    func show() {
        guard Defaults[.enableLaunchpad] else { return }
        guard !NotchPulseLockMonitor.isScreenActuallyLocked() else { return }

        if let active = NSWorkspace.shared.frontmostApplication,
           active.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousFrontmostApp = active
        }

        let targetScreen = Self.screenUnderPointer() ?? NSScreen.main
        guard let screen = targetScreen else { return }

        LaunchpadManager.shared.prepareForPresentation()

        let panel = ensurePanel(for: screen)
        panel.setFrame(screen.frame, display: true)
        panel.alphaValue = 0

        presentationGeneration += 1
        lastShownAt = Date()
        isPresented = true
        liveSwipeOffset = 0
        installLocalMonitors()

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()

        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.alphaValue = 1
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.20
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        }
    }

    func dismiss(restorePreviousApp: Bool = true, completion: (@MainActor @Sendable () -> Void)? = nil) {
        guard isPresented, let panel else {
            completion?()
            return
        }

        presentationGeneration += 1
        let dismissGen = presentationGeneration
        isPresented = false
        removeLocalMonitors()
        liveSwipeOffset = 0
        isTrackingHorizontalSwipe = false
        accumulatedSwipeX = 0
        accumulatedMagnification = 0

        let finishDismiss: @MainActor @Sendable () -> Void = { [weak self] in
            guard let self, self.presentationGeneration == dismissGen else {
                completion?()
                return
            }
            panel.orderOut(nil)
            panel.alphaValue = 1
            LaunchpadManager.shared.searchQuery = ""
            LaunchpadManager.shared.activeFolderId = nil
            LaunchpadManager.shared.isEditingMode = false

            if restorePreviousApp,
               let prev = self.previousFrontmostApp,
               !prev.isTerminated {
                prev.activate()
            }
            self.previousFrontmostApp = nil
            completion?()
        }

        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            finishDismiss()
        } else {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.16
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().alphaValue = 0
            }, completionHandler: {
                Task { @MainActor in
                    finishDismiss()
                }
            })
        }
    }

    // MARK: - Hot Corner Support

    func configureHotCornerMonitor() {
        if let global = hotCornerGlobalMonitor {
            NSEvent.removeMonitor(global)
            hotCornerGlobalMonitor = nil
        }
        if let local = hotCornerLocalMonitor {
            NSEvent.removeMonitor(local)
            hotCornerLocalMonitor = nil
        }
        hotCornerDwellTask?.cancel()
        hotCornerDwellTask = nil
        isPointerInHotCorner = false

        guard Defaults[.enableLaunchpad], Defaults[.launchpadHotCorner] != .none else { return }

        hotCornerGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            Task { @MainActor in
                self?.evaluateHotCorner()
            }
        }
        hotCornerLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            Task { @MainActor in
                self?.evaluateHotCorner()
            }
            return event
        }
    }

    private func evaluateHotCorner() {
        let corner = Defaults[.launchpadHotCorner]
        guard Defaults[.enableLaunchpad], corner != .none else { return }
        guard !NotchPulseLockMonitor.isScreenActuallyLocked() else { return }
        guard NSEvent.pressedMouseButtons == 0 else { return }

        let mouse = NSEvent.mouseLocation
        guard let screen = Self.screenUnderPointer() else { return }
        let frame = screen.frame
        let threshold: CGFloat = 6.0

        let inCorner: Bool
        switch corner {
        case .none:
            inCorner = false
        case .topLeft:
            inCorner = mouse.x <= frame.minX + threshold && mouse.y >= frame.maxY - threshold
        case .topRight:
            inCorner = mouse.x >= frame.maxX - threshold && mouse.y >= frame.maxY - threshold
        case .bottomLeft:
            inCorner = mouse.x <= frame.minX + threshold && mouse.y <= frame.minY + threshold
        case .bottomRight:
            inCorner = mouse.x >= frame.maxX - threshold && mouse.y <= frame.minY + threshold
        }

        if inCorner {
            guard !isPointerInHotCorner else { return }
            isPointerInHotCorner = true
            hotCornerDwellTask?.cancel()
            hotCornerDwellTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(160))
                guard let self, !Task.isCancelled, self.isPointerInHotCorner else { return }
                self.toggle()
            }
        } else {
            isPointerInHotCorner = false
            hotCornerDwellTask?.cancel()
            hotCornerDwellTask = nil
        }
    }

    // MARK: - Panel Construction

    private func ensurePanel(for screen: NSScreen) -> LaunchpadPanel {
        if let existing = panel {
            if !hasInstalledContent {
                installRootView(into: existing)
            }
            return existing
        }

        let newPanel = LaunchpadPanel(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        newPanel.isFloatingPanel = true
        newPanel.becomesKeyOnlyIfNeeded = false
        newPanel.hidesOnDeactivate = false
        newPanel.isOpaque = false
        newPanel.backgroundColor = .clear
        newPanel.hasShadow = false
        newPanel.isMovable = false
        newPanel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 5)
        newPanel.collectionBehavior = [
            .transient,
            .moveToActiveSpace,
            .fullScreenAuxiliary,
            .ignoresCycle
        ]
        installRootView(into: newPanel)
        self.panel = newPanel
        return newPanel
    }

    private func installRootView(into targetPanel: LaunchpadPanel) {
        let hostingView = FirstMouseHostingView(
            rootView: LaunchpadRootView(
                manager: LaunchpadManager.shared,
                windowController: self
            )
        )
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        targetPanel.contentView = hostingView
        hasInstalledContent = true
    }

    private static func screenUnderPointer() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
    }

    // MARK: - Local Event Monitors (Keyboard, Trackpad Swipe & Pinch)

    private func installLocalMonitors() {
        removeLocalMonitors()

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isPresented else { return event }
            return self.handleKeyDown(event) ? nil : event
        }

        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, self.isPresented else { return event }
            return self.handleScrollWheel(event) ? nil : event
        }

        magnifyMonitor = NSEvent.addLocalMonitorForEvents(matching: .magnify) { [weak self] event in
            guard let self, self.isPresented else { return event }
            self.handleMagnify(event)
            return event
        }

        mouseResignObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let activatedBundleId = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            Task { @MainActor in
                guard let self, self.isPresented else { return }
                guard Date().timeIntervalSince(self.lastShownAt) > 0.15 else { return }
                if activatedBundleId != Bundle.main.bundleIdentifier {
                    self.dismiss(restorePreviousApp: false)
                }
            }
        }
    }

    private func removeLocalMonitors() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
            self.scrollMonitor = nil
        }
        if let magnifyMonitor {
            NSEvent.removeMonitor(magnifyMonitor)
            self.magnifyMonitor = nil
        }
        if let mouseResignObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(mouseResignObserver)
            self.mouseResignObserver = nil
        }
    }

    /// Returns `true` when the key event was consumed.
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        let manager = LaunchpadManager.shared
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Allow Cmd+Q to pass through to app quit handler
        if flags.contains(.command) && event.charactersIgnoringModifiers?.lowercased() == "q" {
            return false
        }

        // Escape key
        if event.keyCode == 53 {
            if manager.isEditingMode {
                manager.isEditingMode = false
            } else if manager.activeFolderId != nil {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    manager.activeFolderId = nil
                }
            } else if !manager.searchQuery.isEmpty {
                manager.searchQuery = ""
            } else {
                dismiss(restorePreviousApp: true)
            }
            return true
        }

        // Ignore page arrows while an NSTextView (search/folder rename) has text or is editing folder name
        let isTextEditing: Bool
        if let firstResponder = panel?.firstResponder as? NSTextView {
            isTextEditing = firstResponder.string.isEmpty == false || manager.activeFolderId != nil
        } else {
            isTextEditing = false
        }

        // Return / Keypad Enter -> launch top search match when searching
        if (event.keyCode == 36 || event.keyCode == 76) && !manager.searchQuery.isEmpty {
            if let first = manager.searchResults.first {
                manager.launchApp(first)
                return true
            }
        }

        // Left / PageUp -> previous page
        if (event.keyCode == 123 || event.keyCode == 116) && manager.activeFolderId == nil && manager.searchQuery.isEmpty && !isTextEditing {
            stepPage(by: -1)
            return true
        }

        // Right / PageDown -> next page
        if (event.keyCode == 124 || event.keyCode == 121) && manager.activeFolderId == nil && manager.searchQuery.isEmpty && !isTextEditing {
            stepPage(by: 1)
            return true
        }

        return false
    }

    private func handleScrollWheel(_ event: NSEvent) -> Bool {
        let manager = LaunchpadManager.shared
        guard manager.activeFolderId == nil, manager.searchQuery.isEmpty else {
            return false
        }
        guard manager.pages.count > 1 else {
            return false
        }

        // Ignore post-lift momentum events so one flick moves cleanly by at most 1 page
        if !event.momentumPhase.isEmpty {
            return true
        }

        let dx = event.scrollingDeltaX
        let dy = event.scrollingDeltaY

        if !event.phase.isEmpty {
            // Trackpad 2-finger continuous gesture
            switch event.phase {
            case .began, .mayBegin:
                isTrackingHorizontalSwipe = abs(dx) >= abs(dy)
                accumulatedSwipeX = 0
                if isTrackingHorizontalSwipe {
                    liveSwipeOffset = 0
                }
            case .changed:
                if !isTrackingHorizontalSwipe && abs(dx) > abs(dy) && abs(dx) > 1.5 {
                    isTrackingHorizontalSwipe = true
                }
                guard isTrackingHorizontalSwipe else { return false }
                accumulatedSwipeX += dx * 1.15
                // Apply rubber-band resistance at first and last page edges
                let atLeadingEdge = manager.currentPageIndex == 0 && accumulatedSwipeX > 0
                let atTrailingEdge = manager.currentPageIndex >= manager.pages.count - 1 && accumulatedSwipeX < 0
                liveSwipeOffset = (atLeadingEdge || atTrailingEdge) ? accumulatedSwipeX * 0.25 : accumulatedSwipeX
                return true
            case .ended, .cancelled:
                guard isTrackingHorizontalSwipe else { return false }
                let pageWidth = panel?.frame.width ?? 1200
                let threshold = min(140, pageWidth * 0.12)
                var targetPage = manager.currentPageIndex
                if accumulatedSwipeX < -threshold {
                    targetPage += 1
                } else if accumulatedSwipeX > threshold {
                    targetPage -= 1
                }
                let clamped = max(0, min(targetPage, manager.pages.count - 1))
                withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                    manager.currentPageIndex = clamped
                    liveSwipeOffset = 0
                }
                isTrackingHorizontalSwipe = false
                accumulatedSwipeX = 0
                return true
            default:
                break
            }
            return false
        }

        // Non-phase mouse wheel / stepped scroll: allow horizontal or vertical wheel to step 1 page with cooldown
        let now = Date()
        guard now.timeIntervalSince(lastWheelStepTime) > 0.32 else { return true }
        let primaryDelta = abs(dx) > abs(dy) ? dx : dy
        guard abs(primaryDelta) >= 2.0 else { return false }

        lastWheelStepTime = now
        if primaryDelta < 0 {
            stepPage(by: 1)
        } else {
            stepPage(by: -1)
        }
        return true
    }

    private func handleMagnify(_ event: NSEvent) {
        if event.phase == .began {
            accumulatedMagnification = 0
        }
        accumulatedMagnification += event.magnification
        if accumulatedMagnification <= -0.18 {
            accumulatedMagnification = 0
            dismiss(restorePreviousApp: true)
        }
    }

    func stepPage(by delta: Int) {
        let manager = LaunchpadManager.shared
        guard !manager.pages.isEmpty else { return }
        let target = max(0, min(manager.currentPageIndex + delta, manager.pages.count - 1))
        guard target != manager.currentPageIndex else { return }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            manager.currentPageIndex = target
        } else {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                manager.currentPageIndex = target
            }
        }
    }
}

