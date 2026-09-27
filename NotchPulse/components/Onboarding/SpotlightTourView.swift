//
//  SpotlightTourView.swift
//  NotchPulse
//
//  Created by Antigravity on 2026-09-27.
//

import SwiftUI
import AppKit
import Defaults

// MARK: - Tour Step Model

enum SpotlightTourStep: Int, CaseIterable, Identifiable {
    case notchHover = 0
    case shakeToShelf
    case musicPlayer
    case calendarExpand
    case calendarFullMonth
    case clipboardManager
    case faceIDLock
    case menuBarSettings

    var id: Int { rawValue }

    func title(lang: AppLanguage) -> String {
        switch lang {
        case .vietnamese:
            switch self {
            case .notchHover: return "🕳️ Mở rộng Notch (Dynamic Island)"
            case .shakeToShelf: return "🤝 Lắc chuột để mở Shelf (Smart Shake)"
            case .musicPlayer: return "🎵 Trình phát nhạc & Lời bài hát"
            case .calendarExpand: return "📅 Mở rộng Lịch toàn tháng"
            case .calendarFullMonth: return "🗓️ Điều hướng Lịch & Ngày Âm Lịch"
            case .clipboardManager: return "📋 Bộ nhớ tạm Clipboard"
            case .faceIDLock: return "🔒 Bảo mật Face ID & Khóa màn hình"
            case .menuBarSettings: return "⚙️ Menu Bar & Cài đặt Tùy chỉnh"
            }
        default:
            switch self {
            case .notchHover: return "🕳️ Expand Notch (Dynamic Island)"
            case .shakeToShelf: return "🤝 Shake to Open Shelf (Smart Shake)"
            case .musicPlayer: return "🎵 Music Player & Synced Lyrics"
            case .calendarExpand: return "📅 Expand Full Month Calendar"
            case .calendarFullMonth: return "🗓️ Full Month Navigation & Lunar Details"
            case .clipboardManager: return "📋 Clipboard History & Snippets"
            case .faceIDLock: return "🔒 Face ID & Lock Screen Security"
            case .menuBarSettings: return "⚙️ Menu Bar & Customizations"
            }
        }
    }

    func badgeText(lang: AppLanguage) -> String {
        let current = rawValue + 1
        let total = SpotlightTourStep.allCases.count
        if lang == .vietnamese {
            return "Bước \(current)/\(total)"
        } else {
            return "Step \(current)/\(total)"
        }
    }

    func description(lang: AppLanguage) -> String {
        switch lang {
        case .vietnamese:
            switch self {
            case .notchHover:
                return "Di chuột vào khu vực Notch ở góc trên giữa màn hình để mở rộng bảng điều khiển nhanh. Rời chuột 250ms Notch sẽ tự thu gọn mượt mà."
            case .shakeToShelf:
                return "Khi bạn đang nắm/kéo (drag) một file, hình ảnh hoặc đoạn văn bản, hãy lắc nhẹ chuột trái phải nhanh 2-3 lần. Khay lưu tạm Notch Shelf sẽ lập tức bung ra hứng file!"
            case .musicPlayer:
                return "Click vào Bìa Album để mở nhanh App nhạc tương ứng. Click vào Tên bài hát hoặc biểu tượng Micro để mở Lời bài hát cuộn theo thời gian thực (Synced Lyrics)."
            case .calendarExpand:
                return "Click trực tiếp vào phần hiển thị Ngày & Tháng bên trong Notch để lập tức mở rộng toàn bộ lưới lịch tháng tương tác."
            case .calendarFullMonth:
                return "Dùng 2 nút mũi tên `<` và `>` bên trái để chuyển tháng, và nhấn vào biểu tượng Mặt Trăng bên phải để xem chi tiết Ngày/Tháng Âm Lịch, Can Chi & Giờ hoàng đạo."
            case .clipboardManager:
                return "Tự động lưu lại toàn bộ lịch sử nội dung đã Copy. Click vào dòng bất kỳ để Paste lại nhanh, ghim 📌 nội dung quan trọng hoặc tìm kiếm lịch sử."
            case .faceIDLock:
                return "Di chuột vào Notch để tự động quét nhận diện Face ID / Touch ID giải mã thông tin. Khi dùng màn hình rời, Face ID sẽ hạ xuống mượt mà bên màn hình có Camera thật."
            case .menuBarSettings:
                return "Click icon NotchPulse trên thanh Menu Bar ở góc trên phải màn hình để chọn màn hình hiển thị, chỉnh độ cong góc, độ mờ hiệu ứng hoặc mở Cài đặt nâng cao."
            }
        default:
            switch self {
            case .notchHover:
                return "Hover your cursor over the Notch at the top center of your screen to expand the quick controls. Move mouse away for 250ms to smoothly auto-close."
            case .shakeToShelf:
                return "While dragging any file, image, or text snippet, quickly shake your mouse left and right 2-3 times. The Notch Shelf will immediately pop open to catch your file!"
            case .musicPlayer:
                return "Click the Album Art to jump directly into the active music app. Click the song title or lyrics icon to view real-time synced scrolling lyrics."
            case .calendarExpand:
                return "Click directly on the Month & Date header inside the Notch to expand the full 30-day interactive calendar grid."
            case .calendarFullMonth:
                return "Use the `<` and `>` buttons on the left to switch months, see today highlighted, and click the Moon icon on the right to view detailed Lunar calendar dates & Can Chi."
            case .clipboardManager:
                return "Automatically keeps track of your copied text, images, and links. Click any item to re-paste, pin 📌 essentials, or search your clipboard history."
            case .faceIDLock:
                return "Hover over the Notch to automatically authenticate using Face ID or Touch ID. When connected to an external display, Face ID drops down under your physical camera."
            case .menuBarSettings:
                return "Click the NotchPulse icon in the Menu Bar at the top right to switch display monitors, customize corner radius, adjust lighting effects, or open Settings."
            }
        }
    }

