import AppKit
import ApplicationServices
import Combine
import Defaults
import ScreenCaptureKit
import SwiftUI

// CoreDock private API from ApplicationServices
@_silgen_name("CoreDockGetAutoHideEnabled")
private func CoreDockGetAutoHideEnabled() -> Bool

private final class DockRevealContext {
    let pid: pid_t
    let revealPoint: CGPoint
    var tap: CFMachPort?

    init(pid: pid_t, revealPoint: CGPoint) {
        self.pid = pid
        self.revealPoint = revealPoint
    }
}

// MARK: - Dock Position Enum

enum DockScreenPosition {
    case bottom
    case left
    case right
    case hidden
}

// MARK: - Window Preview Item Model

struct DockWindowItem: Identifiable, Hashable {
    let id: CGWindowID
    let title: String
    let frame: CGRect
    let thumbnail: NSImage?
    let axWindow: AXUIElement?
    let isMinimized: Bool

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: DockWindowItem, rhs: DockWindowItem) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Dock Preview State

@MainActor
final class DockPreviewViewModel: ObservableObject {
    @Published var appName: String = ""
    @Published var appIcon: NSImage? = nil
    @Published var windows: [DockWindowItem] = []
    @Published var hoveredWindowId: CGWindowID? = nil
    @Published var isLoading: Bool = false
    @Published var dockPosition: DockScreenPosition = .bottom

    var onSelectWindow: ((DockWindowItem) -> Void)?
    var onCloseWindow: ((DockWindowItem) -> Void)?
}

// MARK: - Dock Preview Manager

@MainActor
final class DockPreviewManager: ObservableObject {
    static let shared = DockPreviewManager()

    private var mouseMonitor: Any?
    private var clickMonitor: Any?
    private var localClickMonitor: Any?
    private var hoverTimer: Timer?
    private var dismissTimer: Timer?
    private var lastHoveredTitle: String? = nil
    private var lastHoveredItemFrame: CGRect = .zero
    private var isPanelVisible: Bool = false
    private var currentApp: NSRunningApplication?

    private var previewPanel: NSPanel?
    private var hostingView: NSHostingView<DockPreviewView>?
    let viewModel = DockPreviewViewModel()

    private var thumbnailCache: [CGWindowID: (image: NSImage, date: Date)] = [:]
    private var isConfigured = false

    private var dockRevealTap: (tap: CFMachPort, source: CFRunLoopSource, context: Unmanaged<DockRevealContext>)?
    private var lastKeepAlivePulse: Date = .distantPast
    private var cachedDockOrientation: (pos: DockScreenPosition, time: TimeInterval)?
    private var edgeRecheckWork: DispatchWorkItem?
    private var isContextMenuActive = false
    private var lastRightClickTime: Date = .distantPast

