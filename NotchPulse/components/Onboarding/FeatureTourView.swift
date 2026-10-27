import SwiftUI
import Defaults
import AppKit

struct FeatureTourStep {
    let title: String
    let description: String
    let icon: String
    let tabColor: Color
    let viewType: NotchViews
    let target: String?
}

struct SpotlightCutoutShape: Shape {
    var notchRect: CGRect
    var cornerRadius: CGFloat = 20
    var isDynamicIsland: Bool = false
    var isFullRounded: Bool = false
    
    var animatableData: AnimatablePair<CGRect.AnimatableData, CGFloat> {
        get { AnimatablePair(notchRect.animatableData, cornerRadius) }
        set {
            notchRect.animatableData = newValue.first
            cornerRadius = newValue.second
        }
    }
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        
        let cutout: Path
        if isFullRounded || isDynamicIsland {
            cutout = Path(roundedRect: notchRect, cornerRadius: cornerRadius)
        } else {
            cutout = Path(
                roundedRect: notchRect,
                cornerRadii: RectangleCornerRadii(
                    topLeading: 0,
                    bottomLeading: cornerRadius,
                    bottomTrailing: cornerRadius,
                    topTrailing: 0
                )
            )
        }
        path.addPath(cutout)
        return path
    }
}

struct TourSpeechBubbleShape: Shape {
    let isLeadingArrow: Bool
    let arrowOffset: CGFloat
    var cornerRadius: CGFloat = 18
    var arrowWidth: CGFloat = 16
    var arrowHeight: CGFloat = 8

    func path(in rect: CGRect) -> Path {
        var path = Path()

        if isLeadingArrow {
            let clampedY = max(rect.minY + cornerRadius + arrowWidth / 2,
                               min(rect.maxY - cornerRadius - arrowWidth / 2, arrowOffset))
            let bodyRect = CGRect(x: rect.minX + arrowHeight, y: rect.minY,
                                  width: rect.width - arrowHeight, height: rect.height)

            path.move(to: CGPoint(x: bodyRect.minX, y: bodyRect.minY + cornerRadius))
            path.addLine(to: CGPoint(x: bodyRect.minX, y: clampedY - arrowWidth / 2))
            path.addLine(to: CGPoint(x: rect.minX, y: clampedY))
            path.addLine(to: CGPoint(x: bodyRect.minX, y: clampedY + arrowWidth / 2))
            path.addLine(to: CGPoint(x: bodyRect.minX, y: bodyRect.maxY - cornerRadius))

            path.addArc(tangent1End: CGPoint(x: bodyRect.minX, y: bodyRect.maxY),
                        tangent2End: CGPoint(x: bodyRect.minX + cornerRadius, y: bodyRect.maxY),
                        radius: cornerRadius)
            path.addLine(to: CGPoint(x: bodyRect.maxX - cornerRadius, y: bodyRect.maxY))
            path.addArc(tangent1End: CGPoint(x: bodyRect.maxX, y: bodyRect.maxY),
                        tangent2End: CGPoint(x: bodyRect.maxX, y: bodyRect.maxY - cornerRadius),
                        radius: cornerRadius)
            path.addLine(to: CGPoint(x: bodyRect.maxX, y: bodyRect.minY + cornerRadius))
            path.addArc(tangent1End: CGPoint(x: bodyRect.maxX, y: bodyRect.minY),
                        tangent2End: CGPoint(x: bodyRect.maxX - cornerRadius, y: bodyRect.minY),
                        radius: cornerRadius)
            path.addLine(to: CGPoint(x: bodyRect.minX + cornerRadius, y: bodyRect.minY))
            path.addArc(tangent1End: CGPoint(x: bodyRect.minX, y: bodyRect.minY),
                        tangent2End: CGPoint(x: bodyRect.minX, y: bodyRect.minY + cornerRadius),
                        radius: cornerRadius)
        } else {
            let clampedX = max(rect.minX + cornerRadius + arrowWidth / 2,
                               min(rect.maxX - cornerRadius - arrowWidth / 2, arrowOffset))
            let bodyRect = CGRect(x: rect.minX, y: rect.minY + arrowHeight,
                                  width: rect.width, height: rect.height - arrowHeight)

            path.move(to: CGPoint(x: bodyRect.minX + cornerRadius, y: bodyRect.minY))
            path.addLine(to: CGPoint(x: clampedX - arrowWidth / 2, y: bodyRect.minY))
            path.addLine(to: CGPoint(x: clampedX, y: rect.minY))
            path.addLine(to: CGPoint(x: clampedX + arrowWidth / 2, y: bodyRect.minY))
            path.addLine(to: CGPoint(x: bodyRect.maxX - cornerRadius, y: bodyRect.minY))

            path.addArc(tangent1End: CGPoint(x: bodyRect.maxX, y: bodyRect.minY),
                        tangent2End: CGPoint(x: bodyRect.maxX, y: bodyRect.minY + cornerRadius),
                        radius: cornerRadius)
            path.addLine(to: CGPoint(x: bodyRect.maxX, y: bodyRect.maxY - cornerRadius))
            path.addArc(tangent1End: CGPoint(x: bodyRect.maxX, y: bodyRect.maxY),
                        tangent2End: CGPoint(x: bodyRect.maxX - cornerRadius, y: bodyRect.maxY),
                        radius: cornerRadius)
            path.addLine(to: CGPoint(x: bodyRect.minX + cornerRadius, y: bodyRect.maxY))
            path.addArc(tangent1End: CGPoint(x: bodyRect.minX, y: bodyRect.maxY),
                        tangent2End: CGPoint(x: bodyRect.minX, y: bodyRect.maxY - cornerRadius),
                        radius: cornerRadius)
            path.addLine(to: CGPoint(x: bodyRect.minX, y: bodyRect.minY + cornerRadius))
            path.addArc(tangent1End: CGPoint(x: bodyRect.minX, y: bodyRect.minY),
                        tangent2End: CGPoint(x: bodyRect.minX + cornerRadius, y: bodyRect.minY),
                        radius: cornerRadius)
        }

        path.closeSubpath()
        return path
    }
}

