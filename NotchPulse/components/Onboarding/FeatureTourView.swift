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
            viewType: .home
        ),
        FeatureTourStep(
            title: "Notch Shelf",
            description: "Drag and drop files, images, or links directly into the notch. Keep them handy and share them anywhere.",
            icon: "tray.full.fill",
            tabColor: .blue,
            viewType: .shelf
        ),
        FeatureTourStep(
            title: "System Stats",
            description: "Monitor your Mac's health in real-time. View live CPU, Memory, and GPU usage graphs directly in your status bar.",
            icon: "chart.xyaxis.line",
            tabColor: .green,
            viewType: .stats
        ),
        FeatureTourStep(
            title: "Clipboard Manager",
            description: "Never lose a copied item again. Quickly access your clipboard history with a single hover.",
            icon: "doc.on.clipboard.fill",
            tabColor: .orange,
            viewType: .clipboard
        )
    ]
    
    var currentStep: FeatureTourStep {
        steps[currentStepIndex]
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            ZStack {
                currentStep.tabColor.opacity(0.15)
                    .ignoresSafeArea()
                
                VStack(spacing: 16) {
                    Image(systemName: currentStep.icon)
                        .font(.system(size: 60, weight: .light))
                        .foregroundColor(currentStep.tabColor)
                        .shadow(color: currentStep.tabColor.opacity(0.5), radius: 10, x: 0, y: 5)
                        .symbolEffect(.bounce, value: currentStepIndex)
                    
                    Text(loc(currentStep.title))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                        .id("title_\(currentStepIndex)")
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                }
                .padding(.top, 40)
                .padding(.bottom, 30)
            }
            .frame(height: 240)
            
            // Content
            VStack(spacing: 24) {
                Text(loc(currentStep.description))
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
                    .padding(.horizontal, 32)
                    .id("desc_\(currentStepIndex)")
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                
                Spacer()
                
                // Indicators
                HStack(spacing: 8) {
                    ForEach(0..<steps.count, id: \.self) { index in
                        Circle()
                            .fill(index == currentStepIndex ? steps[index].tabColor : Color.secondary.opacity(0.3))
                            .frame(width: index == currentStepIndex ? 10 : 8, height: index == currentStepIndex ? 10 : 8)
                            .animation(.spring(), value: currentStepIndex)
                    }
                }
                .padding(.bottom, 16)
                
                // Buttons
                HStack(spacing: 16) {
                    if currentStepIndex > 0 {
                        Button(action: {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                currentStepIndex -= 1
                                updateNotch()
                            }
                        }) {
                            Text(loc("Back"))
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.primary)
                                .frame(width: 100)
                                .padding(.vertical, 12)
                                .background(Capsule().fill(Color.secondary.opacity(0.1)))
                        }
                        .buttonStyle(PlainButtonStyle())
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
                        Text(currentStepIndex < steps.count - 1 ? loc("Next") : loc("Get Started"))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: currentStepIndex < steps.count - 1 ? 140 : 200)
                            .padding(.vertical, 12)
                            .background(
                                Capsule()
                                    .fill(currentStep.tabColor)
                                    .shadow(color: currentStep.tabColor.opacity(0.4), radius: 8, x: 0, y: 4)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.bottom, 32)
            }
            .padding(.top, 32)
        }
        .frame(width: 440, height: 540)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
        .onAppear {
            updateNotch()
        }
        .onDisappear {
            vm.close()
        }
    }
    
    private func updateNotch() {
        // Force the notch to open and show the corresponding tab to demonstrate!
        coordinator.currentView = currentStep.viewType
        vm.open()
    }
}
