import AppKit
import Defaults
import SwiftUI

struct ClipboardSettingsView: View {
    @Environment(\.settingsHighlightedId) private var highlightedId
    @ObservedObject var clipboardManager = ClipboardManager.shared
    @Default(.enableClipboardManager) var enableClipboardManager
    @Default(.clipboardMaxItems) var clipboardMaxItems

    var body: some View {
        Form {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc("Enable Clipboard Manager"))
                            .font(.headline)
                        Text(loc("Keep track of your recent text and image clips to easily re-copy them from the Notch."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 40)
                    Defaults.Toggle("", key: .enableClipboardManager)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }
            .id("clipboard_general")
            .searchHighlight(highlightedId == "clipboard_general")

            if enableClipboardManager {
                Section {
                    Stepper(loc("History limit: %lld items", clipboardMaxItems), value: $clipboardMaxItems, in: 5...50, step: 5)

                    Button(loc("Clear clipboard history"), role: .destructive) {
                        clipboardManager.clearHistory()
                    }
                    .disabled(clipboardManager.history.isEmpty)
                } header: {
                    Text(loc("Clipboard History"))
                } footer: {
                    Text(loc("NotchPulse securely stores clips locally. Sensitive data protection is active: passwords and concealed items from password managers (1Password, Bitwarden, Keychain) are automatically ignored. Pin clips in the Notch to protect them from being trimmed."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .id("clipboard_options")
                .searchHighlight(highlightedId == "clipboard_options")
            }
        }
        .formStyle(.grouped)
        .accentColor(.effectiveAccent)
    }
}

