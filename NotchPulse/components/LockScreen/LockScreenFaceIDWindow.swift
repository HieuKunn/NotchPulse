//
//  LockScreenFaceIDWindow.swift
//  NotchPulse
//
//  Created for NotchPulse - Lock Screen Face ID Notch Indicator
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
        let initialRect = NSRect(x: 0, y: 0, width: 230, height: 44)
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
        // Ensure FaceID is always above everything else, including fullscreen media
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
        
        let width: CGFloat
        let totalHeight: CGFloat
        let y: CGFloat
        
        if hasPhysicalNotch {
            let maxExpandedWidth = closedSize.width + 80
            let maxExpandedHeight = notchHardwareHeight + 36
            width = max(260, maxExpandedWidth)
            totalHeight = maxExpandedHeight
            y = screen.frame.origin.y + screen.frame.height - totalHeight
        } else {
            width = 260
            totalHeight = 60
            if notchStyle == .dynamicIsland {
                y = screen.frame.origin.y + screen.frame.height - totalHeight - dynamicIslandTopOffset
            } else {
                y = screen.frame.origin.y + screen.frame.height - totalHeight
            }
        }
        
        let x = screen.frame.origin.x + (screen.frame.width - width) / 2
        
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
        
        setFrame(NSRect(x: x, y: y, width: width, height: totalHeight), display: true)
        
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

// MARK: - Apple Face ID Corner Brackets (Vector)
struct AppleFaceIDCornerBrackets: View {
    var color: Color
    var lineWidth: CGFloat
    
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let r = w * 0.28
            let arm = w * 0.24
            
            Path { path in
                // Top-Left Corner
                path.move(to: CGPoint(x: 0, y: r + arm))
                path.addLine(to: CGPoint(x: 0, y: r))
                path.addQuadCurve(to: CGPoint(x: r, y: 0), control: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: r + arm, y: 0))
                
                // Top-Right Corner
                path.move(to: CGPoint(x: w - r - arm, y: 0))
                path.addLine(to: CGPoint(x: w - r, y: 0))
                path.addQuadCurve(to: CGPoint(x: w, y: r), control: CGPoint(x: w, y: 0))
                path.addLine(to: CGPoint(x: w, y: r + arm))
                
                // Bottom-Left Corner
                path.move(to: CGPoint(x: 0, y: h - r - arm))
                path.addLine(to: CGPoint(x: 0, y: h - r))
                path.addQuadCurve(to: CGPoint(x: r, y: h), control: CGPoint(x: 0, y: h))
                path.addLine(to: CGPoint(x: r + arm, y: h))
                
                // Bottom-Right Corner
                path.move(to: CGPoint(x: w - r - arm, y: h))
                path.addLine(to: CGPoint(x: w - r, y: h))
                path.addQuadCurve(to: CGPoint(x: w, y: h - r), control: CGPoint(x: w, y: h))
                path.addLine(to: CGPoint(x: w, y: h - r - arm))
            }
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Apple Face ID Inner Features (Eyes, J-Nose, Smile)
struct AppleFaceIDFeatures: View {
    var color: Color
    var lineWidth: CGFloat
    
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            
            let eyeW = max(2.0, w * 0.08)
            let eyeH = max(4.5, h * 0.19)
            
