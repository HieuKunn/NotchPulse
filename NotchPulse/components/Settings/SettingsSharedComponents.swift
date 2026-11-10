import AVFoundation
import AppKit
import SwiftUI

// MARK: - Highlight Key & Environment

struct SettingsHighlightedIdKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    var settingsHighlightedId: String? {
        get { self[SettingsHighlightedIdKey.self] }
        set { self[SettingsHighlightedIdKey.self] = newValue }
    }
}

struct SettingsSearchHighlightModifier: ViewModifier {
    let isHighlighted: Bool

    func body(content: Content) -> some View {
        content
            .overlay {
                if isHighlighted {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.effectiveAccent, lineWidth: 2)
                        .shadow(color: Color.effectiveAccent.opacity(0.4), radius: 6)
                        .padding(-2)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: isHighlighted)
    }
}

extension View {
    func searchHighlight(_ isHighlighted: Bool) -> some View {
        modifier(SettingsSearchHighlightModifier(isHighlighted: isHighlighted))
    }
}

func checkVideoInput() -> Bool {
    AVCaptureDevice.default(for: .video) != nil
}

// MARK: - Navigation & Directory Models

struct SettingsSectionItem: Identifiable, Hashable {
    let id: String
    let title: String
    let keywords: [String]
}

struct SettingsTabItem: Identifiable {
    let id: SettingsDestination
    let icon: String
    let badgeColor: Color
    let sections: [SettingsSectionItem]
}

// MARK: - Reusable Visual Elements

/// Dedicated macOS-style top header bar matching System Settings (Sonoma/Sequoia).
/// Pinned at top with frosted material backdrop (.bar) without harsh divider lines,
/// letting form content glide cleanly underneath with native material blur.
struct SettingsDetailHeaderBar: View {
    let title: String

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Text(title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 24)
            .frame(height: 52)

            Divider()
        }
        .background(.bar)
    }
}

func customBadge(text: String) -> some View {
    Text(text)
        .foregroundStyle(.secondary)
        .font(.footnote.bold())
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(Color(nsColor: .secondarySystemFill))
        .clipShape(.capsule)
}

func comingSoonTag() -> some View {
    Text(loc("Coming soon"))
        .foregroundStyle(.secondary)
        .font(.footnote.bold())
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(Color(nsColor: .secondarySystemFill))
        .clipShape(.capsule)
}

func warningBadge(_ text: String, _ description: String) -> some View {
    Section {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(.yellow)
            VStack(alignment: .leading) {
                Text(text)
                    .font(.headline)
                Text(description)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

