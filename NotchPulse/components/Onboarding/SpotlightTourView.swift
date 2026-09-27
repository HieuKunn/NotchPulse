//
//  SpotlightTourView.swift
//  NotchPulse
//
//  Created by Antigravity on 2026-09-27.
//

import SwiftUI
import AppKit

// MARK: - Tour Step Model

enum SpotlightTourStep: Int, CaseIterable, Identifiable {
    case notchHover = 0
    case shakeToShelf
    case musicPlayer
    case calendarLunar
    case clipboardManager
    case faceIDLock
    case menuBarSettings

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .notchHover:
            return "🕳️ Mở rộng Notch (Dynamic Island)"
        case .shakeToShelf:
            return "🤝 Lắc chuột để mở Shelf (Smart Shake)"
        case .musicPlayer:
            return "🎵 Trình phát nhạc & Lời bài hát"
        case .calendarLunar:
            return "📅 Lịch Âm Dương & Sự kiện"
        case .clipboardManager:
            return "📋 Bộ nhớ tạm Clipboard"
        case .faceIDLock:
            return "🔒 Bảo mật Face ID & Lock Screen"
        case .menuBarSettings:
            return "⚙️ Menu Bar & Cài đặt Tùy chỉnh"
        }
    }

    var badgeText: String {
        "Bước \(rawValue + 1)/\(SpotlightTourStep.allCases.count)"
    }

    var description: String {
        switch self {
        case .notchHover:
            return "Di chuột vào khu vực Notch ở góc trên giữa màn hình để mở rộng bảng điều khiển nhanh. Rời chuột 250ms Notch sẽ tự thu gọn mượt mà."
        case .shakeToShelf:
            return "Khi bạn đang nắm/kéo (drag) một file, hình ảnh hoặc đoạn văn bản, hãy lắc nhẹ chuột trái phải nhanh 2-3 lần. Khay lưu tạm Notch Shelf sẽ lập tức bung ra hứng file!"
        case .musicPlayer:
            return "Click vào Bìa Album để mở nhanh App nhạc tương ứng. Click vào Tên bài hát hoặc biểu tượng Micro để mở Lời bài hát cuộn theo thời gian thực (Synced Lyrics)."
        case .calendarLunar:
            return "Xem lịch tháng đầy đủ, dùng mũi tên `<` `>` để đổi tháng. Click icon Mặt Trăng góc phải để xem chi tiết Ngày/Tháng Âm Lịch, Can Chi & Hoàng Đạo."
        case .clipboardManager:
            return "Tự động lưu lại toàn bộ lịch sử nội dung đã Copy. Click vào dòng bất kỳ để Paste lại nhanh, ghim 📌 nội dung quan trọng hoặc tìm kiếm lịch sử."
        case .faceIDLock:
            return "Di chuột vào Notch để tự động quét nhận diện Face ID / Touch ID giải mã thông tin. Khi dùng màn hình rời, Face ID sẽ hạ xuống mượt mà bên màn hình có Camera thật."
        case .menuBarSettings:
            return "Click icon NotchPulse trên thanh Menu Bar ở góc trên phải màn hình để chọn màn hình hiển thị, chỉnh độ cong góc, độ mờ hiệu ứng hoặc mở Cài đặt nâng cao."
        }
    }

    var iconName: String {
        switch self {
        case .notchHover: return "arrow.up.and.person.rectangle.portrait"
        case .shakeToShelf: return "hand.draw.fill"
        case .musicPlayer: return "music.note.list"
        case .calendarLunar: return "calendar.badge.clock"
        case .clipboardManager: return "doc.on.clipboard.fill"
        case .faceIDLock: return "faceid"
        case .menuBarSettings: return "gearshape.fill"
        }
    }

    /// Calculate highlight frame relative to screen size (width, height)
    func targetFrame(screenSize: CGSize) -> CGRect {
        let screenWidth = screenSize.width
        let screenHeight = screenSize.height

        switch self {
        case .notchHover:
            // Top center Notch area
            let width: CGFloat = 280
            let height: CGFloat = 50
            return CGRect(x: (screenWidth - width) / 2, y: 0, width: width, height: height)

        case .shakeToShelf:
            // Slightly larger top center area
            let width: CGFloat = 360
            let height: CGFloat = 180
            return CGRect(x: (screenWidth - width) / 2, y: 0, width: width, height: height)

        case .musicPlayer:
            // Notch music area (center top expanded)
            let width: CGFloat = 380
            let height: CGFloat = 160
            return CGRect(x: (screenWidth - width) / 2, y: 20, width: width, height: height)

        case .calendarLunar:
            // Notch Calendar Area
            let width: CGFloat = 400
            let height: CGFloat = 220
            return CGRect(x: (screenWidth - width) / 2, y: 20, width: width, height: height)

        case .clipboardManager:
            // Notch Clipboard Area
            let width: CGFloat = 420
            let height: CGFloat = 240
            return CGRect(x: (screenWidth - width) / 2, y: 20, width: width, height: height)

        case .faceIDLock:
            // Top Camera Lens area
            let width: CGFloat = 220
            let height: CGFloat = 70
            return CGRect(x: (screenWidth - width) / 2, y: 0, width: width, height: height)

        case .menuBarSettings:
            // Menu bar right corner
            let width: CGFloat = 260
            let height: CGFloat = 34
            return CGRect(x: screenWidth - width - 20, y: 0, width: width, height: height)
        }
    }
}