    var iconName: String {
        switch self {
        case .notchHover: return "arrow.up.and.person.rectangle.portrait"
        case .shakeToShelf: return "hand.draw.fill"
        case .musicPlayer: return "music.note.list"
        case .calendarExpand: return "calendar.badge.plus"
        case .calendarFullMonth: return "calendar.badge.clock"
        case .clipboardManager: return "doc.on.clipboard.fill"
        case .faceIDLock: return "faceid"
        case .menuBarSettings: return "gearshape.fill"
        }
    }

    /// Calculate highlight frame relative to screen size (width, height)
    func targetFrame(screenSize: CGSize) -> CGRect {
        let screenWidth = screenSize.width

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
            return CGRect(x: (screenWidth - width) / 2, y: 15, width: width, height: height)

        case .calendarExpand:
            // Compact Calendar header in Notch
            let width: CGFloat = 320
            let height: CGFloat = 70
            return CGRect(x: (screenWidth - width) / 2, y: 10, width: width, height: height)

        case .calendarFullMonth:
            // Notch Full Month Calendar Area
            let width: CGFloat = 420
            let height: CGFloat = 240
            return CGRect(x: (screenWidth - width) / 2, y: 15, width: width, height: height)

        case .clipboardManager:
            // Notch Clipboard Area
            let width: CGFloat = 420
            let height: CGFloat = 240
            return CGRect(x: (screenWidth - width) / 2, y: 15, width: width, height: height)

        case .faceIDLock:
            // Top Camera Lens area
            let width: CGFloat = 240
            let height: CGFloat = 75
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
    var language: AppLanguage = .english
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
                    .fill(Color.black.opacity(0.80), style: FillStyle(eoFill: true))
                    .ignoresSafeArea()
                    .onTapGesture {
                        // Advance step on background tap
                        nextStep()
                    }

                // 2. Bright Glowing Pure White Frame around target (Clean, no neon)
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white, lineWidth: 2.5)
                    .shadow(color: Color.white.opacity(0.85), radius: 8)
                    .shadow(color: Color.white.opacity(0.4), radius: 18)
                    .frame(width: targetRect.width, height: targetRect.height)
                    .position(x: targetRect.midX, y: targetRect.midY)
                    .animation(.spring(response: 0.45, dampingFraction: 0.75), value: currentStepIndex)

