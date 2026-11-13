import AppKit
import Defaults
import SwiftUI

struct DockSettingsView: View {
    @Environment(\.settingsHighlightedId) private var highlightedId
    @Default(.enableDockPreview) private var enableDockPreview
    @Default(.dockPreviewSize) private var dockPreviewSize
    @Default(.dockPreviewHoverDelay) private var hoverDelay
    @Default(.dockPreviewShowTitles) private var showTitles
    @Default(.dockPreviewShowCloseButton) private var showCloseButton

    @State private var dockPositionText: String = ""
    @State private var hasScreenRecordingPermission: Bool = true

    var body: some View {
        Form {
            // Section 1: Master Enable
            Section {
                Defaults.Toggle(key: .enableDockPreview) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc("Enable Dock Window Preview"))
                            .font(.body.weight(.medium))
                        Text(loc("Hover over running apps in your macOS Dock to see live, interactive window previews."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: enableDockPreview) { _, enabled in
                    if enabled {
                        DockPreviewManager.shared.configure()
                    } else {
                        DockPreviewManager.shared.teardown()
                    }
                }
            } header: {
                Text(loc("Dock Window Preview"))
            } footer: {
                Text(loc("Clicking any preview thumbnail activates that specific window. Hovering over a card reveals a close button to quickly dismiss windows."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .id("dock_preview_master")
            .searchHighlight(highlightedId == "dock_preview_master")

            // Section 2: Appearance & Behavior
            Section {
                Picker(loc("Preview Size"), selection: $dockPreviewSize) {
                    Text(loc("Small")).tag(DockPreviewSize.small)
                    Text(loc("Medium")).tag(DockPreviewSize.medium)
                    Text(loc("Large")).tag(DockPreviewSize.large)
                }

                Picker(loc("Hover Delay"), selection: $hoverDelay) {
                    Text(loc("Fast (0.15s)")).tag(0.15)
                    Text(loc("Standard (0.25s)")).tag(0.25)
                    Text(loc("Relaxed (0.40s)")).tag(0.40)
                }

                Defaults.Toggle(key: .dockPreviewShowTitles) {
                    Text(loc("Show window titles"))
                }

                Defaults.Toggle(key: .dockPreviewShowCloseButton) {
                    Text(loc("Show close button on hover"))
                }
            } header: {
                Text(loc("Appearance & Behavior"))
            }
            .id("dock_preview_appearance")
            .searchHighlight(highlightedId == "dock_preview_appearance")

            // Section 3: Status & Permissions
            Section {
                HStack {
                    Label(loc("Detected Dock Position"), systemImage: "dock.rectangle")
                    Spacer()
                    Text(dockPositionText)
                        .foregroundStyle(.secondary)
                        .fontWeight(.medium)
                }

                HStack {
                    Label(loc("Screen Recording Access"), systemImage: "sparkles.tv")
                    Spacer()
                    if hasScreenRecordingPermission {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(loc("Granted"))
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Button(loc("Open Privacy Settings")) {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .controlSize(.small)
                    }
                }
            } header: {
                Text(loc("Status & Permissions"))
            } footer: {
                Text(loc("Screen Recording permission is required by macOS for ScreenCaptureKit to generate thumbnail previews."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .id("dock_preview_status")
            .searchHighlight(highlightedId == "dock_preview_status")
        }
        .formStyle(.grouped)
        .onAppear {
            refreshStatus()
        }
    }

    private func refreshStatus() {
        let (pos, _) = DockPreviewManager.shared.detectDockPosition()
        let isAutohide = (UserDefaults(suiteName: "com.apple.dock")?.bool(forKey: "autohide") ?? false)
        let autoHideSuffix = isAutohide ? " (\(loc("Auto-hide")))" : ""

        switch pos {
        case .bottom:
            dockPositionText = loc("Bottom") + autoHideSuffix
        case .left:
            dockPositionText = loc("Left") + autoHideSuffix
        case .right:
            dockPositionText = loc("Right") + autoHideSuffix
        case .hidden:
            dockPositionText = isAutohide ? loc("Auto-hide") : loc("Hidden")
        }

        hasScreenRecordingPermission = CGPreflightScreenCaptureAccess()
    }
}
