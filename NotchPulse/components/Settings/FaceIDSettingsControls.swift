import SwiftUI
import AppKit
import Defaults

/// What a tab's icon actually is — a built-in SF Symbol, or a template
/// image from the asset catalog for marks with no SF Symbol equivalent.
enum SettingsTabIcon {
    case system(String)
    case asset(String)
}

/// The colored rounded-squircle tile behind a tab's glyph — the same
/// per-category icon treatment macOS System Settings uses.
struct SettingsTabIconBadge: View {
    let icon: SettingsTabIcon
    let gradientColors: [Color]
    let size: CGFloat
    let cornerRadius: CGFloat
    let iconSize: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(LinearGradient(colors: gradientColors, startPoint: .top, endPoint: .bottom))
            .frame(width: size, height: size)
            .overlay(glyph)
    }

    @ViewBuilder
    private var glyph: some View {
        switch icon {
        case .system(let name):
            Image(systemName: name)
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(.white)
        case .asset(let name):
            Image(name)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(.white)
                .frame(width: iconSize, height: iconSize)
        }
    }
}

/// Small "i" glyph that reveals a short explanation in a native popover on tap.
struct SettingsInfoButton: View {
    let text: String
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("More information")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            Text(text)
                .font(.caption)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 220, alignment: .leading)
                .padding(12)
        }
    }
}

/// Long-press button with animated progress indicator to prevent accidental deletions.
struct HoldToConfirmButton: View {
    let title: String
    var holdDuration: TimeInterval = 3
    let action: () -> Void

    @State private var fillProgress: CGFloat = 0

    var body: some View {
        Text(title.localized)
            .font(.caption.weight(.medium))
            .foregroundStyle(fillProgress > 0.5 ? .white : Color.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Color(nsColor: .quaternaryLabelColor)
                        Rectangle()
                            .fill(Color.red)
                            .frame(width: proxy.size.width * fillProgress)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .onLongPressGesture(minimumDuration: holdDuration) {
                action()
            } onPressingChanged: { isPressing in
                withAnimation(.linear(duration: isPressing ? holdDuration : 0.18)) {
                    fillProgress = isPressing ? 1 : 0
                }
            }
    }
}

/// A row of `SettingsOptionTile`s with native spacing.
struct SettingsOptionRow<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 12) {
            content()
        }
        .padding(.vertical, 4)
    }
}

/// One selectable preview tile: artwork on a filled rounded rect, a label
/// beneath, and an accent ring when selected.
struct SettingsOptionTile<Preview: View>: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    var previewHeight: CGFloat = 64
    @ViewBuilder var preview: () -> Preview

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                preview()
                    .frame(maxWidth: .infinity)
                    .frame(height: previewHeight)
                    .background(Color(nsColor: .quaternaryLabelColor).opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(
                                isSelected ? Color.effectiveAccent : Color(nsColor: .separatorColor).opacity(0.3),
                                lineWidth: isSelected ? 2 : 0.5
                            )
                    )

                Text(title.localized)
                    .font(.caption)
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Unlock animation picker — presents minimal vs original preview styles.
struct UnlockAnimationPicker: View {
    @Binding var selection: UnlockAnimationStyle
    var isEnabled: Bool = true
    @Default(.notchStyle) private var notchStyle

    private static let previewHoldDuration: Duration = .seconds(1.5)

    var body: some View {
        SettingsOptionRow {
            ForEach(UnlockAnimationStyle.selectableCases) { style in
                SettingsOptionTile(
                    title: style.title,
                    isSelected: selection == style,
                    action: { selectAndPreview(style) },
                    previewHeight: 80
                ) {
                    preview(for: style, isSelected: selection == style)
                }
            }
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
    }

    private func selectAndPreview(_ style: UnlockAnimationStyle) {
        selection = style
        FaceIDOverlayController.shared.present(styleOverride: style)
        Task {
            try? await Task.sleep(for: Self.previewHoldDuration)
            FaceIDOverlayController.shared.finish(success: true)
        }
    }

    @ViewBuilder
    private func preview(for style: UnlockAnimationStyle, isSelected: Bool) -> some View {
        let isNotch = notchStyle == .notch
        switch style {
        case .minimal:
            if isNotch {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 16)

                        Spacer(minLength: 20)

                        UnlockStillThumbnail()
                            .frame(width: 14, height: 14)
                    }
                    .padding(.horizontal, 8)
                    .frame(width: 110, height: 20)
                    .background(Color.black)
                    .clipShape(NotchShape(topCornerRadius: 4, bottomCornerRadius: 8))

                    Spacer()
                }
                .padding(.top, 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 16)

                        Spacer(minLength: 16)

                        UnlockStillThumbnail()
                            .frame(width: 14, height: 14)
                    }
                    .padding(.horizontal, 8)
                    .frame(width: 110, height: 20)
                    .background(Color.black, in: Capsule(style: .continuous))

                    Spacer()
                }
                .padding(.top, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .original:
            if isNotch {
                VStack(spacing: 0) {
                    ZStack {
                        Color.black
                        UnlockStillThumbnail()
                            .frame(width: 26, height: 26)
                    }
                    .frame(width: 60, height: 48)
                    .clipShape(NotchShape(topCornerRadius: 4, bottomCornerRadius: 10))

                    Spacer()
                }
                .padding(.top, 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    ZStack {
                        Color.black
                        UnlockStillThumbnail()
                            .frame(width: 26, height: 26)
                    }
                    .frame(width: 54, height: 46)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    Spacer()
                }
                .padding(.top, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .none:
            EmptyView()
        }
    }
}

private struct UnlockStillThumbnail: View {
    var body: some View {
        if let url = Bundle.main.url(forResource: "unlockstatic", withExtension: "png"),
           let nsImage = NSImage(contentsOf: url) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "faceid")
                .foregroundStyle(.white)
        }
    }
}

/// Liveness depth picker: Light vs Heavy.
struct LivenessModePicker: View {
    @Binding var selection: LivenessMode
    var isEnabled: Bool = true

    var body: some View {
        SettingsOptionRow {
            ForEach(LivenessMode.allCases) { mode in
                SettingsOptionTile(
                    title: mode.title,
                    isSelected: selection == mode,
                    action: { selection = mode },
                    previewHeight: 48
                ) {
                    Image(systemName: iconName(for: mode))
                        .font(.system(size: 18))
                        .foregroundStyle(selection == mode ? Color.effectiveAccent : Color.secondary)
                }
            }
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
    }

    private func iconName(for mode: LivenessMode) -> String {
        switch mode {
        case .light: return "sun.min.fill"
        case .heavy: return "sun.max.fill"
        }
    }
}

/// Multi-select picker for what arms Face Unlock.
struct UnlockTriggerPicker: View {
    @Binding var selection: Set<UnlockTrigger>
    var isEnabled: Bool = true

    var body: some View {
        SettingsOptionRow {
            ForEach(UnlockTrigger.allCases) { trigger in
                let isSelected = selection.contains(trigger)
                SettingsOptionTile(
                    title: trigger.title,
                    isSelected: isSelected,
                    action: { toggle(trigger, isSelected: isSelected) },
                    previewHeight: 48
                ) {
                    Image(systemName: trigger.iconName)
                        .font(.system(size: 18))
                        .foregroundStyle(isSelected ? Color.effectiveAccent : Color.secondary)
                }
            }
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
    }

    private func toggle(_ trigger: UnlockTrigger, isSelected: Bool) {
        guard isSelected else {
            selection.insert(trigger)
            return
        }
        guard selection.count > 1 else { return }
        selection.remove(trigger)
    }
}
