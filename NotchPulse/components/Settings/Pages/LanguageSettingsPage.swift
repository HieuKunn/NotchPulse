import AppKit
import Defaults
import SwiftUI

struct LanguageSettingsPage: View {
    @Default(.appLanguage) private var appLanguage

    var body: some View {
        Form {
            Section {
                Picker(loc("Display Language"), selection: $appLanguage) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
            } header: {
                Text(loc("App Language"))
            } footer: {
                Text(loc("Change the display language for NotchPulse settings and interface."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
