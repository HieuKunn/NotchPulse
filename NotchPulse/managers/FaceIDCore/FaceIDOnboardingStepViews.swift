//
//  FaceIDOnboardingStepViews.swift
//  NotchPulse
//
//  The screens of the notch-hosted onboarding flow. Each fills whatever panel size
//  FaceIDEnrollmentController reports for its step — sizing itself is the notch window's job.
//

import SwiftUI
import AppKit

// MARK: - 1. Intro

struct IntroStepView: View {
    let controller: FaceIDEnrollmentController

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("NotchPulse")
                    .font(FaceIDTheme.Font.title)
                    .foregroundStyle(FaceIDTheme.textPrimary)
                Text("Face Unlock for Mac")
                    .font(FaceIDTheme.Font.button)
                    .foregroundStyle(FaceIDTheme.textSecondary)

                Spacer(minLength: 12)

                PillButton(title: "Next") {
                    controller.advance()
                }
            }
            .padding(.leading, 4)
            Spacer(minLength: 4)
            NotchPulseLogoView()
                .frame(width: 106, height: 106)
                .padding(.top, 4)
        }
        .onboardingContentPadding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(FaceIDTheme.panel)
        .onAppear {
            controller.playIntroSweepIfNeeded()
        }
    }
}

private struct NotchPulseLogoView: View {
    var body: some View {
        if Bundle.main.url(forResource: "logoanimation", withExtension: "mp4") != nil {
            LoopingVideoView(resourceName: "logoanimation")
        } else if Bundle.main.url(forResource: "idleanimation", withExtension: "mp4") != nil {
            LoopingVideoView(resourceName: "idleanimation")
        } else if let appIcon = NSImage(named: "AppIcon") {
            Image(nsImage: appIcon)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
        } else {
            Image(systemName: "teddybear.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.effectiveAccent)
        }
    }
}

// MARK: - 2. Permissions

struct PermissionsStepView: View {
    let controller: FaceIDEnrollmentController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Permissions")
                .font(FaceIDTheme.Font.title)
                .foregroundStyle(FaceIDTheme.textPrimary)
                .padding(.leading, 4)

            // Spacer(minLength: 0)

            PermissionRow(
                title: "Accessibility",
                detail: "Allow NotchPulse to unlock your Mac",
                granted: controller.accessibilityGranted
            ) { controller.grantAccessibility() }

            PermissionRow(
                title: "Camera",
                detail: "Allow NotchPulse to recognize your face",
                granted: controller.cameraPermission == .granted
            ) { controller.grantCamera() }

            // Spacer(minLength: 0)

            HStack(spacing: 10) {
                PillButton(title: "Back", style: .secondary) {
                    controller.back()
                }
                PillButton(title: "Next", isEnabled: controller.bothPermissionsGranted) {
                    controller.advance()
                }
            }
        }
        .onboardingContentPadding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(FaceIDTheme.panel)
    }
}

// MARK: - 3. Security notice

struct SecurityNoticeStepView: View {
    let controller: FaceIDEnrollmentController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(FaceIDTheme.textPrimary)
                .padding(.top, 6)
                .padding(.leading, 4)

            Text("NotchPulse is not as secure as Apple's FaceID or TouchID.")
                .font(FaceIDTheme.Font.title)
                .foregroundStyle(FaceIDTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 4)

            Text("It uses your Mac's standard webcam and is designed for convenience, not high-security authentication.")
                .font(FaceIDTheme.Font.passwordCaption)
                .foregroundStyle(FaceIDTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 4)

            Spacer(minLength: 8)

            HStack(spacing: 10) {
                if controller.isPostUpdateNotice {
                    // Declining isn't a real option here — see `declinePostUpdateNotice()`.
                    PillButton(title: "No thanks", style: .secondary) {
                        controller.declinePostUpdateNotice()
                    }
                } else {
                    PillButton(title: "Back", style: .secondary) {
                        controller.back()
                    }
                }
                PillButton(title: "I understand", isDefault: true) {
                    controller.advance()
                }
            }
        }
        .onboardingContentPadding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(FaceIDTheme.panel)
    }
}

