//
//  OnboardingFinishView.swift
//  NotchPulse
//
//  Created by Alexander on 2025-06-23.
//


import SwiftUI

struct OnboardingFinishView: View {
    let onFinish: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 60))
                .foregroundColor(.effectiveAccent)
                .padding()

            Text(loc("You're All Set!"))
                .font(.largeTitle)
                .fontWeight(.bold)

            Text(loc("You can now enjoy the app. If you want to tweak things further, you can always visit the settings."))
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Spacer()
            Spacer()

            VStack(spacing: 12) {
                Button(action: onOpenSettings) {
                    Label(loc("Customize in Settings"), systemImage: "gear")
                        .controlSize(.large)
                }
                .controlSize(.large)

                Button(loc("Finish"), action: onFinish)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()
        )
    }
}

#Preview {
    OnboardingFinishView(onFinish: { }, onOpenSettings: { })
}