struct FeatureTourView: View {
    let onFinish: () -> Void
    
    @Default(.appLanguage) var appLanguage: AppLanguage
    @Default(.notchStyle) var notchStyle: NotchStyle
    @State private var currentStepIndex = 0
    @ObservedObject var tourController = FeatureTourController.shared
    @EnvironmentObject var coordinator: NotchPulseViewCoordinator
    @EnvironmentObject var vm: NotchPulseViewModel
    
    private var targetScreen: NSScreen {
        if let preferred = coordinator.preferredScreenUUID.flatMap({ NSScreen.screen(withUUID: $0) }) {
            return preferred
        }
        if let selected = NSScreen.screen(withUUID: coordinator.selectedScreenUUID) {
            return selected
        }
        if let physicalNotchScreen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 || $0.auxiliaryTopLeftArea != nil }) {
            return physicalNotchScreen
        }
        return NSScreen.main ?? NSScreen.screens.first!
    }
    
    private var hasPhysicalNotch: Bool {
        let screen = targetScreen
        return screen.safeAreaInsets.top > 0 || screen.auxiliaryTopLeftArea != nil
    }
    
    private var isDynamicIsland: Bool {
        notchStyle == .dynamicIsland
    }
    
    let steps: [FeatureTourStep] = [
        FeatureTourStep(
            title: "Home Tab & Media Hub",
            description: "Your command center. Control your music, view live lyrics, and access FaceID unlock natively from the Notch.",
            icon: "play.circle.fill",
            tabColor: .pink,
            viewType: .home,
            target: "notch"
        ),
        FeatureTourStep(
            title: "Calendar Expansion",
            description: "Click on the Month & Year header to instantly expand your full-month calendar and view details.",
            icon: "calendar",
            tabColor: .red,
            viewType: .home,
            target: "calendar"
        ),
        FeatureTourStep(
            title: "Notch Shelf",
            description: "Drag and drop files, images, or links directly into the notch. Keep them handy and share them anywhere.",
            icon: "tray.full.fill",
            tabColor: .blue,
            viewType: .shelf,
            target: "shelf"
        ),
        FeatureTourStep(
            title: "System Stats",
            description: "Monitor your Mac's health in real-time. View live CPU, Memory, and GPU usage graphs directly in your status bar. Click on CPU or RAM cards to inspect detailed process breakdown.",
            icon: "chart.xyaxis.line",
            tabColor: .green,
            viewType: .stats,
            target: "stats"
        ),
        FeatureTourStep(
            title: "Temperature & Fan",
            description: "Expand the thermal drawer to monitor CPU/GPU temperatures and adjust your Mac fan speed in real-time.",
            icon: "fanblades.fill",
            tabColor: .teal,
            viewType: .stats,
            target: "fan"
        ),
        FeatureTourStep(
            title: "Clipboard Manager",
            description: "Never lose a copied item again. Quickly access your clipboard history with a single hover.",
            icon: "doc.on.clipboard.fill",
            tabColor: .orange,
            viewType: .clipboard,
            target: "clipboard"
        ),
        FeatureTourStep(
            title: "Audio Hub",
            description: "Switch instantly between speakers, headphones, and microphones. Adjust volume and mute states effortlessly right inside the notch.",
            icon: "speaker.wave.2.fill",
            tabColor: .cyan,
            viewType: .audio,
            target: "audio"
        ),
        FeatureTourStep(
            title: "Display Hub",
            description: "Control built-in and external monitor brightness seamlessly with native hardware DDC/CI controls directly inside the notch.",
            icon: "sun.max.fill",
            tabColor: .yellow,
            viewType: .display,
            target: "display"
        ),
        FeatureTourStep(
            title: "Settings & Options",
            description: "Click the gear icon in the Notch header to open settings and customize NotchPulse to your liking.",
            icon: "gear",
            tabColor: .purple,
            viewType: .home,
            target: "settingsGear"
        )
    ]
    
    var currentStep: FeatureTourStep {
        steps[currentStepIndex]
    }
    
    var body: some View {
        GeometryReader { geometry in
            let screenWidth = geometry.size.width
            let centerX = screenWidth / 2
            
            // Calculate active notch spotlight frame
            let openWidth: CGFloat = vm.notchSize.width > 0 ? vm.notchSize.width : Defaults[.notchOpenWidth]
            let openHeight: CGFloat = vm.effectiveOpenHeight > 0 ? vm.effectiveOpenHeight : 180
            
            let spotlightWidth = openWidth + 24
            let spotlightHeight = openHeight + 14
            let topOffset: CGFloat = isDynamicIsland ? 12 : 0
            
            let isGearTarget = currentStep.target == "settingsGear"
            let gearRect = tourController.settingsGearScreenRect
            let fallbackGearCenterX = centerX + (openWidth / 2) - 14 - (isDynamicIsland ? 22 : 23) - 15
            let fallbackGearCenterY = topOffset + (isDynamicIsland ? 28 : 17)
            let gearCenterX = isGearTarget ? (gearRect?.midX ?? fallbackGearCenterX) : fallbackGearCenterX
            let gearCenterY = isGearTarget ? (gearRect?.midY ?? fallbackGearCenterY) : fallbackGearCenterY
            let gearBoxSize: CGFloat = isGearTarget ? max(38, (gearRect?.width ?? 30) + 8) : 38
            let gearBoxX = gearCenterX - (gearBoxSize / 2)
            let gearBoxY = gearCenterY - (gearBoxSize / 2)
            
            let notchRect = isGearTarget
                ? CGRect(x: gearBoxX, y: gearBoxY, width: gearBoxSize, height: gearBoxSize)
                : CGRect(x: centerX - (spotlightWidth / 2), y: topOffset, width: spotlightWidth, height: spotlightHeight)
            
            let currentCornerRadius: CGFloat = isGearTarget ? (gearBoxSize / 2) : (isDynamicIsland ? 28 : 22)
            
            let cardWidth: CGFloat = 350
            let totalCardWidth: CGFloat = cardWidth + 14
            let notchRight = centerX + (openWidth / 2)
            let anchorRight = isGearTarget ? max(notchRight, gearCenterX + (gearBoxSize / 2)) : notchRight
            let desiredCardX = anchorRight + 14 + (totalCardWidth / 2)
            let maxCardX = screenWidth - (totalCardWidth / 2) - 16
            let cardX = isGearTarget ? min(maxCardX, desiredCardX) : centerX
            
            let cardTop = isGearTarget ? max(10, gearCenterY - 16) : max(10, topOffset)
            let cardEstimatedHeight: CGFloat = 180
            let cardY = isGearTarget ? (cardTop + (cardEstimatedHeight / 2)) : (topOffset + openHeight + 14 + 105)
            let arrowTopPadding = max(8, min(120, gearCenterY - cardTop - 8))
            
            ZStack(alignment: .top) {
                // Dimmed background with spotlight cutout
                SpotlightCutoutShape(
                    notchRect: notchRect,
                    cornerRadius: currentCornerRadius,
                    isDynamicIsland: isDynamicIsland,
                    isFullRounded: isGearTarget
                )
                .fill(Color.black.opacity(0.68), style: FillStyle(eoFill: true))
                .ignoresSafeArea()
                
                // Highlight Clean Border around the open area
                Group {
                    if isGearTarget {
                        Circle()
                            .stroke(Color.white.opacity(0.85), lineWidth: 2)
                            .shadow(color: Color.white.opacity(0.4), radius: 6)
                    } else if isDynamicIsland {
                        RoundedRectangle(cornerRadius: currentCornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(0.6), lineWidth: 1.5)
                            .shadow(color: Color.black.opacity(0.4), radius: 10)
                    } else {
                        UnevenRoundedRectangle(
                            cornerRadii: .init(
                                topLeading: 0,
                                bottomLeading: 22,
                                bottomTrailing: 22,
                                topTrailing: 0
                            )
                        )
                        .stroke(Color.white.opacity(0.4), lineWidth: 1.5)
                        .shadow(color: Color.black.opacity(0.4), radius: 10)
                    }
                }
                .frame(width: notchRect.width, height: notchRect.height)
                .position(x: notchRect.midX, y: notchRect.midY)
                .animation(.spring(response: 0.4, dampingFraction: 0.82), value: currentStepIndex)
                .animation(.spring(response: 0.4, dampingFraction: 0.82), value: openHeight)
                .animation(.spring(response: 0.4, dampingFraction: 0.82), value: openWidth)
                
                // Small Floating Instruction Card
                floatingCard(isGearTarget: isGearTarget, arrowTopPadding: arrowTopPadding, cardWidth: cardWidth)
                    .background(
                        GeometryReader { geo in
                            Color.clear
                                .onAppear {
                                    FeatureTourController.shared.interactiveCardRect = geo.frame(in: .global)
                                }
                                .onChange(of: geo.frame(in: .global)) { _, newFrame in
                                    FeatureTourController.shared.interactiveCardRect = newFrame
                                }
                        }
                    )
                    .position(
                        x: cardX,
                        y: cardY
                    )
                    .animation(.spring(response: 0.4, dampingFraction: 0.82), value: currentStepIndex)
                    .animation(.spring(response: 0.4, dampingFraction: 0.82), value: openHeight)
            }
        }
        .preferredColorScheme(.dark)
        .id("\(appLanguage.rawValue)")
        .onAppear {
            FeatureTourController.shared.isTourActive = true
            repositionWindow()
            updateNotch()
        }
        .onDisappear {
            FeatureTourController.shared.isTourActive = false
            FeatureTourController.shared.interactiveCardRect = nil
            FeatureTourController.shared.settingsGearScreenRect = nil
            teardownNotch()
        }
    }
    
    @ViewBuilder
    private func floatingCard(isGearTarget: Bool, arrowTopPadding: CGFloat, cardWidth: CGFloat) -> some View {
        let bubbleShape = TourSpeechBubbleShape(
            isLeadingArrow: isGearTarget,
            arrowOffset: isGearTarget ? arrowTopPadding : cardWidth / 2,
            cornerRadius: 18,
            arrowWidth: 16,
            arrowHeight: 8
        )

        instructionCardContent
            .padding(.horizontal, 18)
            .padding(.top, isGearTarget ? 18 : 26)
            .padding(.leading, isGearTarget ? 26 : 18)
            .padding(.bottom, 18)
            .padding(.trailing, 18)
            .frame(width: cardWidth + (isGearTarget ? 8 : 0))
            .background(
                bubbleShape
                    .fill(.thickMaterial)
                    .overlay(
                        bubbleShape
                            .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
                    )
            )
            .shadow(color: Color.black.opacity(0.35), radius: 24, x: 0, y: 12)
    }

    private var instructionCardContent: some View {
        VStack(spacing: 14) {
            // Header
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Color.effectiveAccent.opacity(0.18))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: currentStep.icon)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(Color.effectiveAccent)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(loc("Step %d of %d", currentStepIndex + 1, steps.count).uppercased())
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                    
                    Text(loc(currentStep.title))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .id("title_\(currentStepIndex)_\(appLanguage.rawValue)")
                }
                
                Spacer()
                
                Button(action: {
                    teardownNotch()
                    onFinish()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.borderless)
                .help(loc("Close Tour"))
            }
            
            // Description
            Text(loc(currentStep.description))
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.primary.opacity(0.92))
                .lineSpacing(3.5)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .id("desc_\(currentStepIndex)_\(appLanguage.rawValue)")
            
            // Footer Navigation
            HStack(spacing: 10) {
                // Progress Dots
                HStack(spacing: 5) {
                    ForEach(0..<steps.count, id: \.self) { index in
                        Capsule()
                            .fill(index == currentStepIndex ? AnyShapeStyle(Color.effectiveAccent) : AnyShapeStyle(.quaternary))
                            .frame(width: index == currentStepIndex ? 18 : 6, height: 6)
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentStepIndex)
                    }
                }
                
                Spacer()
                
                if currentStepIndex > 0 {
                    Button(loc("Back")) {
                        currentStepIndex -= 1
                        updateNotch()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
                
                Button(action: {
                    if currentStepIndex < steps.count - 1 {
                        currentStepIndex += 1
                        updateNotch()
                    } else {
                        teardownNotch()
                        onFinish()
                    }
                }) {
                    HStack(spacing: 4) {
                        Text(loc(currentStepIndex < steps.count - 1 ? "Next" : "Finish"))
                        if currentStepIndex < steps.count - 1 {
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .tint(Color.effectiveAccent)
            }
        }
    }
    
    private func repositionWindow() {
        guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "OnboardingWindow" || $0.identifier?.rawValue == "FeatureTourWindow" }) else { return }
        window.styleMask = [.borderless, .fullSizeContentView]
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.level = .mainMenu + 2
        
        let screen = targetScreen
        window.setFrame(screen.frame, display: true, animate: true)
    }
    
    private var activeVM: NotchPulseViewModel {
        let appDelegate = (NSApp.delegate as? AppDelegate) ?? AppDelegate.shared
        if Defaults[.showOnAllDisplays], let uuid = targetScreen.displayUUID, let sub = appDelegate?.viewModels[uuid] {
            return sub
        }
        return appDelegate?.vm ?? vm
    }

    private func updateNotch() {
        FeatureTourController.shared.isTourActive = true
        let targetVM = activeVM
        withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
            coordinator.currentView = currentStep.viewType
            targetVM.featureTourTarget = currentStep.target
            CalendarStateViewModel.shared.isFullMonthExpanded = false
            if currentStep.target == "fan" {
                targetVM.customOpenHeight = 300
            } else if currentStep.viewType == .audio {
                AudioDeviceManager.shared.refreshDevices()
                targetVM.customOpenHeight = AudioHubNotchView.calculateHeight(selectedTab: AudioDeviceManager.shared.selectedTab)
            } else if currentStep.viewType == .display {
                BrightnessManager.shared.refreshAllDisplays()
                targetVM.customOpenHeight = DisplayHubNotchView.calculateHeight()
            } else if currentStep.viewType == .clipboard {
                targetVM.customOpenHeight = ClipboardNotchView.preferredHeight
            } else {
                targetVM.customOpenHeight = nil
            }
            targetVM.open()
        }
        
        // Ensure open Notch window stays in front and interactive on every tour step
        let appDelegate = (NSApp.delegate as? AppDelegate) ?? AppDelegate.shared
        appDelegate?.window?.orderFrontRegardless()
        if let winMap = appDelegate?.windows {
            for win in winMap.values {
                win.orderFrontRegardless()
            }
        }
    }
    
    private func teardownNotch() {
        FeatureTourController.shared.isTourActive = false
        FeatureTourController.shared.interactiveCardRect = nil
        CalendarStateViewModel.shared.isFullMonthExpanded = false
        coordinator.currentView = .home
        let targetVM = activeVM
        targetVM.featureTourTarget = nil
        targetVM.customOpenHeight = nil
        targetVM.close(force: true)
    }
}
