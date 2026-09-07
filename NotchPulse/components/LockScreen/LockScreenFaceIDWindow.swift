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
        let screen: NSScreen? = NSScreen.screen(withUUID: NotchPulseViewCoordinator.shared.selectedScreenUUID)
            ?? NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        
        guard let screen = screen else { return }
        
        let hasPhysicalNotch = screen.safeAreaInsets.top > 0
        let closedSize = getClosedNotchSize(screenUUID: NotchPulseViewCoordinator.shared.selectedScreenUUID)
        let displayStyle = Defaults[.faceIDDisplayStyle]
        
        let notchHardwareHeight: CGFloat = hasPhysicalNotch ? screen.safeAreaInsets.top : 34
        
        let width: CGFloat
        let totalHeight: CGFloat
        
        switch displayStyle {
        case .popDown:
            width = max(185, closedSize.width + 10)
            totalHeight = hasPhysicalNotch ? (notchHardwareHeight + 26) : 38
        case .inline:
            if hasPhysicalNotch {
                let sideItemSize = max(22, notchHardwareHeight - 12)
                width = closedSize.width + (2 * sideItemSize + 20)
                totalHeight = notchHardwareHeight
            } else {
                width = 210
                totalHeight = 34
            }
        }
        
        let x = screen.frame.origin.x + (screen.frame.width - width) / 2
        let y = screen.frame.origin.y + screen.frame.height - totalHeight
        
        let trackingHostingView = LockScreenTrackingHostingView(rootView: LockScreenFaceIDPillView(
            hasPhysicalNotch: hasPhysicalNotch,
            notchHardwareHeight: notchHardwareHeight,
            physicalNotchWidth: closedSize.width,
            displayStyle: displayStyle
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

// MARK: - Authentic Apple MacBook Notch Shape with Top Concave Ears & Smooth Rounded Bottom Fillets
struct FaceIDNotchShape: Shape {
    var topCornerRadius: CGFloat = 6
    var bottomCornerRadius: CGFloat = 14
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        // Start top-left outer bezel
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        
        // Top-left concave flare into notch
        path.addArc(
            tangent1End: CGPoint(x: rect.minX + topCornerRadius, y: rect.minY),
            tangent2End: CGPoint(x: rect.minX + topCornerRadius, y: rect.minY + topCornerRadius),
            radius: topCornerRadius
        )
        
        // Left vertical edge down to bottom curve
        path.addLine(to: CGPoint(x: rect.minX + topCornerRadius, y: rect.maxY - bottomCornerRadius))
        
        // Bottom-left smooth circular fillet
        path.addArc(
            tangent1End: CGPoint(x: rect.minX + topCornerRadius, y: rect.maxY),
            tangent2End: CGPoint(x: rect.midX, y: rect.maxY),
            radius: bottomCornerRadius
        )
        
        // Bottom horizontal edge
        path.addLine(to: CGPoint(x: rect.maxX - topCornerRadius - bottomCornerRadius, y: rect.maxY))
        
        // Bottom-right smooth circular fillet
        path.addArc(
            tangent1End: CGPoint(x: rect.maxX - topCornerRadius, y: rect.maxY),
            tangent2End: CGPoint(x: rect.maxX - topCornerRadius, y: rect.minY),
            radius: bottomCornerRadius
        )
        
        // Right vertical edge up to top curve
        path.addLine(to: CGPoint(x: rect.maxX - topCornerRadius, y: rect.minY + topCornerRadius))
        
        // Top-right concave flare out to bezel
        path.addArc(
            tangent1End: CGPoint(x: rect.maxX - topCornerRadius, y: rect.minY),
            tangent2End: CGPoint(x: rect.maxX, y: rect.minY),
            radius: topCornerRadius
        )
        
        path.closeSubpath()
        return path
    }
}

struct FaceIDNotchStrokeShape: Shape {
    var topCornerRadius: CGFloat = 6
    var bottomCornerRadius: CGFloat = 14
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        // Top-left ear down through bottom to top-right ear (leaving top edge flush with bezel)
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addArc(
            tangent1End: CGPoint(x: rect.minX + topCornerRadius, y: rect.minY),
            tangent2End: CGPoint(x: rect.minX + topCornerRadius, y: rect.minY + topCornerRadius),
            radius: topCornerRadius
        )
        path.addLine(to: CGPoint(x: rect.minX + topCornerRadius, y: rect.maxY - bottomCornerRadius))
        path.addArc(
            tangent1End: CGPoint(x: rect.minX + topCornerRadius, y: rect.maxY),
            tangent2End: CGPoint(x: rect.midX, y: rect.maxY),
            radius: bottomCornerRadius
        )
        path.addLine(to: CGPoint(x: rect.maxX - topCornerRadius - bottomCornerRadius, y: rect.maxY))
        path.addArc(
            tangent1End: CGPoint(x: rect.maxX - topCornerRadius, y: rect.maxY),
            tangent2End: CGPoint(x: rect.maxX - topCornerRadius, y: rect.minY),
            radius: bottomCornerRadius
        )
        path.addLine(to: CGPoint(x: rect.maxX - topCornerRadius, y: rect.minY + topCornerRadius))
        path.addArc(
            tangent1End: CGPoint(x: rect.maxX - topCornerRadius, y: rect.minY),
            tangent2End: CGPoint(x: rect.maxX, y: rect.minY),
            radius: topCornerRadius
        )
        return path
    }
}