                // 3. Floating Guidance Tooltip Card
                SpotlightTooltipCard(
                    step: currentStep,
                    language: language,
                    onNext: nextStep,
                    onPrev: prevStep,
                    onSkipStep: nextStep,
                    onSkipAll: dismissTour,
                    isFirst: currentStepIndex == 0,
                    isLast: currentStepIndex == SpotlightTourStep.allCases.count - 1
                )
                .position(tooltipPosition(targetRect: targetRect, screenSize: screenSize))
                .animation(.spring(response: 0.45, dampingFraction: 0.75), value: currentStepIndex)
            }
            .onAppear {
                updateLiveUIState(for: currentStep)
            }
            .onChange(of: currentStepIndex) { _, newIndex in
                if let newStep = SpotlightTourStep(rawValue: newIndex) {
                    updateLiveUIState(for: newStep)
                }
            }
        }
    }

    private func dismissTour() {
        Task { @MainActor in
            (NSApp.delegate as? AppDelegate)?.vm.close()
        }
        onDismiss()
    }

    private func updateLiveUIState(for step: SpotlightTourStep) {
        Task { @MainActor in
            guard let vm = (NSApp.delegate as? AppDelegate)?.vm else { return }
            let coordinator = NotchPulseViewCoordinator.shared

            switch step {
            case .notchHover:
                coordinator.currentView = .home
                vm.open()

            case .shakeToShelf:
                coordinator.currentView = .shelf
                vm.open()

            case .musicPlayer:
                coordinator.currentView = .home
                vm.open()

            case .calendarExpand:
                coordinator.currentView = .home
                CalendarStateViewModel.shared.isFullMonthExpanded = false
                vm.open()

            case .calendarFullMonth:
                coordinator.currentView = .home
                CalendarStateViewModel.shared.isFullMonthExpanded = true
                vm.open()

            case .clipboardManager:
                coordinator.currentView = .clipboard
                vm.open()

            case .faceIDLock:
                vm.open()

            case .menuBarSettings:
                vm.close()
                SettingsWindowController.shared.showWindow()
            }
        }
    }

    private func nextStep() {
        if currentStepIndex < SpotlightTourStep.allCases.count - 1 {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) {
                currentStepIndex += 1
            }
        } else {
            dismissTour()
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
        let cardWidth: CGFloat = 430
        let cardHeight: CGFloat = (currentStep == .faceIDLock) ? 290 : 240
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
    let language: AppLanguage
    let onNext: () -> Void
    let onPrev: () -> Void
    let onSkipStep: () -> Void
    let onSkipAll: () -> Void
    let isFirst: Bool
    let isLast: Bool

    private var isVietnamese: Bool {
        language == .vietnamese
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header Row
            HStack(spacing: 10) {
                Image(systemName: step.iconName)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(.white)

                Text(step.title(lang: language))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Spacer()

                Text(step.badgeText(lang: language))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.15)))
                    .foregroundColor(.white.opacity(0.85))

                // Quick exit X button
                Button(action: onSkipAll) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white.opacity(0.55))
                }
                .buttonStyle(PlainButtonStyle())
                .help(isVietnamese ? "Đóng hướng dẫn (Bỏ qua tất cả)" : "Close guide (Skip all)")
            }

            Divider()
                .background(Color.white.opacity(0.2))

            // Body Description
            Text(step.description(lang: language))
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(.white.opacity(0.92))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            // Step 6 (Face ID): Interactive setup prompt with "Yes" & "No" buttons
            if step == .faceIDLock {
                faceIDSetupPromptSection
            }

            Spacer(minLength: 0)

            // Action Buttons Footer
            HStack(spacing: 8) {
                Button(action: onSkipAll) {
                    Text(isVietnamese ? "Bỏ qua tất cả" : "Skip all")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.55))
                }
                .buttonStyle(PlainButtonStyle())

                Text("•")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.3))

                if !isLast {
                    Button(action: onSkipStep) {
                        Text(isVietnamese ? "Bỏ qua bước" : "Skip step")
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
                            Text(isVietnamese ? "Quay lại" : "Back")
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
                        Text(isLast ? (isVietnamese ? "Hoàn thành" : "Finish") : (isVietnamese ? "Tiếp theo" : "Next"))
                        if !isLast {
                            Image(systemName: "chevron.right")
                        }
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white)
                    )
                    .foregroundColor(.black)
                    .shadow(color: .white.opacity(0.35), radius: 6)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(18)
        .frame(width: 430, height: (step == .faceIDLock) ? 290 : 240)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.88))
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

    @ViewBuilder
    private var faceIDSetupPromptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "person.badge.shield.checkmark.fill")
                    .foregroundColor(.white)
                    .font(.system(size: 13))

                Text(isVietnamese ? "Bạn có muốn thiết lập Face ID ngay không?" : "Would you like to set up Face ID now?")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
            }

            HStack(spacing: 8) {
                Button(action: {
                    onSkipAll()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        if NotchPulsePOCController.shared.hasStoredPassword {
                            FaceIDEnrollmentController.startEnrollmentOnly()
                        } else {
                            FaceIDEnrollmentController.startFlow()
                        }
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                        Text(isVietnamese ? "Có (Thiết lập ngay)" : "Yes (Set up now)")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.white))
                    .foregroundColor(.black)
                }
                .buttonStyle(PlainButtonStyle())

                Button(action: onNext) {
                    Text(isVietnamese ? "Không (Để sau)" : "No (Later)")
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.12)))
                        .foregroundColor(.white.opacity(0.85))
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
    }
}

// MARK: - Tour Manager Window Controller

final class SpotlightTourManager: ObservableObject {
    static let shared = SpotlightTourManager()

    private var tourWindow: NSWindow?

    func showTour(useAppLanguage: Bool = false) {
        closeTour()
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

        let language: AppLanguage = useAppLanguage ? Defaults[.appLanguage] : .english

        let tourView = SpotlightTourView(language: language) { [weak self] in
            self?.closeTour()
        }

        window.contentView = NSHostingView(rootView: tourView)
        self.tourWindow = window

        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeTour() {
        tourWindow?.orderOut(nil)
        tourWindow?.close()
        tourWindow = nil
    }
}
