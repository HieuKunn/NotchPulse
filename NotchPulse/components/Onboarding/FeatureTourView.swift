//
//  FeatureTourView.swift
//  NotchPulse
//
//  Created for NotchPulse - Spotlight Feature Tour & What's New
//

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
        if isDynamicIsland {
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

struct FeatureTourView: View {
    let onFinish: () -> Void
    
    @Default(.appLanguage) var appLanguage: AppLanguage
    @Default(.notchStyle) var notchStyle: NotchStyle
    @State private var currentStepIndex = 0
    @EnvironmentObject var coordinator: NotchPulseViewCoordinator
    @EnvironmentObject var vm: NotchPulseViewModel
    
    private var hasPhysicalNotch: Bool {
        let screen = NSScreen.main ?? NSScreen.screens.first
        return (screen?.safeAreaInsets.top ?? 0) > 0 || screen?.auxiliaryTopLeftArea != nil
    }
    
    private var isDynamicIsland: Bool {
        notchStyle == .dynamicIsland && !hasPhysicalNotch
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
            description: "Monitor your Mac's health in real-time. View live CPU, Memory, and GPU usage graphs directly in your status bar.",
            icon: "chart.xyaxis.line",
            tabColor: .green,
            viewType: .stats,
            target: "stats"
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
            let openHeight: CGFloat = (vm.customOpenHeight ?? vm.notchSize.height) > 0 ? (vm.customOpenHeight ?? vm.notchSize.height) : 180
            
            let spotlightWidth = openWidth + 24
            let spotlightHeight = openHeight + 14
            let topOffset: CGFloat = isDynamicIsland ? 12 : 0
            
            let notchRect = CGRect(
                x: centerX - (spotlightWidth / 2),
                y: topOffset,
                width: spotlightWidth,
                height: spotlightHeight
            )
            
            ZStack(alignment: .top) {
                // Dimmed background with spotlight cutout
                SpotlightCutoutShape(
                    notchRect: notchRect,
                    cornerRadius: isDynamicIsland ? 28 : 22,
                    isDynamicIsland: isDynamicIsland
                )
                .fill(Color.black.opacity(0.68), style: FillStyle(eoFill: true))
                .ignoresSafeArea()
                
                // Highlight Glowing Border around the open notch area
                Group {
                    if isDynamicIsland {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(currentStep.tabColor.opacity(0.85), lineWidth: 2)
                            .shadow(color: currentStep.tabColor.opacity(0.6), radius: 16)
                    } else {
                        UnevenRoundedRectangle(
                            cornerRadii: .init(
                                topLeading: 0,
                                bottomLeading: 22,
                                bottomTrailing: 22,
                                topTrailing: 0
                            )
                        )
                        .stroke(currentStep.tabColor.opacity(0.85), lineWidth: 2)
                        .shadow(color: currentStep.tabColor.opacity(0.6), radius: 16)
                    }
                }
                .frame(width: spotlightWidth, height: spotlightHeight)
                .position(x: centerX, y: topOffset + (spotlightHeight / 2))
                .animation(.spring(response: 0.4, dampingFraction: 0.82), value: currentStepIndex)
                .animation(.spring(response: 0.4, dampingFraction: 0.82), value: openHeight)
                .animation(.spring(response: 0.4, dampingFraction: 0.82), value: openWidth)
                
                // Small Side / Below Floating Instruction Card
                VStack(spacing: 0) {
                    // Upward pointer arrow
                    Image(systemName: "arrowtriangle.up.fill")
                        .font(.system(size: 18))
                        .foregroundColor(currentStep.tabColor)
                        .shadow(color: currentStep.tabColor.opacity(0.6), radius: 6, y: -2)
                        .zIndex(3)
                    
                    instructionCard
                        .padding(.top, -4)
                }
                .frame(width: 380)
                .position(
                    x: centerX,
                    y: topOffset + spotlightHeight + 14 + 110
                )
                .animation(.spring(response: 0.4, dampingFraction: 0.82), value: currentStepIndex)
                .animation(.spring(response: 0.4, dampingFraction: 0.82), value: openHeight)
            }
        }
        .id("\(appLanguage.rawValue)")
        .onAppear {
            repositionWindow()
            updateNotch()
        }
        .onDisappear {
            teardownNotch()
        }
    }
    
    private var instructionCard: some View {
        VStack(spacing: 16) {
            // Header
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(currentStep.tabColor.opacity(0.18))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: currentStep.icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(currentStep.tabColor)
                        .symbolEffect(.bounce, value: currentStepIndex)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(loc(currentStep.title))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .id("title_\(currentStepIndex)_\(appLanguage.rawValue)")
                    
                    Text(loc("Step %d of %d", currentStepIndex + 1, steps.count))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }
                
                Spacer()
                
                Button(action: {
                    teardownNotch()
                    onFinish()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white.opacity(0.45))
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            // Description
            Text(loc(currentStep.description))
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(.white.opacity(0.85))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .id("desc_\(currentStepIndex)_\(appLanguage.rawValue)")
            
            // Footer Navigation
            HStack(spacing: 8) {
                // Dots
                HStack(spacing: 5) {
                    ForEach(0..<steps.count, id: \.self) { index in
                        Capsule()
                            .fill(index == currentStepIndex ? currentStep.tabColor : Color.white.opacity(0.25))
                            .frame(width: index == currentStepIndex ? 16 : 6, height: 6)
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentStepIndex)
                    }
                }
                
                Spacer()
                
                if currentStepIndex > 0 {
                    Button(action: {
                        currentStepIndex -= 1
                        updateNotch()
                    }) {
                        Text(loc("Back"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.75))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.white.opacity(0.1)))
                    }
                    .buttonStyle(PlainButtonStyle())
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
                                .font(.system(size: 10, weight: .bold))
                        }
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(currentStep.tabColor))
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(18)
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.4), radius: 24, x: 0, y: 12)
    }
    
    private func repositionWindow() {
        guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "OnboardingWindow" }) else { return }
        window.styleMask = [.borderless, .fullSizeContentView]
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.level = .floating
        
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            window.setFrame(screen.frame, display: true, animate: true)
        }
    }
    
    private func updateNotch() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
            coordinator.currentView = currentStep.viewType
            vm.featureTourTarget = currentStep.target
            if currentStep.target == "calendar" {
                vm.customOpenHeight = 350
            } else {
                vm.customOpenHeight = nil
            }
            vm.open()
        }
    }
    
    private func teardownNotch() {
        coordinator.currentView = .home
        vm.featureTourTarget = nil
        vm.customOpenHeight = nil
        vm.close()
    }
}
