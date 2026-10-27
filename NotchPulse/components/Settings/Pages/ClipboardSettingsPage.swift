import AppKit
import Defaults
import SwiftUI

struct ClipboardSettingsPage: View {
    @ObservedObject var clipboardManager = ClipboardManager.shared
    @Default(.enableClipboardManager) var enableClipboardManager
    @Default(.clipboardMaxItems) var clipboardMaxItems

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $enableClipboardManager) {
                    Text(loc("Enable Clipboard Manager"))
                        .font(.headline)
                    Text(loc("Keep track of your recent text and image clips to easily re-copy them from the Notch."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .toggleStyle(.switch)
            }

            if enableClipboardManager {
                Section {
                    Stepper(loc("History limit: %lld items", clipboardMaxItems), value: $clipboardMaxItems, in: 5...50, step: 5)

                    Button(role: .destructive) {
                        clipboardManager.clearHistory()
                    } label: {
                        Text(loc("Clear clipboard history"))
                    }
                    .buttonStyle(.bordered)
                    .disabled(clipboardManager.history.isEmpty)
                } header: {
                    Text(loc("Clipboard History"))
                } footer: {
                    Text(loc("NotchPulse securely keeps track of your recent text and image clips. Tap any clip in the Notch clipboard tab to re-copy it instantly."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}
