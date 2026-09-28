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
                return "Click icon Bánh răng ⚙️ ở góc trên bên phải Notch (khi mở) để mở Cài đặt, chuyển màn hình hiển thị, chỉnh độ cong góc hoặc các hiệu ứng ánh sáng."
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
                return "Click the Gear ⚙️ icon at the top right inside the open Notch to switch display monitors, customize corner radius, adjust lighting effects, or open Settings."
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
    @MainActor
    func targetFrame(screenSize: CGSize) -> CGRect {
        let screenWidth = screenSize.width

        switch self {
        case .notchHover:
            let openWidth = CGFloat(Defaults[.notchOpenWidth]) + 20
            let height: CGFloat = 175
            return CGRect(x: (screenWidth - openWidth) / 2, y: 0, width: openWidth, height: height)

        case .shakeToShelf:
            let openWidth = CGFloat(Defaults[.notchOpenWidth]) + 20
            let height: CGFloat = 200
            return CGRect(x: (screenWidth - openWidth) / 2, y: 0, width: openWidth, height: height)

        case .musicPlayer:
            let openWidth = CGFloat(Defaults[.notchOpenWidth]) + 20
            let height: CGFloat = 195
            return CGRect(x: (screenWidth - openWidth) / 2, y: 0, width: openWidth, height: height)

        case .calendarExpand:
            let openWidth = CGFloat(Defaults[.notchOpenWidth]) + 20
            let height: CGFloat = 240
            return CGRect(x: (screenWidth - openWidth) / 2, y: 0, width: openWidth, height: height)

        case .calendarFullMonth:
            let openWidth = CGFloat(Defaults[.notchOpenWidth]) + 20
            let height: CGFloat = 265
            return CGRect(x: (screenWidth - openWidth) / 2, y: 0, width: openWidth, height: height)

        case .clipboardManager:
            let openWidth = CGFloat(Defaults[.notchOpenWidth]) + 20
            let height: CGFloat = 250
            return CGRect(x: (screenWidth - openWidth) / 2, y: 0, width: openWidth, height: height)

        case .faceIDLock:
            let width: CGFloat = 320
            let height: CGFloat = 80
            return CGRect(x: (screenWidth - width) / 2, y: 0, width: width, height: height)

        case .menuBarSettings:
            let openWidth = CGFloat(Defaults[.notchOpenWidth]) + 20
            let height: CGFloat = 175
            return CGRect(x: (screenWidth - openWidth) / 2, y: 0, width: openWidth, height: height)
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

// MARK: - Fullscreen Pass-Through Backdrop View

struct SpotlightBackdropView: View {
    @ObservedObject var manager = SpotlightTourManager.shared

    var body: some View {
        GeometryReader { _ in
            ZStack {
                // 1. Dark Overlay with Cutout (Even-Odd hole punch)
                SpotlightCutoutShape(
                    targetRect: manager.currentCutoutRect,
                    cornerRadius: manager.currentCornerRadius
                )
                .fill(Color.black.opacity(0.75), style: FillStyle(eoFill: true))
                .ignoresSafeArea()

                // 2. Bright Glowing Pure White Frame around target
                RoundedRectangle(cornerRadius: manager.currentCornerRadius, style: .continuous)
                    .stroke(Color.white, lineWidth: 2.5)
                    .shadow(color: Color.white.opacity(0.85), radius: 8)
                    .shadow(color: Color.white.opacity(0.4), radius: 18)
                    .frame(width: max(0, manager.currentCutoutRect.width), height: max(0, manager.currentCutoutRect.height))
                    .position(x: manager.currentCutoutRect.midX, y: manager.currentCutoutRect.midY)
                    .animation(.spring(response: 0.45, dampingFraction: 0.75), value: manager.currentStepIndex)
            }
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
                    .foregroundColor(.black)

                Text(step.title(lang: language))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.black)
                    .lineLimit(1)

                Spacer()

                Text(step.badgeText(lang: language))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.black.opacity(0.08)))
                    .foregroundColor(Color.black.opacity(0.75))

                // Quick exit X button: Closes guide and keeps Notch open
                Button(action: onSkipAll) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(Color.black.opacity(0.45))
                }
                .buttonStyle(PlainButtonStyle())
                .help(isVietnamese ? "Đóng hướng dẫn (Notch vẫn mở)" : "Close guide (Notch stays open)")
            }

            Divider()
                .background(Color.black.opacity(0.12))

            // Body Description
            Text(step.description(lang: language))
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(Color.black.opacity(0.85))
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
                        .foregroundColor(Color.black.opacity(0.5))
                }
                .buttonStyle(PlainButtonStyle())

                Text("•")
                    .font(.system(size: 10))
                    .foregroundColor(Color.black.opacity(0.3))

                if !isLast {
                    Button(action: onSkipStep) {
                        Text(isVietnamese ? "Bỏ qua bước" : "Skip step")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color.black.opacity(0.7))
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
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.08)))
                        .foregroundColor(Color.black.opacity(0.85))
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
                            .fill(Color.black)
                    )
                    .foregroundColor(.white)
                    .shadow(color: Color.black.opacity(0.2), radius: 4)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(18)
        .frame(width: 430, height: (step == .faceIDLock) ? 290 : 240)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.96))
                .background(
                    VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.black.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.35), radius: 20, x: 0, y: 10)
        )
    }

    @ViewBuilder
    private var faceIDSetupPromptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "person.badge.shield.checkmark.fill")
                    .foregroundColor(.black)
                    .font(.system(size: 13))

                Text(isVietnamese ? "Bạn có muốn thiết lập Face ID ngay không?" : "Would you like to set up Face ID now?")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.black)
            }

            HStack(spacing: 8) {
                Button(action: {
                    SpotlightTourManager.shared.startFaceIDSetupFromTour {
                        onNext()
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                        Text(isVietnamese ? "Có (Thiết lập ngay)" : "Yes (Set up now)")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.black))
                    .foregroundColor(.white)
                }
                .buttonStyle(PlainButtonStyle())

                Button(action: onNext) {
                    Text(isVietnamese ? "Không (Để sau)" : "No (Later)")
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.08)))
                        .foregroundColor(Color.black.opacity(0.8))
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.06)))
    }
}

