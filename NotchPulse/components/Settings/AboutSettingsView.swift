import AppKit
import Sparkle
import SwiftUI

struct AboutSettingsView: View {
    @Environment(\.settingsHighlightedId) private var highlightedId
    @State private var showBuildNumber: Bool = false
    @State private var copiedEmail: Bool = false
    let updaterController: SPUStandardUpdaterController
    @Environment(\.openWindow) var openWindow

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
                .onTapGesture {
                    withAnimation {
                        showBuildNumber.toggle()
                    }
                }
            } header: {
                Text(loc("Version info"))
            }
            .id("about_app")
            .searchHighlight(highlightedId == "about_app")

            UpdaterSettingsView(updater: updaterController.updater)
                .id("about_updates")
                .searchHighlight(highlightedId == "about_updates")

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(loc("Report bugs or share feature ideas directly with the creator."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack {
                        Text("hieukunngauz298@gmail.com")
                            .font(.callout.monospaced())
                            .foregroundStyle(.primary)
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
                Button(role: .destructive) {
                    if let appDelegate = NSApp.delegate as? AppDelegate {
                        appDelegate.isUserInitiatedQuit = true
                        appDelegate.quitApplication()
                    } else if let appDelegate = AppDelegate.shared {
                        appDelegate.isUserInitiatedQuit = true
                        appDelegate.quitApplication()
                    }
                } label: {
                    HStack {
                        Image(systemName: "power")
                        Text(loc("Quit NotchPulse"))
                    }
                    .foregroundStyle(.red)
                }
            } footer: {
                VStack(spacing: 12) {
                    Button {
                        if let url = URL(string: "https://github.com/HieuKunn/NotchPulse-Release-for-everyone") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image("Github")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 16, height: 16)
                            Text(loc("GitHub"))
                                .font(.subheadline)
                        }
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

                    Text(loc("Made with 🫶🏻 for NotchPulse"))
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
        }
        .formStyle(.grouped)
    }
}

typealias About = AboutSettingsView
