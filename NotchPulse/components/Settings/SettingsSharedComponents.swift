import AppKit
import Defaults
import SwiftUI

// MARK: - Native Header Bar with Frosted Glass (.bar)
struct SettingsDetailHeaderBar: View {
    let title: String
    var showQuitButton: Bool = false
    @Default(.appLanguage) private var appLanguage

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()

                if showQuitButton {
                    Button(role: .destructive) {
                        if let appDelegate = NSApp.delegate as? AppDelegate {
                            appDelegate.isUserInitiatedQuit = true
                            appDelegate.quitApplication()
                        } else if let appDelegate = AppDelegate.shared {
                            appDelegate.isUserInitiatedQuit = true
                            appDelegate.quitApplication()
                        }
                    } label: {
                        Label(loc("Quit app"), systemImage: "power")
                            .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 24)
            .frame(height: 52)

            Divider()
        }
        .background(.bar)
    }
}

// MARK: - Notch Width Live Preview
struct NotchWidthLivePreview: View {
    let width: CGFloat
    let style: NotchStyle

    private var previewBarWidth: CGFloat {
        let normalized = (width - 560.0) / (960.0 - 560.0)
        let scaled = 160.0 + normalized * 200.0
        return max(160.0, min(360.0, scaled))
    }

    @ViewBuilder
    private var notchBackgroundShape: some View {
        if style == .dynamicIsland {
            Capsule().fill(Color.black)
        } else {
            UnevenRoundedRectangle(
                cornerRadii: .init(
                    topLeading: 0,
                    bottomLeading: 12,
                    bottomTrailing: 12,
                    topTrailing: 0
                )
            ).fill(Color.black)
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .frame(height: 64)
                    .overlay(
                        Rectangle()
                            .fill(Color.primary.opacity(0.04))
                            .frame(height: 20),
                        alignment: .top
                    )

                VStack(spacing: 0) {
                    if style == .dynamicIsland {
                        Spacer().frame(height: 6)
                    }

                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.black.opacity(0.8))
                            .frame(width: 8, height: 8)

                        Spacer()

                        Text("\(Int(width)) px")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)

                        Spacer()

                        Image(systemName: "waveform")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.effectiveAccent)
                    }
                    .padding(.horizontal, 12)
                    .frame(width: previewBarWidth, height: 28)
                    .background(notchBackgroundShape)
                    .animation(.spring(response: 0.25, dampingFraction: 0.8), value: width)
                    .animation(.spring(response: 0.25, dampingFraction: 0.8), value: style)
                }
            }
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(.separator, lineWidth: 0.5)
            )

            HStack {
                Text(loc("560 px (Compact)"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Text(loc("Live preview active on Notch"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(loc("960 px (Extra Wide)"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Native Semantic Badges
func customBadge(text: String) -> some View {
    Text(text)
        .foregroundStyle(.secondary)
        .font(.footnote.weight(.medium))
        .padding(.vertical, 2)
        .padding(.horizontal, 6)
        .background(Color(nsColor: .quaternaryLabelColor).opacity(0.2))
        .clipShape(Capsule())
}

func comingSoonTag() -> some View {
    customBadge(text: loc("Coming soon"))
}

func warningBadge(_ text: String, _ description: String) -> some View {
    Section {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text(text)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

func lighterColor(from nsColor: NSColor, amount: CGFloat = 0.14) -> Color {
    let srgb = nsColor.usingColorSpace(.sRGB) ?? nsColor
    var (r, g, b, a): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
    srgb.getRed(&r, green: &g, blue: &b, alpha: &a)

    func lighten(_ c: CGFloat) -> CGFloat {
        let increased = c + (1.0 - c) * amount
        return min(max(increased, 0), 1)
    }

    let nr = lighten(r)
    let ng = lighten(g)
    let nb = lighten(b)

    return Color(red: Double(nr), green: Double(ng), blue: Double(nb), opacity: Double(a))
}