// MARK: - Dedicated Tooltip Card Host View

struct SpotlightTooltipCardHostView: View {
    @ObservedObject var manager = SpotlightTourManager.shared

    var body: some View {
        SpotlightTooltipCard(
            step: manager.currentStep,
            language: manager.language,
            onNext: { manager.nextStep() },
            onPrev: { manager.prevStep() },
            onSkipStep: { manager.nextStep() },
            onSkipAll: { manager.closeTour() },
            isFirst: manager.currentStepIndex == 0,
            isLast: manager.currentStepIndex == SpotlightTourStep.allCases.count - 1
        )
    }
}

// MARK: - Tour Manager Window Controller

@MainActor
final class SpotlightTourManager: ObservableObject {
    static let shared = SpotlightTourManager()

    /// True while the spotlight tour overlay is visible. ContentView uses this flag
    /// to suppress all auto-close timers so the notch stays open during the tour.
    @Published var isActive: Bool = false

    @Published var currentStepIndex: Int = 0
    @Published var currentCutoutRect: CGRect = .zero
    @Published var currentCornerRadius: CGFloat = 22
    @Published var language: AppLanguage = .english

    var currentStep: SpotlightTourStep {
        SpotlightTourStep(rawValue: currentStepIndex) ?? .notchHover
    }

    private var backdropWindow: NSWindow?
    private var cardWindow: NSWindow?
    private var faceIDPhaseObserver: NSObjectProtocol?
    private var activeScreen: NSScreen?

    func showTour(useAppLanguage: Bool = false) {
        closeTour()

        let targetScreen: NSScreen?
        if Defaults[.showOnAllDisplays] {
            targetScreen = NSScreen.screens.first(where: { $0.isBuiltIn || $0.safeAreaInsets.top > 0 })
                ?? NSScreen.main
        } else {
            let coordinator = NotchPulseViewCoordinator.shared
            targetScreen = NSScreen.screen(withUUID: coordinator.selectedScreenUUID) ?? NSScreen.main
        }
        guard let mainScreen = targetScreen else { return }
        self.activeScreen = mainScreen

        self.language = useAppLanguage ? Defaults[.appLanguage] : .english
        self.currentStepIndex = 0

        let initialTarget = currentStep.targetFrame(screenSize: mainScreen.frame.size)
        self.currentCutoutRect = initialTarget
        self.currentCornerRadius = (currentStep == .menuBarSettings || currentStep == .notchHover) ? 12 : 22

        // 1. Create Non-Blocking Backdrop Window (ignoresMouseEvents = true so all clicks pass through)
        let backdrop = NSWindow(
            contentRect: mainScreen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        backdrop.level = .screenSaver
        backdrop.backgroundColor = .clear
        backdrop.isOpaque = false
        backdrop.hasShadow = false
        backdrop.ignoresMouseEvents = true // Full pass-through for Notch, Desktop, and Apps!
        backdrop.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        backdrop.contentView = NSHostingView(rootView: SpotlightBackdropView())
        self.backdropWindow = backdrop

        // 2. Create Floating Tooltip Card Window (sized strictly to the 430px card)
        let initialCardRect = cardRect(for: currentStep, screen: mainScreen)
        let card = NSPanel(
            contentRect: initialCardRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        card.level = .screenSaver + 1
        card.backgroundColor = .clear
        card.isOpaque = false
        card.hasShadow = false
        card.ignoresMouseEvents = false // Card captures clicks on its own buttons
        card.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        card.contentView = NSHostingView(rootView: SpotlightTooltipCardHostView())
        self.cardWindow = card

        isActive = true

        updateLiveUIState(for: currentStep)

        backdrop.orderFrontRegardless()
        card.orderFrontRegardless()
    }

    func nextStep() {
        if currentStepIndex < SpotlightTourStep.allCases.count - 1 {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) {
                currentStepIndex += 1
            }
            stepDidChange()
        } else {
            closeTour()
        }
    }

    func prevStep() {
        if currentStepIndex > 0 {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) {
                currentStepIndex -= 1
            }
            stepDidChange()
        }
    }