            ZStack {
                // Left Eye (Vertical capsule)
                Capsule()
                    .fill(color)
                    .frame(width: eyeW, height: eyeH)
                    .position(x: w * 0.38, y: h * 0.44)
                
                // Right Eye (Vertical capsule)
                Capsule()
                    .fill(color)
                    .frame(width: eyeW, height: eyeH)
                    .position(x: w * 0.62, y: h * 0.44)
                
                // J-Nose: vertical line curving to the left
                Path { path in
                    path.move(to: CGPoint(x: w * 0.50, y: h * 0.42))
                    path.addLine(to: CGPoint(x: w * 0.50, y: h * 0.56))
                    path.addQuadCurve(
                        to: CGPoint(x: w * 0.44, y: h * 0.58),
                        control: CGPoint(x: w * 0.50, y: h * 0.59)
                    )
                }
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                
                // Mouth: Signature sweet curved smile
                Path { path in
                    path.move(to: CGPoint(x: w * 0.38, y: h * 0.69))
                    path.addQuadCurve(
                        to: CGPoint(x: w * 0.62, y: h * 0.69),
                        control: CGPoint(x: w * 0.50, y: h * 0.77)
                    )
                }
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

// MARK: - Apple 3D Face ID Swivel & Green Unlocking Lock Glyph
struct AppleFaceIDGlyphView: View {
    var isScanning: Bool
    var isSuccess: Bool
    var isFailure: Bool = false
    var size: CGFloat = 20
    
    @State private var swivelY: Double = -16
    @State private var swivelX: Double = -4
    @State private var shockwaveScale: CGFloat = 0.8
    @State private var shockwaveOpacity: Double = 0.0
    @State private var successPop: CGFloat = 1.0
    @State private var shakeOffset: CGFloat = 0
    @State private var bracketPulse: CGFloat = 1.0
    
    // Apple Electric Blue (#0A84FF)
    private let appleBlue = Color(red: 0.04, green: 0.52, blue: 1.0)
    // Apple Vibrant Neon Green (#30D158)
    private let appleGreen = Color(red: 0.188, green: 0.855, blue: 0.376)
    
    var body: some View {
        ZStack {
            // Radiant Shockwave Glow Ring upon unlock
            Circle()
                .strokeBorder(appleBlue.opacity(shockwaveOpacity), lineWidth: 2.0)
                .frame(width: size * 1.5, height: size * 1.5)
                .scaleEffect(shockwaveScale)
            
            if isSuccess {
                // Success State: Unlocked Padlock in vibrant Apple Blue/Green with pop
                Image(systemName: "lock.open.fill")
                    .font(.system(size: size * 0.95, weight: .bold))
                    .foregroundStyle(appleBlue)
                    .shadow(color: appleBlue.opacity(0.85), radius: 6, x: 0, y: 0)
                    .scaleEffect(successPop)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.5).combined(with: .opacity),
                        removal: .opacity
                    ))
            } else {
                // Scanning / Idle State: Authentic Vector Face ID with 3D Swivel
                let glyphColor: Color = isFailure ? Color.orange : appleBlue
                
                ZStack {
                    // Outer 4 Corner Brackets
                    AppleFaceIDCornerBrackets(color: glyphColor, lineWidth: max(1.8, size * 0.09))
                        .frame(width: size, height: size)
                        .scaleEffect(bracketPulse)
                    
                    // Inner Face (Eyes, Nose, Mouth) with 3D perspective swivel
                    AppleFaceIDFeatures(color: glyphColor, lineWidth: max(1.8, size * 0.09))
                        .frame(width: size, height: size)
                        .rotation3DEffect(
                            .degrees(isScanning ? swivelY : 0),
                            axis: (x: 0.0, y: 1.0, z: 0.0),
                            perspective: 0.35
                        )
                        .rotation3DEffect(
                            .degrees(isScanning ? swivelX : 0),
                            axis: (x: 1.0, y: 0.0, z: 0.0),
                            perspective: 0.35
                        )
                        .offset(
                            x: isScanning ? CGFloat(swivelY * 0.14) : 0,
                            y: isScanning ? CGFloat(swivelX * 0.14) : 0
                        )
                }
                .shadow(color: glyphColor.opacity(isScanning ? 0.65 : 0.2), radius: 5, x: 0, y: 0)
                .offset(x: shakeOffset)
            }
        }
        .frame(width: size * 1.3, height: size * 1.3)
        .onAppear {
            if isScanning {
                startSwivelAnimation()
            }
        }
        .onChange(of: isScanning) { _, scanning in
            if scanning {
                startSwivelAnimation()
            }
        }
        .onChange(of: isSuccess) { _, success in
            if success {
                triggerSuccessAnimation()
            }
        }
        .onChange(of: isFailure) { _, failure in
            if failure {
                triggerShakeAnimation()
            }
        }
    }
    
    private func startSwivelAnimation() {
        withAnimation(
            .easeInOut(duration: 1.0)
            .repeatForever(autoreverses: true)
        ) {
            swivelY = 16
            swivelX = 5
        }
        withAnimation(
            .easeInOut(duration: 1.6)
            .repeatForever(autoreverses: true)
        ) {
            bracketPulse = 1.04
        }
    }
    
    private func triggerSuccessAnimation() {
        shockwaveScale = 0.8
        shockwaveOpacity = 0.95
        withAnimation(.easeOut(duration: 0.45)) {
            shockwaveScale = 1.8
            shockwaveOpacity = 0.0
        }
        
        successPop = 0.65
        withAnimation(.spring(response: 0.35, dampingFraction: 0.52, blendDuration: 0)) {
            successPop = 1.0
        }
    }
    
    private func triggerShakeAnimation() {
        let offsets: [CGFloat] = [0, -7, 7, -5, 5, -2, 2, 0]
        for (index, offset) in offsets.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.04) {
                withAnimation(.linear(duration: 0.04)) {
                    self.shakeOffset = offset
                }
            }
        }
    }
}

// MARK: - Lock Screen Face ID Notch Drop-Down View
struct LockScreenFaceIDPillView: View {
    @ObservedObject var faceIDManager = FaceIDManager.shared
    var hasPhysicalNotch: Bool = true
    var notchHardwareHeight: CGFloat = 38
    var physicalNotchWidth: CGFloat = 185
    var notchStyle: NotchStyle = .notch
    
    @State private var isHovered: Bool = false
    
    private let appleBlue = Color(red: 0.04, green: 0.52, blue: 1.0)
    private let appleGreen = Color(red: 0.188, green: 0.855, blue: 0.376)
    
    private var isExpanded: Bool {
        isHovered || faceIDManager.isScanning || faceIDManager.lastUnlockSuccess
    }
    
    private var currentBodyWidth: CGFloat {
        if hasPhysicalNotch {
            return isExpanded ? (physicalNotchWidth + 56) : physicalNotchWidth
        } else {
            return isExpanded ? 210 : 150
        }
    }
    
