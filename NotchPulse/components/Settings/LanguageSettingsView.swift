import Defaults
import SwiftUI

struct LanguageSettingsView: View {
    @Environment(\.settingsHighlightedId) private var highlightedId
    @Default(.appLanguage) private var appLanguage

    var body: some View {
        Form {
            Section {
                Picker(loc("Display Language"), selection: $appLanguage) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }

                Text(loc("Change the display language for NotchPulse settings and interface."))
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } header: {
                Text(loc("App Language"))
            }
            .id("language_display")
            .searchHighlight(highlightedId == "language_display")
        }
        .formStyle(.grouped)
        .accentColor(.effectiveAccent)
    }
}

