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
    @Published private(set) var currentScreenWallpaperURL: URL?
    @Published private(set) var focusSearchToken: Int = 0
    @Published private(set) var topNotchSafeInset: CGFloat = 58

    private var panel: LaunchpadPanel?
    private var hasInstalledContent = false
    private weak var previousFrontmostApp: NSRunningApplication?
    private var defaultsCancellable: AnyCancellable?
    private var presentationGeneration: Int = 0
    private var lastShownAt: Date = .distantPast
    private var suppressEscapeUntil: Date = .distantPast

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
    private var enableCancellable: AnyCancellable?
    private var replaceGestureCancellable: AnyCancellable?

    private static let systemLauncherBundleIds: Set<String> = [
        "com.apple.campo",
        "com.apple.Spotlight",
        "com.apple.apps.launcher"
    ]

    private override init() {
        super.init()
        defaultsCancellable = Defaults.publisher(.launchpadHotCorner)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.configureHotCornerMonitor()
            }
        enableCancellable = Defaults.publisher(.enableLaunchpad)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.configureHotCornerMonitor()
                self?.configureSystemLaunchpadInterceptor()
            }
        replaceGestureCancellable = Defaults.publisher(.launchpadReplaceSystemGesture)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.configureHotCornerMonitor()
                self?.configureSystemLaunchpadInterceptor()
            }
    }

    // MARK: - Public Presentation API

    func prewarmIfNeeded() {
        guard Defaults[.enableLaunchpad] else { return }
        LaunchpadManager.shared.prepareForPresentation()
        if let screen = Self.screenUnderPointer() ?? NSScreen.main {
            updateInsets(for: screen)
            let wallpaperURL = NSWorkspace.shared.desktopImageURL(for: screen)
            currentScreenWallpaperURL = wallpaperURL
            if let wallpaperURL {
                Task.detached(priority: .utility) {
                    _ = LaunchpadBlurredWallpaperCache.shared.loadBlurredWallpaper(from: wallpaperURL)
                }
            }
            if panel == nil {
                _ = ensurePanel(for: screen)
            }
        }
    }

    func suppressEscape(for duration: TimeInterval) {
        let target = Date().addingTimeInterval(duration)
        if target > suppressEscapeUntil {
            suppressEscapeUntil = target
        }
    }

    private func updateInsets(for screen: NSScreen) {
        let menuBarInset = max(0, screen.frame.maxY - screen.visibleFrame.maxY)
        let notchTop = max(screen.safeAreaInsets.top, menuBarInset)
        topNotchSafeInset = notchTop > 26 ? max(58, notchTop + 22) : 44
    }

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
           let bundleId = active.bundleIdentifier,
           bundleId != Bundle.main.bundleIdentifier,
           !Self.systemLauncherBundleIds.contains(bundleId) {
            previousFrontmostApp = active
        }

        let targetScreen = Self.screenUnderPointer() ?? NSScreen.main
        guard let screen = targetScreen else { return }

        updateInsets(for: screen)
        currentScreenWallpaperURL = NSWorkspace.shared.desktopImageURL(for: screen)
        LaunchpadManager.shared.prepareForPresentation()

        let panel = ensurePanel(for: screen)
        panel.setFrame(screen.frame, display: true)
        panel.alphaValue = 0

        presentationGeneration += 1
        lastShownAt = Date()
        isPresented = true
        liveSwipeOffset = 0
        installLocalMonitors()

        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        LaunchpadSystemInterceptor.shared.dismissResidualSpotlightAppsIfVisible(keepLaunchpadOpen: true)

        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.alphaValue = 1
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.14
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        }
    }

    func bringPanelToFrontIfPresented() {
        guard isPresented, let panel else { return }
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
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

        let appToRestore = restorePreviousApp ? self.previousFrontmostApp : nil
        // Dismiss any hidden/lingering macOS native Applications window BEFORE Launchpad fades out
        // so it never flashes into view underneath as our panel disappears.
        LaunchpadSystemInterceptor.shared.dismissResidualSpotlightAppsIfVisible(
            keepLaunchpadOpen: false,
            restoreApp: appToRestore
        )

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

            let finalAppToRestore = restorePreviousApp ? self.previousFrontmostApp : nil
            self.previousFrontmostApp = nil

            let dismissedNative = LaunchpadSystemInterceptor.shared.dismissResidualSpotlightAppsIfVisible(
                keepLaunchpadOpen: false,
                restoreApp: finalAppToRestore
            )
            if !dismissedNative,
               let finalAppToRestore,
               !finalAppToRestore.isTerminated {
                finalAppToRestore.activate()
            }
            completion?()
        }

        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            finishDismiss()
        } else {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.13
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

        guard Defaults[.enableLaunchpad] else { return }
        let hasActiveCorner = Defaults[.launchpadHotCorner] != .none
            || (Defaults[.launchpadReplaceSystemGesture] && !Self.dockLaunchpadHotCorners().isEmpty)
        guard hasActiveCorner else { return }

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
        guard Defaults[.enableLaunchpad] else { return }
        guard !NotchPulseLockMonitor.isScreenActuallyLocked() else { return }
        guard NSEvent.pressedMouseButtons == 0 else { return }

        var activeCorners: Set<LaunchpadHotCorner> = []
        let configured = Defaults[.launchpadHotCorner]
        if configured != .none {
            activeCorners.insert(configured)
        }
        let dockCorners = Defaults[.launchpadReplaceSystemGesture] ? Self.dockLaunchpadHotCorners() : []
        activeCorners.formUnion(dockCorners)
        guard !activeCorners.isEmpty else { return }

        let mouse = NSEvent.mouseLocation
        guard let screen = Self.screenUnderPointer() else { return }
        let frame = screen.frame
        let threshold: CGFloat = 7.0

        var inCorner = false
        for corner in activeCorners {
            switch corner {
            case .none:
                break
            case .topLeft:
                if mouse.x <= frame.minX + threshold && mouse.y >= frame.maxY - threshold { inCorner = true }
            case .topRight:
                if mouse.x >= frame.maxX - threshold && mouse.y >= frame.maxY - threshold { inCorner = true }
            case .bottomLeft:
                if mouse.x <= frame.minX + threshold && mouse.y <= frame.minY + threshold { inCorner = true }
            case .bottomRight:
                if mouse.x >= frame.maxX - threshold && mouse.y <= frame.minY + threshold { inCorner = true }
            }
        }

        if inCorner {
            guard !isPointerInHotCorner else { return }
            isPointerInHotCorner = true
            hotCornerDwellTask?.cancel()
            // Respond faster when intercepting a macOS Dock Launchpad Hot Corner so NotchPulse
            // presents cleanly before Dock dispatches `.launchAppsBrowsing`.
            let dwellMs = dockCorners.isEmpty ? 140 : 85
            hotCornerDwellTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(dwellMs))
                guard let self, !Task.isCancelled, self.isPointerInHotCorner else { return }
                if !dockCorners.isEmpty {
                    LaunchpadSystemInterceptor.shared.noteInterceptedSystemTrigger()
                }
                self.toggle()
            }
        } else {
            isPointerInHotCorner = false
            hotCornerDwellTask?.cancel()
            hotCornerDwellTask = nil
        }
    }

    private static func dockLaunchpadHotCorners() -> Set<LaunchpadHotCorner> {
        let domain = "com.apple.dock" as CFString
        let mapping: [(String, LaunchpadHotCorner)] = [
            ("wvous-tl-corner", .topLeft),
            ("wvous-tr-corner", .topRight),
            ("wvous-bl-corner", .bottomLeft),
            ("wvous-br-corner", .bottomRight)
        ]
        var result: Set<LaunchpadHotCorner> = []
        for (key, corner) in mapping {
            if let num = CFPreferencesCopyValue(key as CFString, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? NSNumber {
                // Dock hot corner code 11 = Launchpad / Applications (15 = Quick Note, 11 = Launchpad)
                if num.intValue == 11 {
                    result.insert(corner)
                }
            }
        }
        return result
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
        newPanel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 20)
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
                guard Date().timeIntervalSince(self.lastShownAt) > 0.25 else { return }
                if let activatedBundleId,
                   activatedBundleId != Bundle.main.bundleIdentifier,
                   !Self.systemLauncherBundleIds.contains(activatedBundleId) {
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
            if Date() < suppressEscapeUntil {
                return true
            }
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

        // Ignore page arrows while an NSTextView (search/folder rename) is focused
        let isTextEditing: Bool
        if let firstResponder = panel?.firstResponder as? NSTextView {
            isTextEditing = panel?.windowNumber != nil && (firstResponder.string.isEmpty == false || manager.activeFolderId != nil || manager.searchQuery.isEmpty == false)
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

        // Type-to-search: start filtering immediately when user types any printable key anywhere
        if !(panel?.firstResponder is NSTextView),
           manager.activeFolderId == nil,
           !flags.contains(.command),
           !flags.contains(.control),
           !flags.contains(.option),
           let chars = event.characters,
           !chars.isEmpty,
           let scalar = chars.unicodeScalars.first,
           !CharacterSet.controlCharacters.contains(scalar),
           !CharacterSet.newlines.contains(scalar) {
            manager.searchQuery.append(chars)
            focusSearchToken += 1
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
                applyHorizontalSwipe(rawDeltaX: accumulatedSwipeX)
                return true
            case .ended, .cancelled:
                guard isTrackingHorizontalSwipe else { return false }
                let pageWidth = panel?.frame.width ?? 1200
                commitHorizontalSwipe(
                    deltaX: accumulatedSwipeX,
                    predictedDeltaX: accumulatedSwipeX,
                    pageWidth: pageWidth
                )
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
        // Both pinch-in and spread-out trackpad gestures cleanly dismiss Launchpad Home
        if accumulatedMagnification <= -0.16 || accumulatedMagnification >= 0.14 {
            accumulatedMagnification = 0
            dismiss(restorePreviousApp: true)
        }
    }

    func applyHorizontalSwipe(rawDeltaX: CGFloat) {
        let manager = LaunchpadManager.shared
        let atLeadingEdge = manager.currentPageIndex == 0 && rawDeltaX > 0
        let atTrailingEdge = manager.currentPageIndex >= manager.pages.count - 1 && rawDeltaX < 0
        liveSwipeOffset = (atLeadingEdge || atTrailingEdge) ? rawDeltaX * 0.28 : rawDeltaX
    }

    func commitHorizontalSwipe(deltaX: CGFloat, predictedDeltaX: CGFloat, pageWidth: CGFloat) {
        let manager = LaunchpadManager.shared
        let effectiveWidth = max(1, pageWidth)
        let threshold = min(140, effectiveWidth * 0.12)
        let velocityThreshold = effectiveWidth * 0.30

        var targetPage = manager.currentPageIndex
        if deltaX < -threshold || predictedDeltaX < -velocityThreshold {
            targetPage += 1
        } else if deltaX > threshold || predictedDeltaX > velocityThreshold {
            targetPage -= 1
        }
        let clamped = max(0, min(targetPage, max(0, manager.pages.count - 1)))

        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            manager.currentPageIndex = clamped
            liveSwipeOffset = 0
        } else {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                manager.currentPageIndex = clamped
                liveSwipeOffset = 0
            }
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

    // MARK: - System Launchpad & Trackpad Pinch Interceptor

    func configureSystemLaunchpadInterceptor() {
        LaunchpadSystemInterceptor.shared.configure()
    }
}

