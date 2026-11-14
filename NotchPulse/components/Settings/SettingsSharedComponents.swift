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

/// Dedicated macOS-style top header bar matching System Settings (Sonoma/Sequoia/Tahoe).
/// Transparent at top so content sits naturally with zero artificial space or painted background;
/// transitions to native within-window frosted material blur and hairline divider when content scrolls underneath.
struct SettingsDetailHeaderBar: View {
    let title: String
    var isScrolled: Bool = false

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
            .padding(.top, 14)
            .padding(.bottom, 6)

            Divider()
                .opacity(isScrolled ? 1 : 0)
        }
        .background {
            if isScrolled {
                Rectangle()
                    .fill(.bar)
                    .ignoresSafeArea(edges: .top)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isScrolled)
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

