import AppKit
import Combine
import Defaults
import ScreenCaptureKit
import SwiftUI

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

    var onSelectWindow: ((DockWindowItem) -> Void)?
    var onCloseWindow: ((DockWindowItem) -> Void)?
}

// MARK: - Dock Preview Manager

@MainActor
final class DockPreviewManager: ObservableObject {
    static let shared = DockPreviewManager()

    private var mouseMonitor: Any?
    private var hoverTimer: Timer?
    private var dismissTimer: Timer?
    private var lastHoveredTitle: String? = nil
    private var lastHoveredItemFrame: CGRect = .zero
    private var isPanelVisible: Bool = false

    private var previewPanel: NSPanel?
    private var hostingView: NSHostingView<DockPreviewView>?
    let viewModel = DockPreviewViewModel()

    private var thumbnailCache: [CGWindowID: (image: NSImage, date: Date)] = [:]
    private var isConfigured = false

    private init() {
        setupCallbacks()
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
        guard !isConfigured else { return }
        isConfigured = true

        startMouseMonitoring()
    }

    func teardown() {
        stopMouseMonitoring()
        hoverTimer?.invalidate()
        hoverTimer = nil
        dismissTimer?.invalidate()
        dismissTimer = nil
        hidePreviewPanel(animated: false)
        isConfigured = false
    }

    // MARK: - Mouse Event Monitoring