// MARK: - 4. Pre set-up

struct PreSetupStepView: View {
    let controller: FaceIDEnrollmentController

    var body: some View {
        VStack(spacing: 2) {
            HStack(alignment: .top, spacing: 2) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Set up Face\nRecognition")
                        .font(FaceIDTheme.Font.title)
                        .foregroundStyle(FaceIDTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Follow the directions\nshown on the screen")
                        .font(FaceIDTheme.Font.button)
                        .foregroundStyle(FaceIDTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 10)
                .padding(.leading, 4)
                Spacer(minLength: 0)
                UnlockGlyphView()
                    .frame(width: 120, height: 120)
            }
            Spacer(minLength: 4)

            HStack(spacing: 10) {
                PillButton(title: "Back", style: .secondary) {
                    controller.back()
                }
                PillButton(title: "Next") {
                    controller.advance()
                }
            }
        }
        .onboardingContentPadding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(FaceIDTheme.panel)
    }
}

private struct UnlockGlyphView: View {
    var body: some View {
        LoopingVideoView(resourceName: "idleanimation")
    }
}

// MARK: - 5-7. Guided enrollment (camera + tick ring + camera-complete)

struct EnrollStepView: View {
    let controller: FaceIDEnrollmentController
    @Environment(\.notchPanelStyle) private var style

    var body: some View {
        VStack(spacing: 0) {
            cameraCluster
                .padding(.top, cameraTopPadding)
            Spacer(minLength: 8)
            instructionLabel
                .padding(.horizontal, FaceIDMetrics.enrollInstructionHorizontalPadding)
                .padding(.bottom, FaceIDMetrics.enrollInstructionBottomPadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) {
            if showsCloseButton {
                EnrollmentCloseButton {
                    controller.dismiss()
                }
                .padding(FaceIDMetrics.enrollCloseButtonEdgePadding)
            }
        }
        .background(FaceIDTheme.panel)
    }

    private var showsCloseButton: Bool {
        !controller.enrollmentComplete && !controller.showCheckmark
    }

    private var cameraTopPadding: CGFloat {
        style == .pill
            ? FaceIDMetrics.enrollCameraTopPaddingPill
            : FaceIDMetrics.enrollCameraTopPaddingNotch
    }

    private var cameraCluster: some View {
        ZStack {
            FaceIDEnrollmentRingView(controller: controller)

            FaceIDCameraPreviewView(session: controller.camera.session, faces: [])
                .frame(
                    width: FaceIDMetrics.cameraCircleDiameter,
                    height: FaceIDMetrics.cameraCircleDiameter
                )
                .clipShape(Circle())
                .opacity(controller.cameraPreviewVisible ? 1 : 0)
                .animation(
                    .easeInOut(duration: FaceIDMetrics.previewFadeOut),
                    value: controller.cameraPreviewVisible
                )
                .overlay {
                    if controller.isTooFar && controller.cameraPreviewVisible && !controller.showCheckmark {
                        EnrollmentTooFarChevron()
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: controller.isTooFar)

            if controller.showCheckmark {
                AnimatedCheckmark(color: FaceIDTheme.accent, lineWidth: 8)
                    .frame(width: 70, height: 59)
                    .transition(.opacity)
                    .padding(.top, 4)
            }
        }
        .frame(
            width: FaceIDMetrics.enrollCameraClusterDiameter,
            height: FaceIDMetrics.enrollCameraClusterDiameter
        )
    }

    private var instructionLabel: some View {
        Text(controller.enrollmentInstruction)
            .font(FaceIDTheme.Font.instruction)
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .id(controller.enrollmentInstruction)
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.2), value: controller.enrollmentInstruction)
            .opacity(controller.guideVisible ? 1 : 0)
            .animation(
                .easeInOut(
                    duration: controller.guideVisible
                        ? FaceIDMetrics.enrollInstructionFadeIn
                        : FaceIDMetrics.enrollInstructionFadeOut
                ),
                value: controller.guideVisible
            )
    }
}