// MARK: - Mini Scanning Pulsing Dots View
struct FaceIDScanningDotsView: View {
    var color: Color
    @State private var phase: Int = 0
    let timer = Timer.publish(every: 0.22, on: .main, in: .common).autoconnect()
    
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(color)
                    .frame(width: 3.5, height: 3.5)
                    .opacity(phase == i ? 1.0 : 0.3)
                    .scaleEffect(phase == i ? 1.25 : 0.85)
                    .animation(.easeInOut(duration: 0.2), value: phase)
            }
        }
        .onReceive(timer) { _ in
            phase = (phase + 1) % 3
        }
    }
}

// MARK: - Lock Screen Face ID Pill View
struct LockScreenFaceIDPillView: View {
    @ObservedObject var faceIDManager = FaceIDManager.shared
    var hasPhysicalNotch: Bool = true
    var notchHardwareHeight: CGFloat = 38
    var physicalNotchWidth: CGFloat = 185
    var displayStyle: FaceIDDisplayStyle = Defaults[.faceIDDisplayStyle]
    
    @State private var isHovered: Bool = false
    
    private let appleBlue = Color(red: 0.04, green: 0.52, blue: 1.0)
    private let appleGreen = Color(red: 0.188, green: 0.855, blue: 0.376)
    
    var body: some View {
        Button {
            triggerScan()
        } label: {
            Group {
                if displayStyle == .inline {
                    inlineContent
                } else {
                    popDownContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(backgroundShape)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                self.isHovered = hovering
            }
            if hovering {
                triggerScan()
            }
        }
    }
    
    // MARK: - Pop-down Layout (Mở rộng ngắn, tinh tế, thanh thoát dưới notch)
    private var popDownContent: some View {
        VStack(spacing: 0) {
            if hasPhysicalNotch {
                // Sits under physical camera bezel area
                Spacer().frame(height: notchHardwareHeight)
            }
            
            VStack(spacing: 1.5) {
                Spacer(minLength: 1)
                AppleFaceIDGlyphView(
                    isScanning: faceIDManager.isScanning,
                    isSuccess: faceIDManager.lastUnlockSuccess,
                    isFailure: !faceIDManager.isScanning && !faceIDManager.lastUnlockSuccess && faceIDManager.statusMessage == "Face Not Recognized",
                    size: 18
                )
                
                Text(statusDisplayText)
                    .font(.system(size: 8.5, weight: .medium, design: .rounded))
                    .foregroundColor(statusDisplayColor)
                    .lineLimit(1)
                    .padding(.bottom, 2)
                Spacer(minLength: 1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    // MARK: - Inline Layout (Mở rộng sang 2 bên như Media khi ở màn Mac có Notch thật)
    @ViewBuilder
    private var inlineContent: some View {
        if hasPhysicalNotch {
            // Màn Mac có notch: 2 bên tai mở rộng giống hệt ô Album Art & Waveform của Media
            let sideWidth = max(28, notchHardwareHeight - 4)
            HStack(spacing: 0) {
                // Ô bên trái: Biểu tượng Face ID nhỏ nhắn, cân đối
                ZStack {
                    AppleFaceIDGlyphView(
                        isScanning: faceIDManager.isScanning,
                        isSuccess: faceIDManager.lastUnlockSuccess,
                        isFailure: !faceIDManager.isScanning && !faceIDManager.lastUnlockSuccess && faceIDManager.statusMessage == "Face Not Recognized",
                        size: 17
                    )
                }
                .frame(width: sideWidth, height: notchHardwareHeight)
                
                // Khoảng đen ở giữa: Khớp hoàn toàn với phần notch nhựa/camera vật lý
                Spacer(minLength: max(40, physicalNotchWidth - 8))
                
                // Ô bên phải: Trạng thái mở khoá (chấm quét / ổ khoá xanh lá mở khi thành công)
                ZStack {
                    if faceIDManager.lastUnlockSuccess {
                        Image(systemName: "lock.open.fill")
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundStyle(appleGreen)
                            .shadow(color: appleGreen.opacity(0.85), radius: 5)
                            .transition(.scale.combined(with: .opacity))
                    } else if faceIDManager.isScanning {
                        FaceIDScanningDotsView(color: appleBlue)
                            .transition(.opacity)
                    } else if faceIDManager.statusMessage == "Face Not Recognized" {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.orange)
                    } else {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(Color.white.opacity(isHovered ? 0.8 : 0.35))
                    }
                }
                .frame(width: sideWidth, height: notchHardwareHeight)
            }
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // Màn hình ngoài không có notch: dạng thanh pill thanh lịch ở giữa
            HStack(spacing: 8) {
                AppleFaceIDGlyphView(
                    isScanning: faceIDManager.isScanning,
                    isSuccess: faceIDManager.lastUnlockSuccess,
                    isFailure: !faceIDManager.isScanning && !faceIDManager.lastUnlockSuccess && faceIDManager.statusMessage == "Face Not Recognized",
                    size: 17
                )
                
                Text(statusDisplayText)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(statusDisplayColor)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    @ViewBuilder
    private var backgroundShape: some View {
        let topRadius: CGFloat = 6
        let bottomRadius: CGFloat = 14
        
        ZStack {
            FaceIDNotchShape(topCornerRadius: topRadius, bottomCornerRadius: bottomRadius)
                .fill(Color.black)
            
            FaceIDNotchStrokeShape(topCornerRadius: topRadius, bottomCornerRadius: bottomRadius)
                .stroke(borderColor, lineWidth: isHovered ? 1.8 : 1.2)
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
            return isHovered ? "Nhấp quét" : "Face ID"
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
