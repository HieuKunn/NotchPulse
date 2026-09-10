//
//  LockScreenFaceIDWindow.swift
//  NotchPulse
//
//  Created for NotchPulse - Lock Screen Face ID Large Drop-Down Notch Overlay
//

import Cocoa
import Combine
import Defaults
import SkyLightWindow
import SwiftUI

// MARK: - AppKit Tracking Hosting View with activeAlways for Lock Screen
final class LockScreenTrackingHostingView<Content: View>: NSHostingView<Content> {
    var onHoverChanged: ((Bool) -> Void)?
    var onClicked: (() -> Void)?
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea {
            removeTrackingArea(ta)
        }
        let options: NSTrackingArea.Options = [
            .mouseEnteredAndExited,
            .mouseMoved,
            .activeAlways,
            .inVisibleRect
        ]
        let ta = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(ta)
        self.trackingArea = ta
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHoverChanged?(false)
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        onClicked?()
    }
}

@MainActor
final class LockScreenFaceIDWindow: NSPanel {
    static let shared = LockScreenFaceIDWindow()
    
    private var isSkyLightAttached = false
    
    private init() {
        let initialRect = NSRect(x: 0, y: 0, width: 320, height: 240)
        super.init(
            contentRect: initialRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        configureWindow()
    }
    
    private func configureWindow() {
        isFloatingPanel = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        // Ensure FaceID is always above everything else, including lock screen and fullscreen media
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 4)
        acceptsMouseMovedEvents = true
        ignoresMouseEvents = false
        
        collectionBehavior = [
            .fullScreenAuxiliary,
            .stationary,
            .canJoinAllSpaces,
            .ignoresCycle
        ]
    }
    
    func show() {
        // Target specifically the screen where NotchPulse displays the notch
        let preferredUUID = NotchPulseViewCoordinator.shared.preferredScreenUUID
        let selectedUUID = NotchPulseViewCoordinator.shared.selectedScreenUUID
        let screen: NSScreen? = (preferredUUID.flatMap { NSScreen.screen(withUUID: $0) })
            ?? NSScreen.screen(withUUID: selectedUUID)
            ?? NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 || $0.auxiliaryTopLeftArea != nil })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        
        guard let screen = screen else { return }
        
        let hasPhysicalNotch = screen.safeAreaInsets.top > 0 || screen.auxiliaryTopLeftArea != nil
        let closedSize = getClosedNotchSize(screenUUID: screen.displayUUID)
        let notchHardwareHeight: CGFloat = (screen.safeAreaInsets.top > 0 ? screen.safeAreaInsets.top : (hasPhysicalNotch ? 32 : 34))
        let notchStyle = Defaults[.notchStyle]
        let dynamicIslandTopOffset = Defaults[.dynamicIslandTopOffset]
        
        let windowWidth: CGFloat = 340
        let windowHeight: CGFloat = 240
        let y: CGFloat
        
        if hasPhysicalNotch {
            y = screen.frame.origin.y + screen.frame.height - windowHeight
        } else {
            if notchStyle == .dynamicIsland {
                y = screen.frame.origin.y + screen.frame.height - windowHeight - dynamicIslandTopOffset
            } else {
                y = screen.frame.origin.y + screen.frame.height - windowHeight
            }
        }
        
        let x = screen.frame.origin.x + (screen.frame.width - windowWidth) / 2
        
        let trackingHostingView = LockScreenTrackingHostingView(rootView: LockScreenFaceIDPillView(
            hasPhysicalNotch: hasPhysicalNotch,
            notchHardwareHeight: notchHardwareHeight,
            physicalNotchWidth: closedSize.width,
            notchStyle: notchStyle
        ))
        trackingHostingView.wantsLayer = true
        trackingHostingView.layer?.backgroundColor = NSColor.clear.cgColor
        trackingHostingView.onHoverChanged = { hovering in
            if hovering {
                if !FaceIDManager.shared.isScanning {
                    FaceIDManager.shared.startRecognitionOnWake()
                }
            }
        }
        trackingHostingView.onClicked = {
            if !FaceIDManager.shared.isScanning {
                FaceIDManager.shared.startRecognitionOnWake()
            }
        }
        contentView = trackingHostingView
        
        setFrame(NSRect(x: x, y: y, width: windowWidth, height: windowHeight), display: true)
        
        if !isSkyLightAttached {
            SkyLightOperator.shared.delegateWindow(self)
            isSkyLightAttached = true
        }
        
        if isVisible && alphaValue > 0.95 {
            orderFrontRegardless()
            return
        }
        
        alphaValue = 0
        orderFrontRegardless()
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1.0
        }
    }
    
    func hide() {
        guard isVisible else { return }
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().alphaValue = 0.0
        }, completionHandler: {
            self.orderOut(nil)
            if self.isSkyLightAttached {
                SkyLightOperator.shared.undelegateWindow(self)
                self.isSkyLightAttached = false
            }
        })
    }
    
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Lock Screen Face ID Large Drop-Down Notch View
struct LockScreenFaceIDPillView: View {
    @ObservedObject var faceIDManager = FaceIDManager.shared
    var hasPhysicalNotch: Bool = true
    var notchHardwareHeight: CGFloat = 38
    var physicalNotchWidth: CGFloat = 185
    var notchStyle: NotchStyle = .notch
    