// MARK: - Hole Punch Shape (Spotlight Cutout)

struct SpotlightCutoutShape: Shape {
    let targetRect: CGRect
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        // Whole screen rect
        path.addRect(rect)
        // Subtracted cutout hole
        let hole = Path(roundedRect: targetRect, cornerSize: CGSize(width: cornerRadius, height: cornerRadius))
        path.addPath(hole)
        return path
    }
}

// MARK: - Main Spotlight Tour View

struct SpotlightTourView: View {
    @State private var currentStepIndex: Int = 0
    let onDismiss: () -> Void

    private var currentStep: SpotlightTourStep {
        SpotlightTourStep(rawValue: currentStepIndex) ?? .notchHover
    }

    var body: some View {
        GeometryReader { geometry in
            let screenSize = geometry.size
            let targetRect = currentStep.targetFrame(screenSize: screenSize)
            let cornerRadius: CGFloat = (currentStep == .menuBarSettings || currentStep == .notchHover) ? 12 : 22

            ZStack {
                // 1. Dark Overlay with Cutout (Even-Odd hole punch)
                SpotlightCutoutShape(targetRect: targetRect, cornerRadius: cornerRadius)
                    .fill(Color.black.opacity(0.82), style: FillStyle(eoFill: true))
                    .ignoresSafeArea()
                    .onTapGesture {
                        // Advance step on background tap
                        nextStep()
                    }

                // 2. Bright Glowing Spotlight Frame around target
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Color.cyan, Color.accentColor, Color.purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 3.5
                    )
                    .shadow(color: Color.cyan.opacity(0.8), radius: 12)
                    .shadow(color: Color.accentColor.opacity(0.6), radius: 24)
                    .frame(width: targetRect.width, height: targetRect.height)
                    .position(x: targetRect.midX, y: targetRect.midY)
                    .animation(.spring(response: 0.45, dampingFraction: 0.75), value: currentStepIndex)

                // 3. Floating Guidance Tooltip Card
                SpotlightTooltipCard(
                    step: currentStep,
                    onNext: nextStep,
                    onPrev: prevStep,
                    onSkipStep: nextStep,
                    onSkipAll: onDismiss,
                    isFirst: currentStepIndex == 0,
                    isLast: currentStepIndex == SpotlightTourStep.allCases.count - 1
                )
                .position(tooltipPosition(targetRect: targetRect, screenSize: screenSize))
                .animation(.spring(response: 0.45, dampingFraction: 0.75), value: currentStepIndex)
            }
        }
    }

    private func nextStep() {
        if currentStepIndex < SpotlightTourStep.allCases.count - 1 {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) {
                currentStepIndex += 1
            }
        } else {
            onDismiss()
        }
    }

    private func prevStep() {
        if currentStepIndex > 0 {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) {
                currentStepIndex -= 1
            }
        }
    }

    /// Smart positioning of the card relative to targetRect
    private func tooltipPosition(targetRect: CGRect, screenSize: CGSize) -> CGPoint {
        let cardWidth: CGFloat = 420
        let cardHeight: CGFloat = 250
        let padding: CGFloat = 20

        // If target is near top (like Notch or MenuBar), place card below
        if targetRect.minY < screenSize.height * 0.4 {
            let y = min(screenSize.height - cardHeight / 2 - padding, targetRect.maxY + cardHeight / 2 + 25)
            let x = min(max(cardWidth / 2 + padding, targetRect.midX), screenSize.width - cardWidth / 2 - padding)
            return CGPoint(x: x, y: y)
        } else {
            // Place card above
            let y = max(cardHeight / 2 + padding, targetRect.minY - cardHeight / 2 - 25)
            let x = min(max(cardWidth / 2 + padding, targetRect.midX), screenSize.width - cardWidth / 2 - padding)
            return CGPoint(x: x, y: y)
        }
    }
}

