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
        VStack {
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
                                .font(.system(size: 11, weight: .medium))
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
                }

                HStack(spacing: 30) {
                    Spacer(minLength: 0)
                    Button {
                        if let url = URL(string: "https://github.com/HieuKunn/NotchPulse-Release-for-everyone") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        VStack(spacing: 5) {
                            Image("Github")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 18)
                            Text(loc("GitHub"))
                        }
                        .contentShape(Rectangle())
                    }
                    Spacer(minLength: 0)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .formStyle(.grouped)

            VStack(spacing: 0) {
                Divider()
                Text(loc("Made with 🫶🏻 for NotchPulse"))
                    .foregroundStyle(.secondary)
                    .padding(.top, 5)
                    .padding(.bottom, 7)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

typealias About = AboutSettingsView