    private func startMouseMonitoring() {
        guard mouseMonitor == nil else { return }

        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleGlobalMouseMove()
            }
        }
    }

    private func stopMouseMonitoring() {
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
    }

    // MARK: - Hover Detection

    private func handleGlobalMouseMove() {
        guard Defaults[.enableDockPreview] else { return }

        let mouseLoc = NSEvent.mouseLocation
        let (dockPos, dockScreen) = detectDockPosition()

        guard dockPos != .hidden, let screen = dockScreen else {
            scheduleDismissalIfNeeded(mouseLoc: mouseLoc)
            return
        }

        // Fast screen edge bounds check before querying Accessibility
        guard isMouseNearDockEdge(mouseLoc: mouseLoc, position: dockPos, screen: screen) else {
            scheduleDismissalIfNeeded(mouseLoc: mouseLoc)
            return
        }

        // If mouse is inside currently visible preview panel, keep it alive
        if isPanelVisible, let panel = previewPanel, panel.frame.insetBy(dx: -10, dy: -10).contains(mouseLoc) {
            dismissTimer?.invalidate()
            dismissTimer = nil
            return
        }

        // Query element under mouse
        let systemWide = AXUIElementCreateSystemWide()
        var elementRef: AXUIElement?
        // AppKit coordinates: origin is bottom-left. Quartz AX coordinates: origin is top-left.
        let quartzY = screen.frame.maxY - mouseLoc.y
        let status = AXUIElementCopyElementAtPosition(systemWide, Float(mouseLoc.x), Float(quartzY), &elementRef)

        guard status == .success, let element = elementRef else {
            scheduleDismissalIfNeeded(mouseLoc: mouseLoc)
            return
        }

        guard let (title, itemFrame) = extractDockItemInfo(from: element, screen: screen) else {
            scheduleDismissalIfNeeded(mouseLoc: mouseLoc)
            return
        }

        // Mouse is hovering over a valid Dock item
        dismissTimer?.invalidate()
        dismissTimer = nil

        if title == lastHoveredTitle && isPanelVisible {
            return
        }

        if title != lastHoveredTitle {
            lastHoveredTitle = title
            lastHoveredItemFrame = itemFrame
            hoverTimer?.invalidate()

            let delay = Defaults[.dockPreviewHoverDelay]
            hoverTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.showPreview(forAppTitle: title, itemFrame: itemFrame, dockPos: dockPos, screen: screen)
                }
            }
        }
    }

    private func isMouseNearDockEdge(mouseLoc: NSPoint, position: DockScreenPosition, screen: NSScreen) -> Bool {
        let margin: CGFloat = 85.0
        switch position {
        case .bottom:
            return mouseLoc.y <= screen.visibleFrame.minY + margin
        case .left:
            return mouseLoc.x <= screen.visibleFrame.minX + margin
        case .right:
            return mouseLoc.x >= screen.visibleFrame.maxX - margin
        case .hidden:
            return false
        }
    }

    private func scheduleDismissalIfNeeded(mouseLoc: NSPoint) {
        hoverTimer?.invalidate()
        hoverTimer = nil
        lastHoveredTitle = nil

        guard isPanelVisible else { return }

        if let panel = previewPanel, panel.frame.insetBy(dx: -14, dy: -14).contains(mouseLoc) {
            return
        }

        if dismissTimer == nil {
            dismissTimer = Timer.scheduledTimer(withTimeInterval: 0.18, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.hidePreviewPanel(animated: true)
                }
            }
        }
    }

    // MARK: - Extract Dock Item Info

    private func extractDockItemInfo(from element: AXUIElement, screen: NSScreen) -> (String, CGRect)? {
        var roleRef: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        let role = roleRef as? String ?? ""

        // Check if element itself is an AXDockItem or child of one
        var targetElement = element
        if role != "AXDockItem" {
            var parentRef: AnyObject?
            if AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parentRef) == .success,
               let parent = parentRef {
                let parentElem = parent as! AXUIElement
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

        // Filter out Trash or Separator or Launchpad if user wants only regular apps
        if title == "Trash" || title == "Thùng rác" { return nil }

        var posRef: AnyObject?
        var sizeRef: AnyObject?
        AXUIElementCopyAttributeValue(targetElement, kAXPositionAttribute as CFString, &posRef)
        AXUIElementCopyAttributeValue(targetElement, kAXSizeAttribute as CFString, &sizeRef)

        var qPos = CGPoint.zero
        var qSize = CGSize.zero
        if let p = posRef { AXValueGetValue(p as! AXValue, .cgPoint, &qPos) }
        if let s = sizeRef { AXValueGetValue(s as! AXValue, .cgSize, &qSize) }

        // Convert Quartz coordinates (top-left) to AppKit coordinates (bottom-left)
        let appKitY = screen.frame.maxY - qPos.y - qSize.height
        let frame = CGRect(x: qPos.x, y: appKitY, width: qSize.width, height: qSize.height)

        return (title, frame)
    }

    // MARK: - Dock Position Detection

    func detectDockPosition() -> (DockScreenPosition, NSScreen?) {
        guard let screen = NSScreen.main else { return (.hidden, nil) }
        let full = screen.frame
        let vis = screen.visibleFrame

        if vis.minX > full.minX + 2 {
            return (.left, screen)
        } else if vis.maxX < full.maxX - 2 {
            return (.right, screen)
        } else if vis.minY > full.minY + 2 {
            return (.bottom, screen)
        } else {
            return (.hidden, screen)
        }
    }

    // MARK: - Show & Capture Previews

    private func showPreview(forAppTitle title: String, itemFrame: CGRect, dockPos: DockScreenPosition, screen: NSScreen) {
        // Find matching running application
        guard let app = findRunningApplication(named: title) else {
            hidePreviewPanel(animated: true)
            return
        }

        viewModel.appName = app.localizedName ?? title
        viewModel.appIcon = app.icon
        viewModel.isLoading = true

        Task {
            let windowItems = await fetchWindows(for: app)
            guard !windowItems.isEmpty else {
                self.hidePreviewPanel(animated: true)
                return
            }

            self.viewModel.windows = windowItems
            self.viewModel.isLoading = false
            self.presentPanel(beside: itemFrame, dockPos: dockPos, screen: screen)
        }
    }

    private func findRunningApplication(named title: String) -> NSRunningApplication? {
        let running = NSWorkspace.shared.runningApplications
        if let exact = running.first(where: { $0.localizedName == title }) {
            return exact
        }
        return running.first(where: {
            guard let name = $0.localizedName else { return false }
            return name.localizedCaseInsensitiveContains(title) || title.localizedCaseInsensitiveContains(name)
        })
    }

    // MARK: - ScreenCaptureKit Window Fetching

    private func fetchWindows(for app: NSRunningApplication) async -> [DockWindowItem] {
        let pid = app.processIdentifier
        let axApp = AXUIElementCreateApplication(pid)

        // Get AXWindows
        var axWindowsMap: [String: AXUIElement] = [:]
        var windowsRef: AnyObject?
        if AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
           let axList = windowsRef as? [AXUIElement] {
            for axWin in axList {
                var titleRef: AnyObject?
                AXUIElementCopyAttributeValue(axWin, kAXTitleAttribute as CFString, &titleRef)
                let t = titleRef as? String ?? ""
                axWindowsMap[t] = axWin
            }
        }

        // Fetch shareable content via ScreenCaptureKit
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            let matchingWindows = content.windows.filter { scWin in
                guard scWin.owningApplication?.processID == pid else { return false }
                guard scWin.frame.width >= 120 && scWin.frame.height >= 80 else { return false }
                // Exclude system HUD/shadow overlays
                guard scWin.windowLayer == 0 else { return false }
                return true
            }

            guard !matchingWindows.isEmpty else { return [] }

            var result: [DockWindowItem] = []
            let targetWidth = Defaults[.dockPreviewSize].thumbnailWidth
            let scale = NSScreen.main?.backingScaleFactor ?? 2.0

            for scWin in matchingWindows.prefix(6) {
                let winTitle = scWin.title?.trimmingCharacters(in: .whitespacesAndNewlines)
                let displayTitle = (winTitle?.isEmpty == false) ? winTitle! : (app.localizedName ?? "Window")

                // Check cache first
                var thumbImage: NSImage? = nil
                if let cached = thumbnailCache[scWin.windowID], Date().timeIntervalSince(cached.date) < 3.0 {
                    thumbImage = cached.image
                } else {
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
                        thumbImage = nsImage
                    }
                }

                let axWin = axWindowsMap[winTitle ?? ""] ?? axWindowsMap.values.first
                result.append(
                    DockWindowItem(
                        id: scWin.windowID,
                        title: displayTitle,
                        frame: scWin.frame,
                        thumbnail: thumbImage,
                        axWindow: axWin,
                        isMinimized: false
                    )
                )
            }
            return result
        } catch {
            // Graceful Accessibility Fallback (No Screen Recording Permission needed):
            // Still shows window title list, click-to-activate, and close button!
            var fallbackItems: [DockWindowItem] = []
            var counter: UInt32 = 1000
            for (title, axWin) in axWindowsMap {
                let displayTitle = title.isEmpty ? (app.localizedName ?? "Window") : title
                fallbackItems.append(
                    DockWindowItem(
                        id: counter,
                        title: displayTitle,
                        frame: .zero,
                        thumbnail: nil,
                        axWindow: axWin,
                        isMinimized: false
                    )
                )
                counter += 1
            }
            return fallbackItems
        }
    }

    // MARK: - Panel Presentation & Layout

    private func presentPanel(beside itemFrame: CGRect, dockPos: DockScreenPosition, screen: NSScreen) {
        if previewPanel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
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

        // Fit content size
        let targetSize = hosting.fittingSize
        panel.setContentSize(targetSize)

        // Calculate position relative to the hovered Dock item
        var panelOrigin = NSPoint.zero
        let spacing: CGFloat = 12.0

        switch dockPos {
        case .right:
            // Dock on the right side -> Popup opens to the left of the dock
            panelOrigin.x = itemFrame.minX - targetSize.width - spacing
            panelOrigin.y = itemFrame.midY - targetSize.height / 2.0
        case .left:
            // Dock on the left side -> Popup opens to the right of the dock
            panelOrigin.x = itemFrame.maxX + spacing
            panelOrigin.y = itemFrame.midY - targetSize.height / 2.0
        case .bottom, .hidden:
            // Dock at the bottom -> Popup opens above the dock
            panelOrigin.x = itemFrame.midX - targetSize.width / 2.0
            panelOrigin.y = itemFrame.maxY + spacing
        }

        // Clamp to screen visibleFrame so it never bleeds offscreen
        let vis = screen.visibleFrame
        panelOrigin.x = max(vis.minX + 8, min(vis.maxX - targetSize.width - 8, panelOrigin.x))
        panelOrigin.y = max(vis.minY + 8, min(vis.maxY - targetSize.height - 8, panelOrigin.y))

        panel.setFrameOrigin(panelOrigin)

        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1.0
            }
        } else {
            panel.orderFrontRegardless()
        }

        isPanelVisible = true
    }

    private func hidePreviewPanel(animated: Bool) {
        guard let panel = previewPanel, isPanelVisible else { return }
        isPanelVisible = false
        lastHoveredTitle = nil
        thumbnailCache.removeAll()
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
        hidePreviewPanel(animated: false)

        if let axWin = item.axWindow {
            AXUIElementPerformAction(axWin, kAXRaiseAction as CFString)
        }
        if let app = findRunningApplication(named: viewModel.appName) {
            app.activate()
        }
    }

    private func closeWindow(_ item: DockWindowItem) {
        if let axWin = item.axWindow {
            var closeBtnRef: AnyObject?
            if AXUIElementCopyAttributeValue(axWin, kAXCloseButtonAttribute as CFString, &closeBtnRef) == .success,
               let closeBtn = closeBtnRef {
                AXUIElementPerformAction(closeBtn as! AXUIElement, kAXPressAction as CFString)
            }
        }
        // Remove item from view model
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            viewModel.windows.removeAll(where: { $0.id == item.id })
            if viewModel.windows.isEmpty {
                hidePreviewPanel(animated: true)
            }
        }
    }
}