// MARK: - Tooltip Card View

struct SpotlightTooltipCard: View {
    let step: SpotlightTourStep
    let onNext: () -> Void
    let onPrev: () -> Void
    let onSkipStep: () -> Void
    let onSkipAll: () -> Void
    let isFirst: Bool
    let isLast: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header Row
            HStack(spacing: 10) {
                Image(systemName: step.iconName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.cyan)

                Text(step.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Spacer()

                Text(step.badgeText)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.15)))
                    .foregroundColor(.white.opacity(0.8))

                // Quick exit X button
                Button(action: onSkipAll) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white.opacity(0.5))
                }
                .buttonStyle(PlainButtonStyle())
                .help("Đóng hướng dẫn (Bỏ qua tất cả)")
            }

            Divider()
                .background(Color.white.opacity(0.2))

            // Body Description
            Text(step.description)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(.white.opacity(0.92))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            // Action Buttons Footer
            HStack(spacing: 8) {
                Button(action: onSkipAll) {
                    Text("Bỏ qua tất cả")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.55))
                }
                .buttonStyle(PlainButtonStyle())

                Text("•")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.3))

                if !isLast {
                    Button(action: onSkipStep) {
                        Text("Bỏ qua bước")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                Spacer()

                if !isFirst {
                    Button(action: onPrev) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Quay lại")
                        }
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.12)))
                        .foregroundColor(.white)
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                Button(action: onNext) {
                    HStack(spacing: 4) {
                        Text(isLast ? "Hoàn thành" : "Tiếp theo")
                        if !isLast {
                            Image(systemName: "chevron.right")
                        }
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(LinearGradient(colors: [.cyan, .blue], startPoint: .leading, endPoint: .trailing))
                    )
                    .foregroundColor(.white)
                    .shadow(color: .cyan.opacity(0.5), radius: 6)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(18)
        .frame(width: 420, height: 240)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.85))
                .background(
                    VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.5), radius: 20, x: 0, y: 10)
        )
    }
}

// MARK: - Tour Manager Window Controller

final class SpotlightTourManager: ObservableObject {
    static let shared = SpotlightTourManager()

    private var tourWindow: NSWindow?

    func showTour() {
        if tourWindow == nil {
            guard let mainScreen = NSScreen.main else { return }

            let window = NSWindow(
                contentRect: mainScreen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.level = .screenSaver
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.ignoresMouseEvents = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

            let tourView = SpotlightTourView { [weak self] in
                self?.closeTour()
            }

            window.contentView = NSHostingView(rootView: tourView)
            self.tourWindow = window
        }

        tourWindow?.setFrame(NSScreen.main?.frame ?? .zero, display: true)
        tourWindow?.makeKeyAndOrderFront(nil)
        tourWindow?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeTour() {
        tourWindow?.orderOut(nil)
        tourWindow?.close()
        tourWindow = nil
    }
}