private struct EnrollmentCloseButton: View {
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(isHovering ? 1 : 0.8))
                .frame(
                    width: FaceIDMetrics.enrollCloseButtonSize,
                    height: FaceIDMetrics.enrollCloseButtonSize
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel("Close")
    }
}

private struct EnrollmentTooFarChevron: View {
    var body: some View {
        if #available(macOS 15.0, *) {
            Image(systemName: "chevron.up.2")
                .font(.system(size: FaceIDMetrics.enrollTooFarChevronSize, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.45), radius: 6, y: 1)
                .symbolEffect(.bounce.up.byLayer, options: .repeating)
                .accessibilityHidden(true)
        } else {
            Image(systemName: "chevron.up.2")
                .font(.system(size: FaceIDMetrics.enrollTooFarChevronSize, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.45), radius: 6, y: 1)
                .symbolEffect(.pulse, options: .repeating)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - 8. Name

/// Asks who was just captured — for a recapture, pre-filled with the existing name so
/// this doubles as rename.
struct NameStepView: View {
    @Bindable var controller: FaceIDEnrollmentController

    private var trimmedName: String {
        controller.pendingName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Name this face")
                .font(FaceIDTheme.Font.title)
                .foregroundStyle(FaceIDTheme.textPrimary)
                .padding(.leading, 4)

            Text("Used to tell enrolled faces apart when more than one person is set up on this Mac.")
                .font(FaceIDTheme.Font.passwordCaption)
                .foregroundStyle(FaceIDTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 4)

            Spacer(minLength: 2)

            PillTextField(placeholder: "Enter a name...", text: $controller.pendingName, autofocus: true) {
                controller.confirmName()
            }

            if let error = controller.nameError {
                Text(error)
                    .font(FaceIDTheme.Font.rowDetail)
                    .foregroundStyle(FaceIDTheme.statusDenied)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                PillButton(title: "Back", style: .secondary) {
                    controller.back()
                }
                PillButton(title: controller.nameStepPrimaryTitle, isEnabled: !trimmedName.isEmpty, isDefault: true) {
                    controller.confirmName()
                }
            }
        }
        .onboardingContentPadding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(FaceIDTheme.panel)
    }
}

// MARK: - 9. Password

struct PasswordStepView: View {
    let controller: FaceIDEnrollmentController

    @State private var password = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Enter your password")
                .font(FaceIDTheme.Font.title)
                .foregroundStyle(FaceIDTheme.textPrimary)
                .padding(.leading, 4)

            Text("Your password is required to unlock your Mac. It is encrypted and securely stored on your device. NotchPulse works entirely offline, so your password never leaves your Mac.")
                .font(FaceIDTheme.Font.passwordCaption)
                .foregroundStyle(FaceIDTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 4)

            Spacer(minLength: 2)

            PillSecureField(placeholder: "Enter password...", text: $password, autofocus: true) {
                guard !password.isEmpty, !controller.isSavingPassword else { return }
                Task { _ = await controller.finish(password: password) }
            }

            if let error = controller.passwordError {
                Text(error)
                    .font(FaceIDTheme.Font.rowDetail)
                    .foregroundStyle(FaceIDTheme.statusDenied)
            }

            // Spacer(minLength: 0)

            HStack(spacing: 10) {
                PillButton(title: "Back", style: .secondary) {
                    controller.back()
                }
                PillButton(
                    title: controller.isSavingPassword ? "Saving…" : "Confirm",
                    isEnabled: !password.isEmpty && !controller.isSavingPassword,
                    isDefault: true
                ) {
                    Task { _ = await controller.finish(password: password) }
                }
            }
        }
        .onboardingContentPadding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(FaceIDTheme.panel)
    }
}

// MARK: - 10. Complete

struct CompleteStepView: View {
    var body: some View {
        HStack(spacing: 12) {
            Text("You're all set")
                .font(FaceIDTheme.Font.title)
                .foregroundStyle(FaceIDTheme.textPrimary)
            Spacer(minLength: 4)
            AnimatedCheckmark(color: .white, lineWidth: 5)
                .frame(width: 20, height: 15)
        }
        .onboardingContentHorizontalPadding()
        .padding(.top, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(FaceIDTheme.panel)
    }
}
