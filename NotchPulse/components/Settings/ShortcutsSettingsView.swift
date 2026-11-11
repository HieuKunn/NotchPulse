import KeyboardShortcuts
import SwiftUI

struct ShortcutsSettingsView: View {
    @Environment(\.settingsHighlightedId) private var highlightedId

    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder(loc("Toggle Sneak Peek:"), name: .toggleSneakPeek)
            } header: {
                Text(loc("Media"))
                    .id("shortcuts_media")
            } footer: {
                Text(
                    loc("Sneak Peek shows the media title and artist under the notch for a few seconds.")
                )
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.secondary)
                .font(.caption)
            }
            .id("shortcuts_media")
            .searchHighlight(highlightedId == "shortcuts_media")

            Section {
                KeyboardShortcuts.Recorder(loc("Toggle Notch Open:"), name: .toggleNotchOpen)
                KeyboardShortcuts.Recorder(loc("Open Launchpad:"), name: .toggleLaunchpad)
            } header: {
                Text(loc("Notch"))
                    .id("shortcuts_notch")
            }
            .id("shortcuts_notch")
            .searchHighlight(highlightedId == "shortcuts_notch")
        }
        .formStyle(.grouped)
        .tint(.effectiveAccent)
    }
}

typealias Shortcuts = ShortcutsSettingsView