    private func stepDidChange() {
        guard let screen = activeScreen else { return }
        
        // 1. Pre-switch live tabs & open notch for the new step beforehand
        updateLiveUIState(for: currentStep)

        // 2. Update spotlight cutout and card frame
        let newTarget = currentStep.targetFrame(screenSize: screen.frame.size)
        self.currentCutoutRect = newTarget
        self.currentCornerRadius = (currentStep == .menuBarSettings || currentStep == .notchHover) ? 12 : 22

        let newCardRect = cardRect(for: currentStep, screen: screen)
        cardWindow?.setFrame(newCardRect, display: true, animate: true)
    }

    private func cardRect(for step: SpotlightTourStep, screen: NSScreen) -> NSRect {
        let screenSize = screen.frame.size
        let screenOrigin = screen.frame.origin
        let targetRect = step.targetFrame(screenSize: screenSize)
        let cardWidth: CGFloat = 430
        let cardHeight: CGFloat = (step == .faceIDLock) ? 290 : 240
        let padding: CGFloat = 20

        let x: CGFloat
        if step == .menuBarSettings {
            let openWidth = CGFloat(Defaults[.notchOpenWidth])
            let notchRight = (screenSize.width + openWidth) / 2
            x = min(screenSize.width - cardWidth - 20, max(20, notchRight - cardWidth / 2))
        } else {
            x = (screenSize.width - cardWidth) / 2
        }

        let topY = targetRect.maxY + 20
        let constrainedTopY = min(screenSize.height - cardHeight - padding, topY)

        let appKitY = screenOrigin.y + (screenSize.height - constrainedTopY - cardHeight)
        let appKitX = screenOrigin.x + x

        return NSRect(x: appKitX, y: appKitY, width: cardWidth, height: cardHeight)
    }

    private func updateLiveUIState(for step: SpotlightTourStep) {
        guard let appDelegate = NSApp.delegate as? AppDelegate else { return }
        let coordinator = NotchPulseViewCoordinator.shared

        let targetVM: NotchPulseViewModel
        if let activeUUID = self.activeScreen?.displayUUID,
           let vm = appDelegate.viewModels[activeUUID] {
            targetVM = vm
        } else if let camScreen = NSScreen.screens.first(where: { $0.isBuiltIn || $0.safeAreaInsets.top > 0 }),
                  let camUUID = camScreen.displayUUID,
                  let vm = appDelegate.viewModels[camUUID] {
            targetVM = vm
        } else {
            targetVM = appDelegate.viewModels[coordinator.selectedScreenUUID] ?? appDelegate.vm
        }

        let allVMs: [NotchPulseViewModel] = [appDelegate.vm, targetVM] + Array(appDelegate.viewModels.values)

        // Synchronously and smoothly pre-switch tab pages so the user sees the page directly
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            switch step {
            case .notchHover:
                coordinator.currentView = .home
                CalendarStateViewModel.shared.isFullMonthExpanded = false
                for vm in allVMs {
                    vm.customOpenHeight = nil
                    vm.open()
                }

            case .shakeToShelf:
                coordinator.currentView = .shelf
                CalendarStateViewModel.shared.isFullMonthExpanded = false
                for vm in allVMs {
                    vm.customOpenHeight = nil
                    vm.open()
                }

            case .musicPlayer:
                coordinator.currentView = .home
                CalendarStateViewModel.shared.isFullMonthExpanded = false
                for vm in allVMs {
                    vm.customOpenHeight = nil
                    vm.open()
                }

            case .calendarExpand:
                coordinator.currentView = .home
                CalendarStateViewModel.shared.isFullMonthExpanded = false
                for vm in allVMs {
                    vm.customOpenHeight = nil
                    vm.open()
                }

            case .calendarFullMonth:
                coordinator.currentView = .home
                CalendarStateViewModel.shared.isFullMonthExpanded = true
                for vm in allVMs {
                    vm.customOpenHeight = 240
                    vm.open()
                }

            case .clipboardManager:
                coordinator.currentView = .clipboard
                CalendarStateViewModel.shared.isFullMonthExpanded = false
                for vm in allVMs {
                    vm.customOpenHeight = 250
                    vm.open()
                }

            case .faceIDLock:
                coordinator.currentView = .home
                CalendarStateViewModel.shared.isFullMonthExpanded = false
                for vm in allVMs {
                    vm.customOpenHeight = nil
                    vm.open()
                }

            case .menuBarSettings:
                coordinator.currentView = .home
                CalendarStateViewModel.shared.isFullMonthExpanded = false
                for vm in allVMs {
                    vm.customOpenHeight = nil
                    vm.open()
                }
            }
        }

