import AppKit
import SwiftUI
import Defaults

final class PassthroughTourHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard FeatureTourController.shared.isTourActive else {
            return super.hitTest(point)
        }
        guard let cardRect = FeatureTourController.shared.interactiveCardRect else {
            return nil
        }
        // point in hitTest is in window / superview coordinates. Convert to local flipped coordinates:
        let localPoint = self.convert(point, from: self.superview)
        let expandedCardRect = cardRect.insetBy(dx: -12, dy: -12)
        if expandedCardRect.contains(localPoint) {
            return super.hitTest(point)
        }
        return nil
    }
}

@MainActor
final class FeatureTourController: NSObject, ObservableObject {
    static let shared = FeatureTourController()

    @Published public var isTourActive: Bool = false
    public var interactiveCardRect: CGRect?
    @Published public var settingsGearScreenRect: CGRect?
    private var tourWindow: NSWindow?

    override private init() {
        super.init()
    }

    func startTour() {
        isTourActive = true
        let coordinator = NotchPulseViewCoordinator.shared
        coordinator.firstLaunch = false

        let targetScreen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 || $0.auxiliaryTopLeftArea != nil }) ?? NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
        let appDelegate = (NSApp.delegate as? AppDelegate) ?? AppDelegate.shared
        let targetVM: NotchPulseViewModel
        if Defaults[.showOnAllDisplays], let uuid = targetScreen.displayUUID, let sub = appDelegate?.viewModels[uuid] {
            targetVM = sub
        } else {
            targetVM = appDelegate?.vm ?? NotchPulseViewModel()
        }

        targetVM.open()

        // Tear down any existing tour window
        if let existing = tourWindow {
            existing.orderOut(nil)
            tourWindow = nil
        }

        let screen = targetScreen
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.level = .mainMenu + 4
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.setFrame(screen.frame, display: true)
        window.isReleasedWhenClosed = false
        window.identifier = NSUserInterfaceItemIdentifier("FeatureTourWindow")

        window.contentView = PassthroughTourHostingView(
            rootView: FeatureTourView(onFinish: { [weak self] in
                self?.dismissTour()
            })
            .environmentObject(coordinator)
            .environmentObject(targetVM)
        )

        self.tourWindow = window

        // Bring to front
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    func dismissTour() {
        isTourActive = false
        interactiveCardRect = nil
        settingsGearScreenRect = nil
        tourWindow?.orderOut(nil)
        tourWindow = nil

        let coordinator = NotchPulseViewCoordinator.shared
        let appDelegate = (NSApp.delegate as? AppDelegate) ?? AppDelegate.shared

        coordinator.firstLaunch = false
        coordinator.currentView = .home
        CalendarStateViewModel.shared.isFullMonthExpanded = false
        
        let targetScreen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 || $0.auxiliaryTopLeftArea != nil }) ?? NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
        let targetVM: NotchPulseViewModel
        if Defaults[.showOnAllDisplays], let uuid = targetScreen.displayUUID, let sub = appDelegate?.viewModels[uuid] {
            targetVM = sub
        } else {
            targetVM = appDelegate?.vm ?? NotchPulseViewModel()
        }

        targetVM.customOpenHeight = nil
        targetVM.featureTourTarget = nil
        targetVM.close(force: true)
    }
}

struct ScreenFrameReader: NSViewRepresentable {
    let onFrameChange: (CGRect) -> Void

    func makeNSView(context: Context) -> FrameObserverView {
        let view = FrameObserverView()
        view.onFrameChange = onFrameChange
        return view
    }

    func updateNSView(_ nsView: FrameObserverView, context: Context) {
        nsView.onFrameChange = onFrameChange
    }

    class FrameObserverView: NSView {
        var onFrameChange: ((CGRect) -> Void)?
        private var lastReportedRect: CGRect = .zero

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            reportFrame()
        }

        override func layout() {
            super.layout()
            reportFrame()
        }

        private func reportFrame() {
            guard let window = self.window, let screen = window.screen else { return }
            let windowRect = convert(bounds, to: nil)
            let screenRect = window.convertToScreen(windowRect)
            let swiftUIRect = CGRect(
                x: screenRect.origin.x - screen.frame.origin.x,
                y: screen.frame.maxY - screenRect.maxY,
                width: screenRect.width,
                height: screenRect.height
            )
            guard abs(swiftUIRect.origin.x - lastReportedRect.origin.x) > 0.5 ||
                  abs(swiftUIRect.origin.y - lastReportedRect.origin.y) > 0.5 ||
                  abs(swiftUIRect.width - lastReportedRect.width) > 0.5 ||
                  abs(swiftUIRect.height - lastReportedRect.height) > 0.5 else { return }
            lastReportedRect = swiftUIRect
            DispatchQueue.main.async {
                self.onFrameChange?(swiftUIRect)
            }
        }
    }
}

