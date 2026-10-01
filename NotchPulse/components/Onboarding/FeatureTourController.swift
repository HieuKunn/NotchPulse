//
//  FeatureTourController.swift
//  NotchPulse
//
//  Created for NotchPulse - Spotlight Feature Tour & What's New Presenter
//

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
final class FeatureTourController: NSObject {
    static let shared = FeatureTourController()

    public var isTourActive: Bool = false
    public var interactiveCardRect: CGRect?
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
        window.level = .mainMenu + 2
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