        // After vm.open() the notchSize is set to the real open dimensions — use those to
        // compute the spotlight cutout so the ring matches the actual rendered notch exactly.
        updateCutoutRectFromLiveVM(step: step, targetVM: targetVM)
    }

    /// Compute the spotlight cutout rect by reading the live notch dimensions from `targetVM`
    /// after `open()` has been called. This ensures the highlight ring is always pixel-accurate
    /// regardless of user width/height settings or custom open height overrides.
    @MainActor
    private func updateCutoutRectFromLiveVM(step: SpotlightTourStep, targetVM: NotchPulseViewModel) {
        guard let screen = activeScreen else { return }
        let screenSize = screen.frame.size

        // The open notch width comes directly from the VM (set by open() -> openNotchWidth).
        // Add padding so the spotlight ring fits smoothly around the outer edge of the expanded notch.
        let notchWidth = targetVM.notchSize.width
        let ringPad: CGFloat = 12       // Generous padding around the open notch edges
        let ringWidth = notchWidth + ringPad * 2

        // Height: use the VM's effective open height (respects customOpenHeight overrides like
        // calendar's 240pt or clipboard's 250pt). For the faceID closed-notch step use 80pt.
        let notchHeight: CGFloat
        if step == .faceIDLock {
            notchHeight = 80
        } else {
            notchHeight = targetVM.customOpenHeight ?? targetVM.notchSize.height
        }
        
        // Extend slightly above top of screen (-10) so top edge of ring merges cleanly off-screen,
        // matching notch top attachment.
        let yOffset: CGFloat = -10
        let ringHeight = notchHeight + ringPad + abs(yOffset)

        // Cutout X is centered on screen (same as the notch window centering logic).
        let x = (screenSize.width - ringWidth) / 2
        let y: CGFloat = yOffset

        withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
            self.currentCutoutRect = CGRect(x: x, y: y, width: ringWidth, height: ringHeight)
            self.currentCornerRadius = step == .faceIDLock ? 18 : 32
        }
    }


    func hideTour() {
        backdropWindow?.orderOut(nil)
        cardWindow?.orderOut(nil)
    }

    func unhideTour() {
        guard isActive else { return }
        backdropWindow?.orderFrontRegardless()
        cardWindow?.orderFrontRegardless()
    }

    func startFaceIDSetupFromTour(completion: @escaping () -> Void) {
        hideTour()

        if let existing = faceIDPhaseObserver {
            NotificationCenter.default.removeObserver(existing)
            faceIDPhaseObserver = nil
        }

        faceIDPhaseObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name.faceIDPhaseChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                if FaceIDOverlayController.shared.phase == .closed {
                    if let obs = self?.faceIDPhaseObserver {
                        NotificationCenter.default.removeObserver(obs)
                        self?.faceIDPhaseObserver = nil
                    }
                    try? await Task.sleep(for: .milliseconds(350))
                    self?.unhideTour()
                    completion()
                }
            }
        }

        // Use standard enrollment flow (identical to Settings menu: startEnrollmentOnly)
        FaceIDEnrollmentController.startEnrollmentOnly()
    }

    func closeTour() {
        if let obs = faceIDPhaseObserver {
            NotificationCenter.default.removeObserver(obs)
            faceIDPhaseObserver = nil
        }
        isActive = false
        backdropWindow?.orderOut(nil)
        backdropWindow?.close()
        backdropWindow = nil

        cardWindow?.orderOut(nil)
        cardWindow?.close()
        cardWindow = nil

        // Keep the Notch OPEN after closing tour so user can start using it immediately!
        guard let appDelegate = NSApp.delegate as? AppDelegate else { return }
        let coordinator = NotchPulseViewCoordinator.shared
        coordinator.currentView = .home
        CalendarStateViewModel.shared.isFullMonthExpanded = false

        let allVMs: [NotchPulseViewModel] = [appDelegate.vm] + Array(appDelegate.viewModels.values)
        for vm in allVMs {
            vm.customOpenHeight = nil
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                vm.close()
            }
        }
    }
}
