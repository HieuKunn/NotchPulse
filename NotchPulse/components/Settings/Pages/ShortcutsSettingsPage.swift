import AppKit
import Defaults
import KeyboardShortcuts
import SwiftUI

struct ShortcutsSettingsPage: View {
    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder(loc("Toggle Sneak Peek:"), name: .toggleSneakPeek)
            } header: {
                Text(loc("Media"))
            } footer: {
                Text(loc("Sneak Peek shows the media title and artist under the notch for a few seconds."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                KeyboardShortcuts.Recorder(loc("Toggle Notch Open:"), name: .toggleNotchOpen)
            } header: {
                Text(loc("General"))
            }
        }
        .formStyle(.grouped)
    }
}