    private var currentBodyHeight: CGFloat {
        if hasPhysicalNotch {
            return isExpanded ? (notchHardwareHeight + 24) : notchHardwareHeight
        } else {
            return isExpanded ? 46 : 30
        }
    }
    
    private var topRadius: CGFloat { 6 }
    private var bottomRadius: CGFloat { isExpanded ? (hasPhysicalNotch ? 20 : 23) : (hasPhysicalNotch ? 12 : 15) }
    
    var body: some View {
        VStack(spacing: 0) {
            Button {
                triggerScan()
            } label: {
                ZStack(alignment: .top) {
                    // Background notch drop-down silhouette
                    backgroundShape
                    
                    // Dropped Chin Content (Centered 3D Face ID / Unlock Glyph directly below camera cutout)
                    VStack(spacing: 0) {
                        if hasPhysicalNotch {
                            // Clear spacer exactly matching hardware notch camera cutout height
                            Spacer()
                                .frame(height: max(0, notchHardwareHeight - 12))
                        }
                        
                        // Centered 3D Face ID Glyph in the dropped chin
                        HStack(spacing: 6) {
                            AppleFaceIDGlyphView(
                                isScanning: faceIDManager.isScanning,
                                isSuccess: faceIDManager.lastUnlockSuccess,
                                isFailure: !faceIDManager.isScanning && !faceIDManager.lastUnlockSuccess && faceIDManager.statusMessage == "Face Not Recognized",
                                size: hasPhysicalNotch ? 18 : 17
                            )
                            
                            if !hasPhysicalNotch && isExpanded {
                                Text(statusDisplayText)
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundColor(statusDisplayColor)
                                    .lineLimit(1)
                                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: hasPhysicalNotch ? 30 : nil)
                        .opacity(isExpanded ? 1.0 : 0.0)
                        .scaleEffect(isExpanded ? 1.0 : 0.5)
                        .blur(radius: isExpanded ? 0 : 4)
                        
                        if !hasPhysicalNotch {
                            Spacer(minLength: 0)
                        }
                    }
                    .frame(width: currentBodyWidth, height: currentBodyHeight)
                }
                .frame(width: currentBodyWidth, height: currentBodyHeight)
                .shadow(color: Color.black.opacity(isExpanded ? (isHovered ? 0.6 : 0.4) : 0), radius: 10, y: 4)
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                    self.isHovered = hovering
                }
                if hovering {
                    triggerScan()
                }
            }
            
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.35, dampingFraction: 0.78), value: isExpanded)
        .animation(.spring(response: 0.35, dampingFraction: 0.78), value: isHovered)
        .animation(.spring(response: 0.35, dampingFraction: 0.78), value: faceIDManager.isScanning)
        .animation(.spring(response: 0.35, dampingFraction: 0.78), value: faceIDManager.lastUnlockSuccess)
    }
    
    @ViewBuilder
    private var backgroundShape: some View {
        if hasPhysicalNotch {
            NotchShape(topCornerRadius: topRadius, bottomCornerRadius: bottomRadius)
                .fill(Color.black)
                .frame(width: currentBodyWidth, height: currentBodyHeight)
        } else {
            if notchStyle == .dynamicIsland {
                RoundedRectangle(cornerRadius: bottomRadius, style: .continuous)
                    .fill(Color.black)
                    .overlay(
                        RoundedRectangle(cornerRadius: bottomRadius, style: .continuous)
                            .stroke(borderColor, lineWidth: isHovered ? 1.8 : 1.0)
                    )
                    .frame(width: currentBodyWidth, height: currentBodyHeight)
            } else {
                NotchShape(topCornerRadius: topRadius, bottomCornerRadius: bottomRadius)
                    .fill(Color.black)
                    .frame(width: currentBodyWidth, height: currentBodyHeight)
            }
        }
    }
    
    private func triggerScan() {
        if !faceIDManager.isScanning {
            faceIDManager.startRecognitionOnWake()
        }
    }
    
    private var statusDisplayText: String {
        if faceIDManager.lastUnlockSuccess {
            return "Đã khớp!"
        } else if faceIDManager.isScanning {
            return "Đang quét…"
        } else if faceIDManager.statusMessage == "Face Not Recognized" {
            return "Chưa khớp"
        } else {
            return "Face ID"
        }
    }
    
    private var statusDisplayColor: Color {
        if faceIDManager.lastUnlockSuccess {
            return appleGreen
        } else if faceIDManager.isScanning {
            return appleBlue
        } else if faceIDManager.statusMessage == "Face Not Recognized" {
            return .orange
        } else {
            return Color.white.opacity(isHovered ? 0.95 : 0.6)
        }
    }
    
    private var borderColor: Color {
        if faceIDManager.lastUnlockSuccess {
            return appleGreen.opacity(0.85)
        } else if faceIDManager.isScanning {
            return appleBlue.opacity(0.75)
        } else if faceIDManager.statusMessage == "Face Not Recognized" {
            return .orange.opacity(isHovered ? 0.9 : 0.6)
        } else {
            return appleBlue.opacity(isHovered ? 0.85 : 0.4)
        }
    }
}