    @State private var isHovered: Bool = false
    @State private var isScanPulseDimmed: Bool = false
    
    private var isExpanded: Bool {
        isHovered || faceIDManager.isScanning || faceIDManager.lastUnlockSuccess
    }
    
    private var scanMedia: ScanMedia {
        if faceIDManager.lastUnlockSuccess {
            return .success
        } else if faceIDManager.statusMessage == "Face Not Recognized" {
            return .failure
        } else {
            return .idle
        }
    }
    
    // Closed & Open Dimensions matching Glance architecture
    private var closedBodySize: CGSize {
        if hasPhysicalNotch {
            return CGSize(width: physicalNotchWidth, height: notchHardwareHeight)
        } else {
            return CGSize(width: 80, height: 24)
        }
    }
    
    private var openBodySize: CGSize {
        if hasPhysicalNotch {
            return CGSize(width: 220, height: 200)
        } else {
            return CGSize(width: 180, height: 180)
        }
    }
    
    private var topRadius: CGFloat {
        if isExpanded {
            return hasPhysicalNotch ? 16 : 48
        } else {
            return hasPhysicalNotch ? 6 : (closedBodySize.height / 2)
        }
    }
    
    private var bottomRadius: CGFloat {
        if isExpanded {
            return hasPhysicalNotch ? 60 : 48
        } else {
            return hasPhysicalNotch ? 12 : (closedBodySize.height / 2)
        }
    }
    
    private var currentSize: CGSize {
        let body = isExpanded ? openBodySize : closedBodySize
        let flare: CGFloat = hasPhysicalNotch ? (topRadius * 2) : 0
        return CGSize(width: body.width + flare, height: body.height)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Button {
                triggerScan()
            } label: {
                applyNotchClip(
                    ZStack(alignment: .top) {
                        ScanAnimationView(media: scanMedia)
                            .padding(.top, hasPhysicalNotch ? 40 : 28)
                            .padding(.horizontal, hasPhysicalNotch ? 32 : 24)
                            .padding(.bottom, 24)
                            .scaleEffect(faceIDManager.isScanning && isScanPulseDimmed ? 0.97 : 1.0)
                            .opacity(faceIDManager.isScanning && isScanPulseDimmed ? 0.70 : 1.0)
                            .blur(radius: isExpanded ? 0 : 30)
                            .opacity(isExpanded ? 1.0 : 0.0)
                            .scaleEffect(isExpanded ? 1.0 : 0.3)
                    }
                    .frame(width: currentSize.width, height: currentSize.height)
                    .background(Color.black)
                )
                .overlay(
                    Group {
                        if !hasPhysicalNotch && notchStyle == .dynamicIsland {
                            RoundedRectangle(cornerRadius: bottomRadius, style: .continuous)
                                .stroke(
                                    faceIDManager.lastUnlockSuccess ? Color.green.opacity(0.8) : Color.blue.opacity(isHovered ? 0.8 : 0.4),
                                    lineWidth: isHovered ? 1.5 : 1.0
                                )
                        }
                    }
                )
                .shadow(
                    color: Color.black.opacity(isExpanded ? (isHovered ? 0.65 : 0.45) : 0),
                    radius: 12,
                    y: 6
                )
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(.spring(response: 0.45, dampingFraction: hovering ? 0.70 : 1.0)) {
                    self.isHovered = hovering
                }
                if hovering {
                    triggerScan()
                }
            }
            
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.45, dampingFraction: isExpanded ? 0.70 : 1.0), value: isExpanded)
        .animation(.spring(response: 0.45, dampingFraction: 0.75), value: isHovered)
        .animation(.spring(response: 0.45, dampingFraction: 0.70), value: faceIDManager.isScanning)
        .animation(.spring(response: 0.45, dampingFraction: 0.70), value: faceIDManager.lastUnlockSuccess)
        .onChange(of: faceIDManager.isScanning) { _, scanning in
            if scanning {
                startBreathingPulse()
            } else {
                isScanPulseDimmed = false
            }
        }
    }
    
    @ViewBuilder
    private func applyNotchClip<V: View>(_ content: V) -> some View {
        if hasPhysicalNotch {
            content.clipShape(NotchShape(topCornerRadius: topRadius, bottomCornerRadius: bottomRadius))
        } else if notchStyle == .dynamicIsland {
            content.clipShape(RoundedRectangle(cornerRadius: bottomRadius, style: .continuous))
        } else {
            content.clipShape(NotchShape(topCornerRadius: topRadius, bottomCornerRadius: bottomRadius))
        }
    }
    
    private func triggerScan() {
        if !faceIDManager.isScanning {
            faceIDManager.startRecognitionOnWake()
        }
    }
    
    private func startBreathingPulse() {
        withAnimation(
            .easeInOut(duration: 0.5)
            .repeatForever(autoreverses: true)
        ) {
            isScanPulseDimmed = true
        }
    }
}
