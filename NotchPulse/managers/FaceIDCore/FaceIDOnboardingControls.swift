import SwiftUI
import AppKit

/// The primary (accent-filled) or secondary (dark) pill button used for
/// Next/Back/Confirm across every step.
struct PillButton: View {
    enum Style { case primary, secondary }

    let title: String
    var style: Style = .primary
    var width: CGFloat = FaceIDMetrics.primaryButtonWidth
    var isEnabled = true
    /// Return/Enter activates this button when a focused text field doesn't
    /// consume it — same as a Mac dialog's default button.
    var isDefault = false
    let action: () -> Void

    var body: some View {
        let button = Button(action: action) {
            Text(loc(title))
                .font(FaceIDTheme.Font.button)
                .foregroundStyle(style == .primary ? Color.white : Color.primary)
                .frame(width: width, height: FaceIDMetrics.pillButtonHeight)
                .background(background)
                .clipShape(Capsule())
                .overlay(
                    Group {
                        if style == .secondary {
                            Capsule().stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                        }
                    }
                )
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.4)
        .disabled(!isEnabled)

        if isDefault {
            button.keyboardShortcut(.defaultAction)
        } else {
            button
        }
    }

    @ViewBuilder
    private var background: some View {
        if style == .primary {
            Color.effectiveAccent
        } else {
            Color(nsColor: .controlBackgroundColor)
        }
    }
}

/// One row on the Permissions screen: status dot, title/detail, and a Grant
/// pill that disables once granted.
struct PermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool
    let grant: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(granted ? FaceIDTheme.statusGranted : FaceIDTheme.statusDenied)
                .frame(width: FaceIDMetrics.statusDotSize, height: FaceIDMetrics.statusDotSize)

            VStack(alignment: .leading, spacing: 1) {
                Text(loc(title))
                    .font(FaceIDTheme.Font.rowTitle)
                    .foregroundStyle(.primary)
                Text(loc(detail))
                    .font(FaceIDTheme.Font.rowDetail)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            Spacer(minLength: 4)

            Button(action: grant) {
                Text(granted ? loc("Granted") : loc("Grant"))
                    .font(FaceIDTheme.Font.grantLabel)
                    .foregroundStyle(.primary)
                    .frame(width: FaceIDMetrics.grantButtonSize.width, height: FaceIDMetrics.grantButtonSize.height)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)
            .disabled(granted)
            .opacity(granted ? 0.6 : 1)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .frame(height: FaceIDMetrics.permissionRowHeight)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.6))
        .clipShape(Capsule())
    }
}

/// The password entry field — a pill-shaped `SecureField`.
struct PillSecureField: View {
    let placeholder: String
    @Binding var text: String
    var autofocus = false
    var onSubmit: () -> Void = {}
    @FocusState private var isFocused: Bool

    var body: some View {
        SecureField("", text: $text, prompt: Text(loc(placeholder)).foregroundStyle(.secondary))
            .textFieldStyle(.plain)
            .font(FaceIDTheme.Font.passwordPlaceholder)
            .foregroundStyle(.primary)
            .focused($isFocused)
            .onSubmit(onSubmit)
            .background(OnboardingFieldFirstResponder(enabled: autofocus, onReady: { isFocused = true }))
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(isFocused ? AnyShapeStyle(Color.effectiveAccent) : AnyShapeStyle(Color.primary.opacity(0.12)), lineWidth: isFocused ? 1.5 : 0.5)
            )
    }
}

/// The plain-text twin of `PillSecureField`, used by the naming step. Same
/// capsule so the two read as one control family — only the echo differs.
struct PillTextField: View {
    let placeholder: String
    @Binding var text: String
    var autofocus = false
    var onSubmit: () -> Void = {}
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("", text: $text, prompt: Text(loc(placeholder)).foregroundStyle(.secondary))
            .textFieldStyle(.plain)
            .font(FaceIDTheme.Font.passwordPlaceholder)
            .foregroundStyle(.primary)
            .focused($isFocused)
            .onSubmit(onSubmit)
            .background(OnboardingFieldFirstResponder(enabled: autofocus, onReady: { isFocused = true }))
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(isFocused ? AnyShapeStyle(Color.effectiveAccent) : AnyShapeStyle(Color.primary.opacity(0.12)), lineWidth: isFocused ? 1.5 : 0.5)
            )
    }
}

/// Makes a notch-hosted field first responder after the step spring finishes. SwiftUI's
/// `.focused` alone is ignored while the panel is still becoming key.
private struct OnboardingFieldFirstResponder: NSViewRepresentable {
    let enabled: Bool
    let onReady: () -> Void

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard enabled, !context.coordinator.didSchedule else { return }
        context.coordinator.didSchedule = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(FaceIDMetrics.fieldAutofocusDelay))
            NSApp.activate(ignoringOtherApps: true)
            for _ in 0..<8 {
                if nsView.window != nil { break }
                try? await Task.sleep(for: .milliseconds(50))
            }
            guard let window = nsView.window else { return }
            window.makeKeyAndOrderFront(nil)
            if let field = nearestTextField(from: nsView) {
                window.makeFirstResponder(field)
            }
            onReady()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var didSchedule = false }
}

private func nearestTextField(from view: NSView) -> NSView? {
    var current: NSView? = view.superview
    while let node = current {
        if let field = firstTextField(in: node) { return field }
        current = node.superview
    }
    return nil
}

private func firstTextField(in view: NSView) -> NSView? {
    if view is NSTextField { return view }
    for child in view.subviews {
        if let found = firstTextField(in: child) { return found }
    }
    return nil
}
