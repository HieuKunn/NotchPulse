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
        let initialRect = NSRect(x: 0, y: 0, width: 230, height: 42)
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
        let height: CGFloat = 42
        
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

// MARK: - Lock Screen Face ID Pill View
struct LockScreenFaceIDPillView: View {
    @ObservedObject var faceIDManager = FaceIDManager.shared
    @State private var isPulsing: Bool = false
    
    var body: some View {
        Button {
            if !faceIDManager.isScanning && !faceIDManager.lastUnlockSuccess {
                faceIDManager.startRecognitionOnWake()
            }
        } label: {
            HStack(spacing: 8) {
                if faceIDManager.lastUnlockSuccess {
                    Image(systemName: "lock.open.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.green)
                    
                    Text("Đã mở khoá!")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                } else if faceIDManager.isScanning {
                    Image(systemName: "faceid")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.cyan)
                        .scaleEffect(isPulsing ? 1.15 : 0.95)
                        .animation(
                            .easeInOut(duration: 0.6).repeatForever(autoreverses: true),
                            value: isPulsing
                        )
                    
                    Text("Đang quét Face ID…")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                } else {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.orange)
                    
                    Text("Chạm để quét lại")
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                ZStack {
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark)
                    
                    Capsule()
                        .fill(Color.black.opacity(0.65))
                    
                    Capsule()
                        .strokeBorder(borderColor, lineWidth: 1.2)
                }
            )
            .shadow(color: .black.opacity(0.35), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .onAppear {
            isPulsing = true
        }
    }
    
    private var borderColor: Color {
        if faceIDManager.lastUnlockSuccess {
            return .green.opacity(0.8)
        } else if faceIDManager.isScanning {
            return .cyan.opacity(0.6)
        } else {
            return .orange.opacity(0.5)
        }
    }
}
