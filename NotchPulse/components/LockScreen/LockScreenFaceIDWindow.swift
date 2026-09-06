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
        guard let screen = NSScreen.main else { return }
        
        let width: CGFloat = 230
        let height: CGFloat = 44
        
        // Position gracefully directly under the MacBook Notch / top center
        let x = (screen.frame.width - width) / 2 + screen.frame.origin.x
        let y = screen.frame.origin.y + screen.frame.height - height - 12
        
        setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        
        if !isSkyLightAttached {
            SkyLightOperator.shared.delegateWindow(self)
            isSkyLightAttached = true
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

// MARK: - Apple 3D Face ID Swivel & Green Unlocking Lock Glyph
struct AppleFaceIDGlyphView: View {
    var isScanning: Bool
    var isSuccess: Bool
    var isFailure: Bool = false
    var size: CGFloat = 22
    
    @State private var swivelY: Double = -18
    @State private var swivelX: Double = -4
    @State private var shockwaveScale: CGFloat = 0.8
    @State private var shockwaveOpacity: Double = 0.0
    @State private var successPop: CGFloat = 1.0
    @State private var shakeOffset: CGFloat = 0
    
    // Apple vibrant iOS green (#30D158)
    private let appleGreen = Color(red: 0.188, green: 0.855, blue: 0.376)
    
    var body: some View {
        ZStack {
            // Radiant Shockwave Glow Ring upon unlock
            Circle()
                .strokeBorder(appleGreen.opacity(shockwaveOpacity), lineWidth: 2.0)
                .frame(width: size * 1.5, height: size * 1.5)
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
                // Scanning / Idle State: 3D Swiveling Face ID Mesh
                ZStack {
                    Image(systemName: "faceid")
                        .font(.system(size: size, weight: .regular))
                        .foregroundStyle(isFailure ? Color.orange : Color.white)
                        .shadow(
                            color: isFailure ? Color.orange.opacity(0.6) : (isScanning ? Color.cyan.opacity(0.5) : .clear),
                            radius: 6, x: 0, y: 0
                        )
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
                }
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
            .easeInOut(duration: 1.2)
            .repeatForever(autoreverses: true)
        ) {
            swivelY = 18
            swivelX = 4
        }
    }
    
    private func triggerSuccessAnimation() {
        // Shockwave expansion
        shockwaveScale = 0.8
        shockwaveOpacity = 0.95
        withAnimation(.easeOut(duration: 0.5)) {
            shockwaveScale = 1.9
            shockwaveOpacity = 0.0
        }
        
        // Elastic Pop
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

// MARK: - Lock Screen Face ID Pill View
struct LockScreenFaceIDPillView: View {
    @ObservedObject var faceIDManager = FaceIDManager.shared
    
    private let appleGreen = Color(red: 0.188, green: 0.855, blue: 0.376)
    
    var body: some View {
        Button {
            if !faceIDManager.isScanning && !faceIDManager.lastUnlockSuccess {
                faceIDManager.startRecognitionOnWake()
            }
        } label: {
            HStack(spacing: 10) {
                AppleFaceIDGlyphView(
                    isScanning: faceIDManager.isScanning,
                    isSuccess: faceIDManager.lastUnlockSuccess,
                    isFailure: !faceIDManager.isScanning && !faceIDManager.lastUnlockSuccess && faceIDManager.statusMessage == "Face Not Recognized",
                    size: 21
                )
                
                if faceIDManager.lastUnlockSuccess {
                    Text("Đã mở khoá")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(appleGreen)
                        .transition(.scale.combined(with: .opacity))
                } else if faceIDManager.isScanning {
                    Text("Face ID…")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.95))
                } else {
                    Text("Chạm để quét lại")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                ZStack {
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark)
                    
                    Capsule()
                        .fill(Color.black.opacity(0.7))
                    
                    Capsule()
                        .strokeBorder(borderColor, lineWidth: 1.2)
                }
            )
            .shadow(color: .black.opacity(0.4), radius: 12, x: 0, y: 5)
        }
        .buttonStyle(.plain)
    }
    
    private var borderColor: Color {
        if faceIDManager.lastUnlockSuccess {
            return appleGreen.opacity(0.85)
        } else if faceIDManager.isScanning {
            return .cyan.opacity(0.6)
        } else {
            return .orange.opacity(0.5)
        }
    }
}
