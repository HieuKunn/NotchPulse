//
//  LockScreenFaceIDWindow.swift
//  NotchPulse
//
//  Created for NotchPulse v2.0 - Lock Screen Face ID Notch Indicator
//

import Cocoa
import Combine
import Defaults
import SkyLightWindow
import SwiftUI

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
        level = .screenSaver
        appearance = NSAppearance(named: .darkAqua)
        
        collectionBehavior = [
            .fullScreenAuxiliary,
            .stationary,
            .canJoinAllSpaces,
            .ignoresCycle
        ]
        
        contentView = NSHostingView(rootView: LockScreenFaceIDPillView())
    }
    
    func show() {
        // Target specifically the screen where NotchPulse displays the notch
        let screen: NSScreen? = NSScreen.screen(withUUID: NotchPulseViewCoordinator.shared.selectedScreenUUID)
            ?? NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        
        guard let screen = screen else { return }
        
        let hasPhysicalNotch = screen.safeAreaInsets.top > 0
        let closedSize = getClosedNotchSize(screenUUID: NotchPulseViewCoordinator.shared.selectedScreenUUID)
        let width: CGFloat = max(185, closedSize.width)
        
        // When on a Mac with physical notch:
        // The window starts from the very top bezel of the Mac, covering the physical notch
        // and extending 48px downward as a single unified shape.
        // When on an external monitor (no notch):
        // The notch doesn't have a camera bezel, so its height is compact (44px) attached to the top edge.
        let notchHardwareHeight: CGFloat = hasPhysicalNotch ? screen.safeAreaInsets.top : 0
        let totalHeight: CGFloat = hasPhysicalNotch ? (notchHardwareHeight + 48) : 44
        
        let x = screen.frame.origin.x + (screen.frame.width - width) / 2
        let y = screen.frame.origin.y + screen.frame.height - totalHeight
        
        contentView = NSHostingView(rootView: LockScreenFaceIDPillView(
            hasPhysicalNotch: hasPhysicalNotch,
            notchHardwareHeight: notchHardwareHeight
        ))
        
        setFrame(NSRect(x: x, y: y, width: width, height: totalHeight), display: true)
        
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
            
            let eyeW = max(2.5, w * 0.08)
            let eyeH = max(6.0, h * 0.19)
            
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
    var size: CGFloat = 28
    
    @State private var swivelY: Double = -18
    @State private var swivelX: Double = -5
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
                .strokeBorder(appleGreen.opacity(shockwaveOpacity), lineWidth: 2.5)
                .frame(width: size * 1.6, height: size * 1.6)
                .scaleEffect(shockwaveScale)
            
            if isSuccess {
                // Success State: Unlocked Padlock in vibrant Apple Green with pop
                Image(systemName: "lock.open.fill")
                    .font(.system(size: size * 0.95, weight: .bold))
                    .foregroundStyle(appleGreen)
                    .shadow(color: appleGreen.opacity(0.85), radius: 8, x: 0, y: 0)
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
                    AppleFaceIDCornerBrackets(color: glyphColor, lineWidth: max(2.2, size * 0.09))
                        .frame(width: size, height: size)
                        .scaleEffect(bracketPulse)
                    
                    // Inner Face (Eyes, Nose, Mouth) with 3D perspective swivel
                    AppleFaceIDFeatures(color: glyphColor, lineWidth: max(2.2, size * 0.09))
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
                            x: isScanning ? CGFloat(swivelY * 0.16) : 0,
                            y: isScanning ? CGFloat(swivelX * 0.16) : 0
                        )
                }
                .shadow(color: glyphColor.opacity(isScanning ? 0.65 : 0.2), radius: 6, x: 0, y: 0)
                .offset(x: shakeOffset)
            }
        }
        .frame(width: size * 1.4, height: size * 1.4)
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
            .easeInOut(duration: 1.1)
            .repeatForever(autoreverses: true)
        ) {
            swivelY = 18
            swivelX = 6
        }
        withAnimation(
            .easeInOut(duration: 1.8)
            .repeatForever(autoreverses: true)
        ) {
            bracketPulse = 1.04
        }
    }
    
    private func triggerSuccessAnimation() {
        shockwaveScale = 0.8
        shockwaveOpacity = 0.95
        withAnimation(.easeOut(duration: 0.5)) {
            shockwaveScale = 1.9
            shockwaveOpacity = 0.0
        }
        
        successPop = 0.65
        withAnimation(.spring(response: 0.35, dampingFraction: 0.52, blendDuration: 0)) {
            successPop = 1.0
        }
    }
    
    private func triggerShakeAnimation() {
        let offsets: [CGFloat] = [0, -8, 8, -6, 6, -3, 3, 0]
        for (index, offset) in offsets.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.04) {
                withAnimation(.linear(duration: 0.04)) {
                    self.shakeOffset = offset
                }
            }
        }
    }
}

