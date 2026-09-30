//
//  FeatureTourView.swift
//  NotchPulse
//
//  Created by Antigravity
//

import SwiftUI

struct FeatureTourStep {
    let title: String
    let description: String
    let icon: String
    let tabColor: Color
    let viewType: NotchViews
    let target: String?
}

struct FeatureTourView: View {
    let onFinish: () -> Void
    
    @State private var currentStepIndex = 0
    @EnvironmentObject var coordinator: NotchPulseViewCoordinator
    @EnvironmentObject var vm: NotchPulseViewModel
    
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
            tabColor: .gray,
            viewType: .home,
            target: "settingsGear"
        )
    ]
    
    var currentStep: FeatureTourStep {
        steps[currentStepIndex]
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // A simple pointer to the notch!
            Image(systemName: "arrowtriangle.up.fill")
                .font(.system(size: 24))
                .foregroundColor(currentStep.tabColor)
                .shadow(color: currentStep.tabColor.opacity(0.5), radius: 5, x: 0, y: -2)
                .padding(.top, -14)
                .zIndex(2)

            VStack(spacing: 16) {
                HStack(spacing: 16) {
                    Image(systemName: currentStep.icon)
                        .font(.system(size: 32, weight: .light))
                        .foregroundColor(currentStep.tabColor)
                        .symbolEffect(.bounce, value: currentStepIndex)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(loc(currentStep.title))
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                            .id("title_\(currentStepIndex)")
                            .transition(.opacity)
                        
                        Text(loc(currentStep.description))
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                            .id("desc_\(currentStepIndex)")
                            .transition(.opacity)
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                
                HStack(spacing: 8) {
                    ForEach(0..<steps.count, id: \.self) { index in
                        Circle()
                            .fill(index == currentStepIndex ? steps[index].tabColor : Color.secondary.opacity(0.3))
                            .frame(width: index == currentStepIndex ? 8 : 6, height: index == currentStepIndex ? 8 : 6)
                            .animation(.spring(), value: currentStepIndex)
                    }
                    Spacer()
                    
                    if currentStepIndex > 0 {
                        Button("Back") {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                currentStepIndex -= 1
                                updateNotch()
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        .foregroundColor(.secondary)
                        .font(.system(size: 12, weight: .medium))
                    }
                    
                    Button(action: {
                        if currentStepIndex < steps.count - 1 {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                currentStepIndex += 1
                                updateNotch()
                            }
                        } else {
                            onFinish()
                        }
                    }) {
                        Text(currentStepIndex < steps.count - 1 ? "Next" : "Finish")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(currentStep.tabColor))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
            .background(
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.1), lineWidth: 1))
            )
            .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        }
        .frame(width: 360)
        .padding(.top, 10)
        .onAppear {
            repositionWindow()
            updateNotch()
        }
        .onDisappear {
            vm.featureTourTarget = nil
            vm.close()
        }
    }
    
    private func repositionWindow() {
        guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "OnboardingWindow" }) else { return }
        window.styleMask = [.borderless, .fullSizeContentView]
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        
        if let screen = NSScreen.main {
            let width: CGFloat = 360
            let height: CGFloat = 160
            let yPos = screen.frame.maxY - 250
            window.setFrame(NSRect(x: screen.frame.midX - (width/2), y: yPos, width: width, height: height), display: true, animate: true)
        }
    }
    
    private func updateNotch() {
        coordinator.currentView = currentStep.viewType
        vm.featureTourTarget = currentStep.target
        vm.open()
    }
}