    private init() {
        setupCallbacks()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isConfigured, self.mouseMonitor == nil else { return }
                self.startMouseMonitoring(resetRetry: true)
            }
        }
    }

    private func setupCallbacks() {
        viewModel.onSelectWindow = { [weak self] item in
            self?.activateWindow(item)
        }
        viewModel.onCloseWindow = { [weak self] item in
            self?.closeWindow(item)
        }
    }

    func configure() {
        guard Defaults[.enableDockPreview] else {
            teardown()
            return
        }
        isConfigured = true
        startMouseMonitoring()

        // Pre-warm ScreenCaptureKit in background so first preview hover has 0ms cold-start latency
        Task.detached(priority: .background) {
            _ = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        }
    }

    func teardown() {
        stopMouseMonitoring()
        monitorRetryCount = 0
        hoverTimer?.invalidate()
        hoverTimer = nil
        dismissTimer?.invalidate()
        dismissTimer = nil
        trailingMoveWork?.cancel()
        trailingMoveWork = nil
        edgeRecheckWork?.cancel()
        edgeRecheckWork = nil
        cachedDockBar = nil
        dismissImmediately()
        isConfigured = false
    }

    // MARK: - Mouse Event Monitoring

    private var monitorRetryCount = 0
    private let maxMonitorRetries = 4

    private func startMouseMonitoring(resetRetry: Bool = false) {
        if resetRetry {
            monitorRetryCount = 0
        }
        if mouseMonitor == nil {
            mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.throttledMouseMove()
                }
            }
            if mouseMonitor == nil && monitorRetryCount < maxMonitorRetries {
                monitorRetryCount += 1
                // Retry only a limited number of times (max 4 attempts: ~12s total), then stop to save CPU/battery
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                    guard let self, self.isConfigured, self.mouseMonitor == nil else { return }
                    self.startMouseMonitoring()
                }
            }
        }

        if clickMonitor == nil {
            clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [
                .rightMouseDown,
                .leftMouseDown,
                .otherMouseDown
            ]) { [weak self] event in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }

                    // Right click or Control+Click ANYWHERE (on dock icon, desktop, etc.):
                    // 1. Mark context menu as active to block all upcoming preview triggers
                    // 2. IMMEDIATELY dismiss preview & cancel timers with 0 delay so macOS Dock context menu opens clean!
                    if event.type == .rightMouseDown || (event.type == .leftMouseDown && event.modifierFlags.contains(.control)) {
                        self.isContextMenuActive = true
                        self.lastRightClickTime = Date()
                        self.dismissImmediately()
                        return
                    }

                    // Any left click or other click: reset context menu suppression
                    self.isContextMenuActive = false

                    // Left click outside the preview panel: immediately dismiss
                    let mouseLoc = NSEvent.mouseLocation
                    if let panel = self.previewPanel, !panel.frame.contains(mouseLoc) {
                        self.dismissImmediately()
                    }
                }
            }
        }

        if localClickMonitor == nil {
            localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak self] event in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    if event.type == .rightMouseDown || (event.type == .leftMouseDown && event.modifierFlags.contains(.control)) {
                        self.isContextMenuActive = true
                        self.lastRightClickTime = Date()
                        self.dismissImmediately()
                    } else if event.type == .leftMouseDown {
                        self.isContextMenuActive = false
                    }
                }
                return event
            }
        }
    }

    private func stopMouseMonitoring() {
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
        if let monitor = localClickMonitor {
            NSEvent.removeMonitor(monitor)
            localClickMonitor = nil
        }
    }

    // MARK: - Hover Detection

    private var lastMouseProcessTime: TimeInterval = 0
    private var trailingMoveWork: DispatchWorkItem?

    /// Throttles the high-frequency global mouseMoved stream (~30Hz) with a trailing call
    /// so the final resting mouse position is always evaluated.
    private func throttledMouseMove() {
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastMouseProcessTime >= 0.033 {
            lastMouseProcessTime = now
            trailingMoveWork?.cancel()
            trailingMoveWork = nil
            handleGlobalMouseMove()
        } else if trailingMoveWork == nil {
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.trailingMoveWork = nil
                self.lastMouseProcessTime = ProcessInfo.processInfo.systemUptime
                self.handleGlobalMouseMove()
            }
            trailingMoveWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04, execute: work)
        }
    }

    private func handleGlobalMouseMove() {
        guard Defaults[.enableDockPreview] else { return }

        let mouseLoc = NSEvent.mouseLocation

        // 0. Ultra-fast screen-interior guard:
        // When preview panel is NOT visible and mouse is comfortably inside the screen
        // (i.e. user is typing, reading, or moving around the middle of the screen),
        // exit immediately in < 0.001ms with zero allocations, zero IPC, and zero preference reads!
        if !isPanelVisible {
            let primaryScreen = NSScreen.screens.first ?? NSScreen.main
            let screen = NSScreen.screens.first(where: { NSPointInRect(mouseLoc, $0.frame) }) ?? primaryScreen
            if let screen {
                let margin: CGFloat = 110.0
                let nearAnyDockBorder = mouseLoc.x <= screen.frame.minX + margin
                    || mouseLoc.x >= screen.frame.maxX - margin
                    || mouseLoc.y <= screen.frame.minY + margin
                if !nearAnyDockBorder {
                    dismissImmediately()
                    return
                }
            }
        }

        let (dockPos, dockScreen) = detectDockPosition()

        guard dockPos != .hidden, let screen = dockScreen else {
            dismissImmediately()
            return
        }

        // Context Menu Guard: If the user right-clicked to view options/context menu on Dock,
        // or a native Dock menu is actively open on screen, DO NOT show or keep previews alive!
        if isContextMenuActive {
            if isDockContextMenuOpen() || Date().timeIntervalSince(lastRightClickTime) < 1.2 {
                dismissImmediately()
                return
            } else {
                isContextMenuActive = false
            }
        } else if isDockContextMenuOpen() {
            isContextMenuActive = true
            dismissImmediately()
            return
        }

        // 1. If mouse is inside currently visible preview panel, keep it alive
        if isPanelVisible, let panel = previewPanel, panel.frame.contains(mouseLoc) {
            dismissTimer?.invalidate()
            dismissTimer = nil
            keepDockRevealed(screen: screen, dockPos: dockPos, mouseLoc: mouseLoc)
            return
        }

        // 2. Safe Corridor: If preview panel is currently open, allow smooth traversal
        // between the Dock bar and the preview panel without triggering auto-hide or premature dismissal.
        if isPanelVisible, let panel = previewPanel {
            let dockBar = getDockBarGeometry(screen: screen)
            let corridor: CGRect

            switch dockPos {
            case .right:
                let leftEdge = panel.frame.minX - 16
                let rightEdge = screen.frame.maxX
                let topEdge = max(panel.frame.maxY, lastHoveredItemFrame.maxY, dockBar?.maxY ?? screen.frame.maxY) + 24
                let bottomEdge = min(panel.frame.minY, lastHoveredItemFrame.minY, dockBar?.minY ?? screen.frame.minY) - 24
                corridor = CGRect(x: leftEdge, y: bottomEdge, width: rightEdge - leftEdge, height: topEdge - bottomEdge)

            case .left:
                let leftEdge = screen.frame.minX
                let rightEdge = panel.frame.maxX + 16
                let topEdge = max(panel.frame.maxY, lastHoveredItemFrame.maxY, dockBar?.maxY ?? screen.frame.maxY) + 24
                let bottomEdge = min(panel.frame.minY, lastHoveredItemFrame.minY, dockBar?.minY ?? screen.frame.minY) - 24
                corridor = CGRect(x: leftEdge, y: bottomEdge, width: rightEdge - leftEdge, height: topEdge - bottomEdge)

            case .bottom, .hidden:
                let leftEdge = min(panel.frame.minX, lastHoveredItemFrame.minX, dockBar?.minX ?? screen.frame.minX) - 24
                let rightEdge = max(panel.frame.maxX, lastHoveredItemFrame.maxX, dockBar?.maxX ?? screen.frame.maxX) + 24
                let bottomEdge = screen.frame.minY
                let topEdge = panel.frame.maxY + 16
                corridor = CGRect(x: leftEdge, y: bottomEdge, width: rightEdge - leftEdge, height: topEdge - bottomEdge)
            }

            if corridor.contains(mouseLoc) {
                keepDockRevealed(screen: screen, dockPos: dockPos, mouseLoc: mouseLoc)

                // Inside the Safe Corridor / Dock Bar region:
                // Check if the user is hovering over another Dock app icon to switch previews instantly!
                if let dockApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first {
                    let dockAX = AXUIElementCreateApplication(dockApp.processIdentifier)
                    var elementRef: AXUIElement?
                    let primaryScreen = NSScreen.screens.first ?? screen
                    let quartzX = mouseLoc.x
                    let quartzY = primaryScreen.frame.maxY - mouseLoc.y

                    let status = AXUIElementCopyElementAtPosition(dockAX, Float(quartzX), Float(quartzY), &elementRef)
                    if status == .success, let element = elementRef,
                       let dockItem = extractDockItemInfo(from: element, primaryScreen: primaryScreen) {
                        dismissTimer?.invalidate()
                        dismissTimer = nil

                        let title = dockItem.title
                        if title != lastHoveredTitle {
                            lastHoveredTitle = title
                            lastHoveredItemFrame = dockItem.frame
                            hoverTimer?.invalidate()
                            showPreview(forDockItem: dockItem, dockPos: dockPos, screen: screen)
                        }
                        return
                    }
                }

                // If moving across the gap between Dock and preview panel:
                // Provide a comfortable ~400ms grace period so movement feels fluid and natural
                if dismissTimer == nil {
                    dismissTimer = Timer.scheduledTimer(withTimeInterval: 0.40, repeats: false) { [weak self] _ in
                        Task { @MainActor [weak self] in
                            self?.dismissImmediately()
                        }
                    }
                }
                return
            }
        }

        // 3. Fast screen edge bounds check before querying Accessibility for initial hover
        guard isMouseNearDockEdge(mouseLoc: mouseLoc, position: dockPos, screen: screen) else {
            dismissImmediately()
            return
        }

        // 4. Query the Dock process directly using AXUIElementCreateApplication
        guard let dockApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            dismissImmediately()
            return
        }

        let dockAX = AXUIElementCreateApplication(dockApp.processIdentifier)
        var elementRef: AXUIElement?

        let primaryScreen = NSScreen.screens.first ?? screen
        let quartzX = mouseLoc.x
        let quartzY = primaryScreen.frame.maxY - mouseLoc.y

        let status = AXUIElementCopyElementAtPosition(dockAX, Float(quartzX), Float(quartzY), &elementRef)

        if status == .success, let element = elementRef,
           let dockItem = extractDockItemInfo(from: element, primaryScreen: primaryScreen) {
            // Mouse is actively hovering over a valid Dock item!
            dismissTimer?.invalidate()
            dismissTimer = nil

            let title = dockItem.title
            if title == lastHoveredTitle && isPanelVisible {
                return
            }

            if title != lastHoveredTitle {
                lastHoveredTitle = title
                lastHoveredItemFrame = dockItem.frame
                hoverTimer?.invalidate()

                if isPanelVisible {
                    // Switch immediately to adjacent app preview without lag!
                    showPreview(forDockItem: dockItem, dockPos: dockPos, screen: screen)
                } else {
                    let delay = Defaults[.dockPreviewHoverDelay]
                    hoverTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                        Task { @MainActor [weak self] in
                            guard let self = self else { return }
                            self.showPreview(forDockItem: dockItem, dockPos: dockPos, screen: screen)
                        }
                    }
                }
            }
            return
        }

        // 5. Mouse is near the Dock edge, but no icon under the cursor yet.
        // This happens when:
        // a. Auto-hidden Dock is sliding out (~150ms animation), cursor is stationary at screen edge.
        // b. Cursor is traversing between icon gaps or magnification is actively resizing.
        // We schedule a one-shot re-check after 120ms so we automatically catch the icon once revealed
        // without requiring the user to wiggle or move their mouse again!
        if edgeRecheckWork == nil {
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.edgeRecheckWork = nil
                self.handleGlobalMouseMove()
            }
            edgeRecheckWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
        }

        if isPanelVisible {
            if dismissTimer == nil {
                dismissTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.dismissImmediately()
                    }
                }
            }
            return
        }

        // If hoverTimer is actively counting down, keep it alive while still near the Dock edge!
        if hoverTimer != nil {
            return
        }

        lastHoveredTitle = nil
        lastHoveredItemFrame = .zero
    }

    private func isMouseNearDockEdge(mouseLoc: NSPoint, position: DockScreenPosition, screen: NSScreen) -> Bool {
        let margin: CGFloat = 110.0
        switch position {
        case .bottom:
            return mouseLoc.y <= screen.frame.minY + margin
        case .left:
            return mouseLoc.x <= screen.frame.minX + margin
        case .right:
            return mouseLoc.x >= screen.frame.maxX - margin
        case .hidden:
            return false
        }
    }

    private func dismissImmediately() {
        edgeRecheckWork?.cancel()
        edgeRecheckWork = nil
        hoverTimer?.invalidate()
        hoverTimer = nil
        dismissTimer?.invalidate()
        dismissTimer = nil
        lastHoveredTitle = nil
        lastHoveredItemFrame = .zero
        releaseDockReveal()

        guard isPanelVisible else { return }
        hidePreviewPanel(animated: false)
    }

    // MARK: - Dock Context Menu Detection

    func isDockContextMenuOpen() -> Bool {
        guard let dockApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return false }
        let pid = dockApp.processIdentifier

        // 1. Fast check CGWindowList for on-screen Dock popup/menu windows (layer > 20)
        let cgList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for win in cgList {
            if (win[kCGWindowOwnerPID as String] as? pid_t) == pid {
                let layer = win[kCGWindowLayer as String] as? Int ?? 0
                // Normal Dock bar is layer 20. Context menus, submenus, and popups are layer > 20 (typically 100+)
                if layer > 20 {
                    return true
                }
            }
        }

        // 2. Check Accessibility children of Dock
        let dockAX = AXUIElementCreateApplication(pid)
        var childrenRef: AnyObject?
        if AXUIElementCopyAttributeValue(dockAX, kAXChildrenAttribute as CFString, &childrenRef) == .success,
           let children = childrenRef as? [AXUIElement] {
            for child in children {
                var roleRef: AnyObject?
                AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleRef)
                if let role = roleRef as? String, role == "AXMenu" || role == "AXMenuItem" || role == "AXPopover" {
                    return true
                }
            }
        }

        return false
    }

    // MARK: - Dock Reveal & Auto-Hide Control

    func isMouseInsideDock(mouseLoc: NSPoint, screen: NSScreen, dockPos: DockScreenPosition) -> Bool {
        if let dockBar = getDockBarGeometry(screen: screen) {
            return dockBar.insetBy(dx: -8, dy: -8).contains(mouseLoc)
        }
        return isMouseNearDockEdge(mouseLoc: mouseLoc, position: dockPos, screen: screen)
    }

    private static let mouseExitedEventType = CGEventType(rawValue: UInt32(NSEvent.EventType.mouseExited.rawValue))!

    private static func postMouseEvent(_ type: CGEventType, at point: CGPoint, toDock pid: pid_t) {
        guard let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left) else { return }
        event.type = type
        event.postToPid(pid)
    }

    private static let dockEventTapCallback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
        let ctx = Unmanaged<DockRevealContext>.fromOpaque(refcon).takeUnretainedValue()
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = ctx.tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }
        if type.rawValue == UInt32(NSEvent.EventType.mouseExited.rawValue) {
            // ONLY post mouseMoved if mouse is outside the Dock (i.e. mouse genuinely left Dock towards preview)
            // If the user's mouse is still near the Dock edge / on the Dock, do NOT intercept or inject!
            let mouseLoc = NSEvent.mouseLocation
            let (pos, dScreen) = DockPreviewManager.shared.detectDockPosition()
            let screen = dScreen ?? NSScreen.main ?? NSScreen.screens[0]
            if !DockPreviewManager.shared.isMouseInsideDock(mouseLoc: mouseLoc, screen: screen, dockPos: pos) {
                DockPreviewManager.postMouseEvent(.mouseMoved, at: ctx.revealPoint, toDock: ctx.pid)
            }
        }
        return Unmanaged.passUnretained(event)
    }

    private func keepDockRevealed(screen: NSScreen, dockPos: DockScreenPosition, mouseLoc: NSPoint) {
        guard Defaults[.dockPreviewKeepDockVisible] else { return }
        guard CoreDockGetAutoHideEnabled() else { return }

        guard let dockApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return }
        let pid = dockApp.processIdentifier

        // CRITICAL ANTI-JITTER RULE:
        // When mouse is inside the Dock bar, the system natively keeps the Dock visible.
        // NEVER post fake mouse events while user is hovering Dock icons, or the Dock will jitter!
        let insideDock = isMouseInsideDock(mouseLoc: mouseLoc, screen: screen, dockPos: dockPos)

        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let screenQuartz = CGRect(x: screen.frame.minX, y: primaryHeight - screen.frame.maxY, width: screen.frame.width, height: screen.frame.height)
        let dockBar = getDockBarGeometry(screen: screen)
        let dockBarQuartz = dockBar.map { CGRect(x: $0.minX, y: primaryHeight - $0.maxY, width: $0.width, height: $0.height) }

        // Compute revealPoint in the screen margin outside the app icons
        let revealPoint: CGPoint
        switch dockPos {
        case .right:
            let y = dockBarQuartz != nil ? min(max((screenQuartz.minY + dockBarQuartz!.minY) / 2, screenQuartz.minY + 32), dockBarQuartz!.minY) : screenQuartz.midY
            revealPoint = CGPoint(x: screenQuartz.maxX - 1, y: y)
        case .left:
            let y = dockBarQuartz != nil ? min(max((screenQuartz.minY + dockBarQuartz!.minY) / 2, screenQuartz.minY + 32), dockBarQuartz!.minY) : screenQuartz.midY
            revealPoint = CGPoint(x: screenQuartz.minX + 1, y: y)
        case .bottom, .hidden:
            let x = dockBarQuartz != nil ? min(max((screenQuartz.minX + dockBarQuartz!.minX) / 2, screenQuartz.minX + 32), dockBarQuartz!.minX) : screenQuartz.midX
            revealPoint = CGPoint(x: x, y: screenQuartz.maxY - 1)
        }

        if let current = dockRevealTap {
            if !insideDock {
                let now = Date()
                if now.timeIntervalSince(lastKeepAlivePulse) > 0.40 {
                    lastKeepAlivePulse = now
                    Self.postMouseEvent(.mouseMoved, at: current.context.takeUnretainedValue().revealPoint, toDock: pid)
                }
            }
            return
        }

        let context = DockRevealContext(pid: pid, revealPoint: revealPoint)
        let unmanaged = Unmanaged.passRetained(context)

        guard let tap = CGEvent.tapCreateForPid(
            pid: pid,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(1) << Self.mouseExitedEventType.rawValue,
            callback: Self.dockEventTapCallback,
            userInfo: unmanaged.toOpaque()
        ) else {
            unmanaged.release()
            return
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            unmanaged.release()
            return
        }

        context.tap = tap
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        dockRevealTap = (tap, source, unmanaged)
        lastKeepAlivePulse = Date()

        if !insideDock {
            Self.postMouseEvent(.mouseMoved, at: revealPoint, toDock: pid)
        }
    }

    private func releaseDockReveal() {
        guard let pin = dockRevealTap else { return }
        dockRevealTap = nil

        let pid = pin.context.takeUnretainedValue().pid
        CFRunLoopRemoveSource(CFRunLoopGetMain(), pin.source, .commonModes)
        CFMachPortInvalidate(pin.tap)
        pin.context.release()

        // If mouse is currently outside the Dock bar region, notify Dock with mouseExited so it auto-hides naturally
        let mouseLoc = NSEvent.mouseLocation
        let primaryScreen = NSScreen.screens.first ?? NSScreen.main
        let (pos, dScreen) = detectDockPosition()
        let screen = dScreen ?? primaryScreen ?? NSScreen.screens[0]
        let dockBar = getDockBarGeometry(screen: screen)

        let isInsideDock: Bool
        if let bar = dockBar {
            isInsideDock = bar.insetBy(dx: -12, dy: -12).contains(mouseLoc)
        } else {
            isInsideDock = isMouseNearDockEdge(mouseLoc: mouseLoc, position: pos, screen: screen)
        }

        if !isInsideDock {
            let primaryHeight = primaryScreen?.frame.height ?? screen.frame.height
            let qPoint = CGPoint(x: mouseLoc.x, y: primaryHeight - mouseLoc.y)
            Self.postMouseEvent(Self.mouseExitedEventType, at: qPoint, toDock: pid)
        }
    }

    // MARK: - Extract Dock Item Info

    struct DockItemInfo {
        let title: String
        let frame: CGRect
        let url: URL?
        let isRunning: Bool
    }

    private func extractDockItemInfo(from element: AXUIElement, primaryScreen: NSScreen) -> DockItemInfo? {
        var roleRef: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        let role = roleRef as? String ?? ""

        var targetElement = element
        if role != "AXDockItem" {
            var parentRef: AnyObject?
            if AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parentRef) == .success,
               let parentElem = axElement(from: parentRef) {
                var parentRoleRef: AnyObject?
                AXUIElementCopyAttributeValue(parentElem, kAXRoleAttribute as CFString, &parentRoleRef)
                if (parentRoleRef as? String) == "AXDockItem" {
                    targetElement = parentElem
                } else {
                    return nil
                }
            } else {
                return nil
            }
        }

        var titleRef: AnyObject?
        AXUIElementCopyAttributeValue(targetElement, kAXTitleAttribute as CFString, &titleRef)
        guard let title = titleRef as? String, !title.isEmpty else { return nil }

        // Ignore trash and separator items
        if title == "Trash" || title == "Thùng rác" || title == "Bin" { return nil }

        var posRef: AnyObject?
        var sizeRef: AnyObject?
        AXUIElementCopyAttributeValue(targetElement, kAXPositionAttribute as CFString, &posRef)
        AXUIElementCopyAttributeValue(targetElement, kAXSizeAttribute as CFString, &sizeRef)

        let qPos = axPoint(from: posRef) ?? .zero
        let qSize = axSize(from: sizeRef) ?? .zero

        let appKitY = primaryScreen.frame.maxY - qPos.y - qSize.height
        let frame = CGRect(x: qPos.x, y: appKitY, width: qSize.width, height: qSize.height)

        var urlRef: AnyObject?
        var isRunningRef: AnyObject?
        AXUIElementCopyAttributeValue(targetElement, "AXURL" as CFString, &urlRef)
        AXUIElementCopyAttributeValue(targetElement, "AXIsApplicationRunning" as CFString, &isRunningRef)

        let fileURL: URL?
        if let url = urlRef as? URL {
            fileURL = url
        } else if let urlStr = urlRef as? String {
            fileURL = URL(string: urlStr)
        } else {
            fileURL = nil
        }

        let isRunning = (isRunningRef as? Bool) ?? ((isRunningRef as? Int) == 1)

        return DockItemInfo(title: title, frame: frame, url: fileURL, isRunning: isRunning)
    }

    // MARK: - Dock Position Detection

    func detectDockPosition() -> (DockScreenPosition, NSScreen?) {
        let mouseLoc = NSEvent.mouseLocation
        let primaryScreen = NSScreen.screens.first ?? NSScreen.main
        let screen = NSScreen.screens.first(where: { NSPointInRect(mouseLoc, $0.frame) }) ?? primaryScreen

        guard let screen else { return (.bottom, nil) }
        let full = screen.frame
        let vis = screen.visibleFrame

        // 1. Check if the screen under mouse or any connected screen has a fixed Dock gap
        if vis.minX > full.minX + 2 {
            return (.left, screen)
        } else if vis.maxX < full.maxX - 2 {
            return (.right, screen)
        } else if vis.minY > full.minY + 2 {
            return (.bottom, screen)
        }

        // Check other screens for fixed Dock (multi-monitor setup)
        for otherScreen in NSScreen.screens where otherScreen != screen {
            let oFull = otherScreen.frame
            let oVis = otherScreen.visibleFrame
            if oVis.minX > oFull.minX + 2 {
                return (.left, screen)
            } else if oVis.maxX < oFull.maxX - 2 {
                return (.right, screen)
            } else if oVis.minY > oFull.minY + 2 {
                return (.bottom, screen)
            }
        }

        // 2. Dock is set to Auto-hide.
        // Check 2.0s cache first to avoid querying CFPreferences / UserDefaults repeatedly
        let now = ProcessInfo.processInfo.systemUptime
        if let cached = cachedDockOrientation, now - cached.time < 2.0 {
            return (cached.pos, screen)
        }

        var detectedPos: DockScreenPosition = .bottom
        if let dockDefaults = UserDefaults(suiteName: "com.apple.dock"),
           let orientation = dockDefaults.string(forKey: "orientation") {
            switch orientation.lowercased() {
            case "left":
                detectedPos = .left
            case "right":
                detectedPos = .right
            case "bottom":
                detectedPos = .bottom
            default:
                break
            }
        } else if let pref = CFPreferencesCopyAppValue("orientation" as CFString, "com.apple.dock" as CFString) as? String {
            switch pref.lowercased() {
            case "left":
                detectedPos = .left
            case "right":
                detectedPos = .right
            case "bottom":
                detectedPos = .bottom
            default:
                break
            }
        }

        cachedDockOrientation = (detectedPos, now)
        return (detectedPos, screen)
    }

    // MARK: - Show & Capture Previews

    private func showPreview(forDockItem item: DockItemInfo, dockPos: DockScreenPosition, screen: NSScreen) {
        keepDockRevealed(screen: screen, dockPos: dockPos, mouseLoc: NSEvent.mouseLocation)
        guard let app = findRunningApplication(for: item) else {
            hidePreviewPanel(animated: true)
            return
        }

        self.currentApp = app
        viewModel.appName = app.localizedName ?? item.title
        viewModel.appIcon = app.icon
        viewModel.isLoading = true
        viewModel.dockPosition = dockPos

        Task {
            let windowItems = await fetchWindows(for: app)

            // If user opened context menu while fetching, abort immediately!
            if self.isContextMenuActive || self.isDockContextMenuOpen() {
                self.hidePreviewPanel(animated: false)
                return
            }

            // CRITICAL USER RULE:
            // If the user closed windows with the red button (0 valid windows remaining):
            // DO NOT OPEN OR DISPLAY ANY PREVIEW PANEL!
            guard !windowItems.isEmpty else {
                self.hidePreviewPanel(animated: true)
                return
            }

            self.viewModel.windows = windowItems
            self.viewModel.isLoading = false
            self.presentPanel(beside: item.frame, dockPos: dockPos, screen: screen)
        }
    }

    private func findRunningApplication(for dockInfo: DockItemInfo) -> NSRunningApplication? {
        let running = NSWorkspace.shared.runningApplications
        if let targetURL = dockInfo.url {
            let bundle = Bundle(url: targetURL)
            let targetBundleId = bundle?.bundleIdentifier
            if let match = running.first(where: {
                if let bId = $0.bundleIdentifier, let tId = targetBundleId, bId == tId { return true }
                if let bURL = $0.bundleURL, bURL == targetURL { return true }
                return false
            }) {
                return match
            }
        }

        let title = dockInfo.title
        if let exact = running.first(where: { $0.localizedName == title }) {
            return exact
        }
        return running.first(where: {
            guard let name = $0.localizedName else { return false }
            return name.localizedCaseInsensitiveContains(title) || title.localizedCaseInsensitiveContains(name)
        })
    }

    // MARK: - Filtered Window Fetching (Excludes Closed Windows, Supports Fullscreen & Minimized)

    private func fetchWindows(for app: NSRunningApplication) async -> [DockWindowItem] {
        let pid = app.processIdentifier
        let axApp = AXUIElementCreateApplication(pid)

        // 1. Gather all legitimate user AX Windows on current space (standard windows & dialogs)
        var axValidWindows: [(title: String, isMinimized: Bool, axWindow: AXUIElement)] = []
        var windowsRef: AnyObject?
        if AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
           let axList = windowsRef as? [AXUIElement] {
            for axWin in axList {
                var roleRef: AnyObject?
                var subroleRef: AnyObject?
                var minRef: AnyObject?
                var titleRef: AnyObject?
                AXUIElementCopyAttributeValue(axWin, kAXRoleAttribute as CFString, &roleRef)
                AXUIElementCopyAttributeValue(axWin, kAXSubroleAttribute as CFString, &subroleRef)
                AXUIElementCopyAttributeValue(axWin, kAXMinimizedAttribute as CFString, &minRef)
                AXUIElementCopyAttributeValue(axWin, kAXTitleAttribute as CFString, &titleRef)

                let role = roleRef as? String ?? ""
                let subrole = subroleRef as? String ?? ""
                // Ignore desktop, scroll areas, drawers, and menus
                guard role == "AXWindow" else { continue }
                guard subrole == "AXStandardWindow" || subrole == "AXDialog" || subrole.isEmpty else { continue }

                let isMin = (minRef as? Bool) ?? false
                let t = (titleRef as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                axValidWindows.append((title: t, isMinimized: isMin, axWindow: axWin))
            }
        }

        // 2. Fetch shareable windows from ScreenCaptureKit across all spaces (including Fullscreen)
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            let matchingWindows = content.windows.filter { scWin in
                guard scWin.owningApplication?.processID == pid else { return false }
                guard scWin.frame.width >= 120 && scWin.frame.height >= 80 else { return false }
                guard scWin.windowLayer == 0 || (scWin.windowLayer > 0 && scWin.windowLayer < 25) else { return false }
                return true
            }

            // If BOTH Accessibility windows AND ScreenCaptureKit windows are empty,
            // the app truly has NO open windows (e.g. user clicked the red X close button).
            // Do NOT open or display any preview panel!
            if axValidWindows.isEmpty && matchingWindows.isEmpty {
                return []
            }

            var result: [DockWindowItem] = []
            let targetWidth = Defaults[.dockPreviewSize].thumbnailWidth
            let scale = NSScreen.main?.backingScaleFactor ?? 2.0

            if !axValidWindows.isEmpty {
                for (index, axItem) in axValidWindows.prefix(10).enumerated() {
                    // Match with ScreenCaptureKit window
                    let scWin = matchingWindows.first(where: {
                        let scTitle = $0.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        return !scTitle.isEmpty && scTitle == axItem.title
                    }) ?? (index < matchingWindows.count ? matchingWindows[index] : nil)

                    let displayTitle = axItem.title.isEmpty ? (app.localizedName ?? "Window") : axItem.title
                    let winId = scWin?.windowID ?? UInt32(7000 + index)

                    var thumbImage: NSImage? = nil
                    if let scWin = scWin {
                        thumbImage = await captureThumbnail(for: scWin, targetWidth: targetWidth, scale: scale)
                    }

                    result.append(
                        DockWindowItem(
                            id: winId,
                            title: displayTitle,
                            frame: scWin?.frame ?? .zero,
                            thumbnail: thumbImage,
                            axWindow: axItem.axWindow,
                            isMinimized: axItem.isMinimized || (scWin != nil && !scWin!.isOnScreen)
                        )
                    )
                }
            } else {
                // axValidWindows is empty, but matchingWindows is NOT empty!
                // This happens when the app is in native macOS FULLSCREEN Space, or on an inactive Space.
                // Sort matching windows: windows with titles and larger window area first
                let sortedWindows = matchingWindows.sorted { (w1, w2) -> Bool in
                    let t1 = !(w1.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                    let t2 = !(w2.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                    if t1 != t2 { return t1 }
                    return (w1.frame.width * w1.frame.height) > (w2.frame.width * w2.frame.height)
                }

                for scWin in sortedWindows.prefix(10) {
                    let rawTitle = scWin.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let displayTitle = rawTitle.isEmpty ? (app.localizedName ?? "Window") : rawTitle
                    let thumbImage = await captureThumbnail(for: scWin, targetWidth: targetWidth, scale: scale)

                    result.append(
                        DockWindowItem(
                            id: scWin.windowID,
                            title: displayTitle,
                            frame: scWin.frame,
                            thumbnail: thumbImage,
                            axWindow: nil,
                            isMinimized: false
                        )
                    )
                }
            }

            return result
        } catch {
            // Graceful AX fallback
            var fallbackItems: [DockWindowItem] = []
            for (index, axItem) in axValidWindows.prefix(10).enumerated() {
                let displayTitle = axItem.title.isEmpty ? (app.localizedName ?? "Window") : axItem.title
                fallbackItems.append(
                    DockWindowItem(
                        id: UInt32(8000 + index),
                        title: displayTitle,
                        frame: .zero,
                        thumbnail: nil,
                        axWindow: axItem.axWindow,
                        isMinimized: axItem.isMinimized
                    )
                )
            }
            return fallbackItems
        }
    }

    private func captureThumbnail(for scWin: SCWindow, targetWidth: CGFloat, scale: CGFloat) async -> NSImage? {
        if let cached = thumbnailCache[scWin.windowID], Date().timeIntervalSince(cached.date) < 600.0 {
            return cached.image
        }

        let aspect = max(0.2, min(3.0, scWin.frame.height / max(1.0, scWin.frame.width)))
        let targetHeight = max(80.0, targetWidth * aspect)

        let config = SCStreamConfiguration()
        config.width = Int(targetWidth * scale)
        config.height = Int(targetHeight * scale)
        config.showsCursor = false

        if let cgImage = try? await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(desktopIndependentWindow: scWin),
            configuration: config
        ) {
            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: targetWidth, height: targetHeight))
            thumbnailCache[scWin.windowID] = (nsImage, Date())
            return nsImage
        }
        return nil
    }

    // MARK: - Panel Presentation with Consistent Fixed Small Spacing (Windows-like)

    /// Cached Dock bar geometry (Accessibility IPC is expensive; the Dock bar rarely changes shape).
    private var cachedDockBar: (rect: CGRect?, date: Date)?

    private func getDockBarGeometry(screen: NSScreen) -> CGRect? {
        if let cached = cachedDockBar, Date().timeIntervalSince(cached.date) < 0.75 {
            return cached.rect
        }
        let rect = computeDockBarGeometry(screen: screen)
        cachedDockBar = (rect, Date())
        return rect
    }

    private func computeDockBarGeometry(screen: NSScreen) -> CGRect? {
        guard let dockApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            return nil
        }
        let dockAX = AXUIElementCreateApplication(dockApp.processIdentifier)
        var childrenRef: AnyObject?
        guard AXUIElementCopyAttributeValue(dockAX, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else {
            return nil
        }

        let primaryScreen = NSScreen.screens.first ?? screen
        for child in children {
            var roleRef: AnyObject?
            AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleRef)
            if (roleRef as? String) == "AXList" {
                var posRef: AnyObject?
                var sizeRef: AnyObject?
                AXUIElementCopyAttributeValue(child, kAXPositionAttribute as CFString, &posRef)
                AXUIElementCopyAttributeValue(child, kAXSizeAttribute as CFString, &sizeRef)
                let qPos = axPoint(from: posRef) ?? .zero
                let qSize = axSize(from: sizeRef) ?? .zero

                if qSize.width > 0 && qSize.height > 0 {
                    let appKitY = primaryScreen.frame.maxY - qPos.y - qSize.height
                    return CGRect(x: qPos.x, y: appKitY, width: qSize.width, height: qSize.height)
                }
            }
        }
        return nil
    }

    private func presentPanel(beside itemFrame: CGRect, dockPos: DockScreenPosition, screen: NSScreen) {
        if isContextMenuActive || isDockContextMenuOpen() {
            return
        }

        if previewPanel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 240, height: 180),
                styleMask: [.nonactivatingPanel, .borderless],
                backing: .buffered,
                defer: false
            )
            panel.level = .popUpMenu
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.isMovableByWindowBackground = false
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

            let hosting = NSHostingView(rootView: DockPreviewView(viewModel: viewModel))
            panel.contentView = hosting
            self.previewPanel = panel
            self.hostingView = hosting
        }

        guard let panel = previewPanel, let hosting = hostingView else { return }

        viewModel.dockPosition = dockPos

        // Force SwiftUI to evaluate complete layout and fitting size for current windows count
        hosting.layoutSubtreeIfNeeded()
        let targetSize = hosting.fittingSize

        // Read Dock Magnification settings from macOS to calculate maximum possible protrusion
        let dockDefaults = UserDefaults(suiteName: "com.apple.dock")
        let isMagnification = dockDefaults?.bool(forKey: "magnification") ?? false
        let tilesize = CGFloat(dockDefaults?.double(forKey: "tilesize") ?? 48.0)
        let largesize = CGFloat(dockDefaults?.double(forKey: "largesize") ?? 82.0)
        // Max theoretical expansion beyond normal tilesize:
        let maxExpansion = isMagnification ? max(0.0, largesize - tilesize) : 0.0

        // Margin into dock: -4px (pull closer into the dock edge)
        let baseMargin: CGFloat = -4.0
        var panelOrigin = NSPoint.zero
        let dockBarFrame = getDockBarGeometry(screen: screen)

        switch dockPos {
        case .right:
            // DOCK ON RIGHT -> Panel MUST strictly be to the LEFT of the Dock!
            let dockWidth = dockBarFrame?.width ?? max(68.0, itemFrame.width + 16.0)
            let dockLeftEdge: CGFloat
            if let dbFrame = dockBarFrame, dbFrame.minX < screen.frame.maxX - 5 {
                dockLeftEdge = dbFrame.minX
            } else {
                dockLeftEdge = screen.frame.maxX - dockWidth
            }

            // Always calculate based on the MAXIMUM protrusion of the icon (magnification max),
            // so even if the icon is still animating/expanding or hasn't finished protruding yet,
            // the preview is positioned safely beyond max expansion + 10px, never overlapping the logo!
            let maxIconLeftEdge = min(dockLeftEdge - maxExpansion, itemFrame.minX)
            panelOrigin.x = maxIconLeftEdge - targetSize.width - baseMargin
            panelOrigin.y = itemFrame.midY - targetSize.height / 2.0

            panelOrigin.x = max(screen.frame.minX + 12, min(maxIconLeftEdge - targetSize.width - baseMargin, panelOrigin.x))
            panelOrigin.y = max(screen.frame.minY + 12, min(screen.frame.maxY - targetSize.height - 12, panelOrigin.y))

        case .left:
            // DOCK ON LEFT -> Panel MUST strictly be to the RIGHT of the Dock!
            let dockWidth = dockBarFrame?.width ?? max(68.0, itemFrame.width + 16.0)
            let dockRightEdge: CGFloat
            if let dbFrame = dockBarFrame, dbFrame.maxX > screen.frame.minX + 5 {
                dockRightEdge = dbFrame.maxX
            } else {
                dockRightEdge = screen.frame.minX + dockWidth
            }

            let maxIconRightEdge = max(dockRightEdge + maxExpansion, itemFrame.maxX)
            panelOrigin.x = maxIconRightEdge + baseMargin
            panelOrigin.y = itemFrame.midY - targetSize.height / 2.0

            panelOrigin.x = min(screen.frame.maxX - targetSize.width - 12, max(maxIconRightEdge + baseMargin, panelOrigin.x))
            panelOrigin.y = max(screen.frame.minY + 12, min(screen.frame.maxY - targetSize.height - 12, panelOrigin.y))

        case .bottom, .hidden:
            // DOCK AT BOTTOM -> Panel MUST strictly be ABOVE the Dock!
            let dockHeight = dockBarFrame?.height ?? max(68.0, itemFrame.height + 16.0)
            let dockTopEdge: CGFloat
            if let dbFrame = dockBarFrame, dbFrame.maxY > screen.frame.minY + 5 {
                dockTopEdge = dbFrame.maxY
            } else {
                dockTopEdge = screen.frame.minY + dockHeight
            }

            let maxIconTopEdge = max(dockTopEdge + maxExpansion, itemFrame.maxY)
            panelOrigin.y = maxIconTopEdge + baseMargin
            panelOrigin.x = itemFrame.midX - targetSize.width / 2.0

            panelOrigin.x = max(screen.frame.minX + 12, min(screen.frame.maxX - targetSize.width - 12, panelOrigin.x))
            panelOrigin.y = min(screen.frame.maxY - targetSize.height - 12, max(maxIconTopEdge + baseMargin, panelOrigin.y))
        }

        let newFrame = NSRect(origin: panelOrigin, size: targetSize)
        panel.setFrame(newFrame, display: true)
        panel.invalidateShadow()

        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.12
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1.0
            }
        } else {
            panel.orderFrontRegardless()
        }

        isPanelVisible = true
        keepDockRevealed(screen: screen, dockPos: dockPos, mouseLoc: NSEvent.mouseLocation)
    }

    private func hidePreviewPanel(animated: Bool) {
        releaseDockReveal()
        guard let panel = previewPanel, isPanelVisible else { return }
        isPanelVisible = false
        lastHoveredTitle = nil
        // Retain thumbnailCache so minimized windows keep their captured previews!
        if thumbnailCache.count > 60 {
            let now = Date()
            thumbnailCache = thumbnailCache.filter { now.timeIntervalSince($0.value.date) < 900 }
        }
        viewModel.windows.removeAll()

        if animated {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.12
                panel.animator().alphaValue = 0.0
            }, completionHandler: { [weak panel] in
                Task { @MainActor in
                    panel?.orderOut(nil)
                }
            })
        } else {
            panel.alphaValue = 0.0
            panel.orderOut(nil)
        }
    }

    // MARK: - Window Interactions

    private func activateWindow(_ item: DockWindowItem) {
        if let axWin = item.axWindow {
            if item.isMinimized {
                AXUIElementSetAttributeValue(axWin, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            }
            AXUIElementPerformAction(axWin, kAXRaiseAction as CFString)
        }
        currentApp?.activate()
        hidePreviewPanel(animated: true)
    }

    private func closeWindow(_ item: DockWindowItem) {
        if let axWin = item.axWindow {
            var closeBtnRef: AnyObject?
            if AXUIElementCopyAttributeValue(axWin, kAXCloseButtonAttribute as CFString, &closeBtnRef) == .success,
               let closeBtn = axElement(from: closeBtnRef) {
                AXUIElementPerformAction(closeBtn, kAXPressAction as CFString)
            }
        }
        viewModel.windows.removeAll(where: { $0.id == item.id })
        if viewModel.windows.isEmpty {
            hidePreviewPanel(animated: true)
        }
    }
}


// MARK: - Safe Accessibility Casting (no force-casts → no crash if Dock returns unexpected types)

private func axElement(from ref: AnyObject?) -> AXUIElement? {
    guard let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
    return unsafeBitCast(ref, to: AXUIElement.self)
}

private func axPoint(from ref: AnyObject?) -> CGPoint? {
    guard let ref, CFGetTypeID(ref) == AXValueGetTypeID() else { return nil }
    let value = unsafeBitCast(ref, to: AXValue.self)
    var point = CGPoint.zero
    return AXValueGetValue(value, .cgPoint, &point) ? point : nil
}

private func axSize(from ref: AnyObject?) -> CGSize? {
    guard let ref, CFGetTypeID(ref) == AXValueGetTypeID() else { return nil }
    let value = unsafeBitCast(ref, to: AXValue.self)
    var size = CGSize.zero
    return AXValueGetValue(value, .cgSize, &size) ? size : nil
}
