//
//  FeatureTourController.swift
//  NotchPulse
//
//  Created for NotchPulse - Spotlight Feature Tour & What's New Presenter
//

import AppKit
import SwiftUI

final class PassthroughTourHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? {
        if FeatureTourController.shared.isTourActive, let cardRect = FeatureTourController.shared.interactiveCardRect {
            let expandedCardRect = cardRect.insetBy(dx: -4, dy: -4)
            if expandedCardRect.contains(point) {
                return super.hitTest(point)
            }
            return nil
        }
        return super.hitTest(point)
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
        // Open the notch and ensure it stays open
        let vm = (AppDelegate.shared?.vm) ?? NotchPulseViewModel()
        vm.open()
        if let viewModels = AppDelegate.shared?.viewModels {
            for subVm in viewModels.values {
                subVm.open()
            }
        }

        // Tear down any existing tour window
        if let existing = tourWindow {
            existing.orderOut(nil)
            tourWindow = nil
        }

        let screen = NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
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

        let coordinator = NotchPulseViewCoordinator.shared

        window.contentView = PassthroughTourHostingView(
            rootView: FeatureTourView(onFinish: { [weak self] in
                self?.dismissTour()
            })
            .environmentObject(coordinator)
            .environmentObject(vm)
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
        let vm = (AppDelegate.shared?.vm) ?? NotchPulseViewModel()

        coordinator.firstLaunch = false
        coordinator.currentView = .home
        CalendarStateViewModel.shared.isFullMonthExpanded = false
        vm.customOpenHeight = nil
        vm.featureTourTarget = nil
        vm.close(force: true)
        if let viewModels = AppDelegate.shared?.viewModels {
            for subVm in viewModels.values {
                subVm.customOpenHeight = nil
                subVm.featureTourTarget = nil
                subVm.close(force: true)
            }
        }
    }
}
