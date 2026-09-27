//
//  NotchPulseSkyLightWindow.swift
//  NotchPulse
//
//  Created by Alexander on 2025-10-20.
//

import Cocoa
import SkyLightWindow
import Defaults
import Combine
import SwiftUI

extension SkyLightOperator {
    func undelegateWindow(_ window: NSWindow) {
        typealias F_SLSRemoveWindowsFromSpaces = @convention(c) (Int32, CFArray, CFArray) -> Int32
        
        let handler = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_NOW)
        guard let SLSRemoveWindowsFromSpaces = unsafeBitCast(
            dlsym(handler, "SLSRemoveWindowsFromSpaces"),
            to: F_SLSRemoveWindowsFromSpaces?.self
        ) else {
            return
        }
        
        // Remove the window from the SkyLight space
        _ = SLSRemoveWindowsFromSpaces(
            connection,
            [window.windowNumber] as CFArray,
            [space] as CFArray
        )
    }
}

class NotchPulseSkyLightWindow: NSPanel {
    private var isSkyLightEnabled: Bool = false
    private var observers: Set<AnyCancellable> = []
    
    override init(
        contentRect: NSRect,
        styleMask: NSWindow.StyleMask,
        backing: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: styleMask,
            backing: backing,
            defer: flag
        )
        
        configureWindow()
        setupObservers()
    }
    
    private func configureWindow() {
        isFloatingPanel = true
        isOpaque = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        backgroundColor = .clear
        isMovable = false
        level = .mainMenu + 3
        hasShadow = false
        isReleasedWhenClosed = false
        
        // Force dark appearance regardless of system setting
        appearance = NSAppearance(named: .darkAqua)
        
        collectionBehavior = [
            .fullScreenAuxiliary,
            .stationary,
            .canJoinAllSpaces,
            .ignoresCycle,
        ]
        
        // Apply initial sharing type setting
        updateSharingType()
    }
    
    private func setupObservers() {
        // Listen for changes to the hideFromScreenRecording setting
        Defaults.publisher(.hideFromScreenRecording)
            .sink { [weak self] _ in
                self?.updateSharingType()
            }
            .store(in: &observers)
    }
    
    private func updateSharingType() {
        if Defaults[.hideFromScreenRecording] {
            sharingType = .none
        } else {
            sharingType = .readWrite
        }
    }
    
    func enableSkyLight() {
        if !isSkyLightEnabled {
            SkyLightOperator.shared.delegateWindow(self)
            isSkyLightEnabled = true
        }
    }
    
    func disableSkyLight() {
        if isSkyLightEnabled {
            SkyLightOperator.shared.undelegateWindow(self)
            isSkyLightEnabled = false
        }
    }
    
    override var canBecomeKey: Bool {
        FaceIDOverlayController.shared.phase == .onboarding
    }
    override var canBecomeMain: Bool {
        FaceIDOverlayController.shared.phase == .onboarding
    }
}

// MARK: - NotchPulseHostingView with Passthrough Hit-Testing
/// Ensures that mouse clicks outside the active, visible notch bounds are strictly passed through (returning nil).
/// This prevents any transparent window canvas or padding from blocking clicks to underlying browser tabs, links, or controls.
final class NotchPulseHostingView<Content: View>: NSHostingView<Content> {
    weak var viewModel: NotchPulseViewModel?

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Allow normal event routing if Face ID onboarding requires keyboard/mouse focus
        if FaceIDOverlayController.shared.phase == .onboarding {
            return super.hitTest(point)
        }

        guard let vm = viewModel else {
            return super.hitTest(point)
        }

        let isDynamicIsland = Defaults[.notchStyle] == .dynamicIsland
        let screen = window?.screen ?? NSScreen.main
        let hasPhysicalNotch = (screen?.safeAreaInsets.top ?? 0) > 0 || screen?.auxiliaryTopLeftArea != nil
        let topOffset: CGFloat = (isDynamicIsland && !hasPhysicalNotch) ? CGFloat(Defaults[.dynamicIslandTopOffset]) : 0

        let notchWidth: CGFloat
        let notchHeight: CGFloat

        if vm.notchState == .open {
            notchWidth = max(vm.notchSize.width, openNotchWidth) + 30
            notchHeight = (vm.customOpenHeight ?? vm.notchSize.height) + topOffset + 30
        } else {
            let closedW = isDynamicIsland ? 210.0 : (vm.closedNotchSize.width > 0 ? vm.closedNotchSize.width : 185.0)
            let closedH = isDynamicIsland ? 32.0 : (vm.effectiveClosedNotchHeight > 0 ? vm.effectiveClosedNotchHeight : 36.0)
            let chinH = vm.chinHeight
            let bottomRowH: CGFloat = 40 // Sneak peek or HUD if active

            notchWidth = max(closedW, 240.0) + (vm.isCameraExpanded ? 60.0 : 0.0)
            notchHeight = closedH + chinH + bottomRowH + topOffset + 10
        }

        let notchRect: NSRect
        if isFlipped {
            notchRect = NSRect(
                x: bounds.midX - (notchWidth / 2),
                y: topOffset,
                width: notchWidth,
                height: notchHeight
            )
        } else {
            notchRect = NSRect(
                x: bounds.midX - (notchWidth / 2),
                y: bounds.height - (topOffset + notchHeight),
                width: notchWidth,
                height: notchHeight
            )
        }

        // Strictly ignore any clicks outside the visible notch bounds.
        // Returning nil lets macOS pass mouse clicks directly to underlying
        // windows (Safari/Chrome tabs, address bar, web links, etc.) without any interference.
        guard notchRect.contains(point) else {
            return nil
        }

        return super.hitTest(point)
    }
}

