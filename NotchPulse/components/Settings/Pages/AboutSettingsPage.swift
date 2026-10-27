import AppKit
import Sparkle
import SwiftUI

struct AboutSettingsPage: View {
    @State private var showBuildNumber: Bool = false
    @State private var copiedEmail: Bool = false
    let updaterController: SPUStandardUpdaterController

    var body: some View {
        Form {
            Section {
                HStack {
                    Text(loc("Release name"))
                    Spacer()
                    Text(Bundle.main.releaseNameString)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text(loc("Version"))
                    Spacer()
                    if showBuildNumber {
                        Text("(\(Bundle.main.buildVersionNumber ?? ""))")
                            .foregroundStyle(.secondary)
                    }
                    Text(Bundle.main.releaseVersionNumber ?? "unknown")
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation {
                        showBuildNumber.toggle()
                    }
                }
            } header: {
                Text(loc("Version info"))
            }

            UpdaterSettingsView(updater: updaterController.updater)

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(loc("Report bugs or share feature ideas directly with the creator."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack {
                        Text("hieukunngauz298@gmail.com")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.primary)
                            .textSelection(.enabled)

                        Spacer()

                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString("hieukunngauz298@gmail.com", forType: .string)
                            copiedEmail = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                copiedEmail = false
                            }
                        } label: {
                            Label(
                                copiedEmail ? loc("Copied") : loc("Copy Email"),
                                systemImage: copiedEmail ? "checkmark.circle.fill" : "doc.on.clipboard"
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
                .padding(.vertical, 2)
            } header: {
                Text(loc("Feedback & Feature Requests"))
            }

            Section {
                HStack {
                    Label(loc("GitHub Repository"), systemImage: "link")
                    Spacer()
                    Button(loc("Open in Browser")) {
                        if let url = URL(string: "https://github.com/HieuKunn/NotchPulse-Release-for-everyone") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } header: {
                Text(loc("Community"))
            } footer: {
                HStack {
                    Spacer()
                    Text(loc("Made with 🫶🏻 for NotchPulse"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.top, 12)
            }
        }
        .formStyle(.grouped)
    }
}