struct FaceIDExtensionShape: Shape {
    var cornerRadius: CGFloat
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerRadius))
        path.addArc(center: CGPoint(x: rect.maxX - cornerRadius, y: rect.maxY - cornerRadius), radius: cornerRadius, startAngle: Angle(degrees: 0), endAngle: Angle(degrees: 90), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX + cornerRadius, y: rect.maxY))
        path.addArc(center: CGPoint(x: rect.minX + cornerRadius, y: rect.maxY - cornerRadius), radius: cornerRadius, startAngle: Angle(degrees: 90), endAngle: Angle(degrees: 180), clockwise: false)
        path.closeSubpath()
        return path
    }
}

struct FaceIDExtensionStrokeShape: Shape {
    var cornerRadius: CGFloat
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        // Start from top-right, go down, curve bottom-right, go left, curve bottom-left, go up to top-left
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerRadius))
        path.addArc(center: CGPoint(x: rect.maxX - cornerRadius, y: rect.maxY - cornerRadius), radius: cornerRadius, startAngle: Angle(degrees: 0), endAngle: Angle(degrees: 90), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX + cornerRadius, y: rect.maxY))
        path.addArc(center: CGPoint(x: rect.minX + cornerRadius, y: rect.maxY - cornerRadius), radius: cornerRadius, startAngle: Angle(degrees: 90), endAngle: Angle(degrees: 180), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        return path
    }
}

// MARK: - Lock Screen Face ID Pill View
struct LockScreenFaceIDPillView: View {
    @ObservedObject var faceIDManager = FaceIDManager.shared
    var hasPhysicalNotch: Bool = true
    var notchHardwareHeight: CGFloat = 38
    
    private let appleBlue = Color(red: 0.04, green: 0.52, blue: 1.0)
    private let appleGreen = Color(red: 0.188, green: 0.855, blue: 0.376)
    
    var body: some View {
        Button {
            if !faceIDManager.isScanning && !faceIDManager.lastUnlockSuccess {
                faceIDManager.startRecognitionOnWake()
            }
        } label: {
            VStack(spacing: 0) {
                if hasPhysicalNotch {
                    // Sits under physical camera bezel area
                    Spacer().frame(height: notchHardwareHeight)
                }
                
                VStack {
                    Spacer(minLength: 2)
                    AppleFaceIDGlyphView(
                        isScanning: faceIDManager.isScanning,
                        isSuccess: faceIDManager.lastUnlockSuccess,
                        isFailure: !faceIDManager.isScanning && !faceIDManager.lastUnlockSuccess && faceIDManager.statusMessage == "Face Not Recognized",
                        size: hasPhysicalNotch ? 32 : 26
                    )
                    Spacer(minLength: 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                ZStack {
                    FaceIDExtensionShape(cornerRadius: hasPhysicalNotch ? 20 : 14)
                        .fill(Color.black)
                    
                    FaceIDExtensionStrokeShape(cornerRadius: hasPhysicalNotch ? 20 : 14)
                        .stroke(borderColor, lineWidth: 1.5)
                }
            )
            .shadow(color: .black.opacity(0.6), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var borderColor: Color {
        if faceIDManager.lastUnlockSuccess {
            return appleGreen.opacity(0.85)
        } else if faceIDManager.isScanning {
            return appleBlue.opacity(0.75)
        } else {
            return .orange.opacity(0.5)
        }
    }
}
