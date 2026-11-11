import AppKit
import Defaults
import SwiftUI

struct MediaSettingsView: View {
    @Environment(\.settingsHighlightedId) private var highlightedId
    @Default(.waitInterval) var waitInterval
    @Default(.mediaController) var mediaController
    @ObservedObject var coordinator = NotchPulseViewCoordinator.shared
    @Default(.hideNotchOption) var hideNotchOption
    @Default(.enableSneakPeek) private var enableSneakPeek
    @Default(.sneakPeekStyles) var sneakPeekStyles

    @Default(.enableLyrics) var enableLyrics
    @Default(.enableMediaFeature) var enableMediaFeature
    @State private var isSyncing: Bool = false
    @State private var isMusicSyncConfirmed: Bool = MediaAutomationPermissionHelper.isSyncConfirmed()

    var body: some View {
        Form {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc("Enable Media & Music Player"))
                            .font(.headline)
                        Text(loc("Display track info, interactive playback controls, and lyrics in the Notch."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 40)
                    Defaults.Toggle("", key: .enableMediaFeature)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }
            .id("media_enable")
            .searchHighlight(highlightedId == "media_enable")

            Section {
                Picker(loc("Music Source"), selection: $mediaController) {
                    ForEach(availableMediaControllers) { controller in
                        Text(controller == .nowPlaying ? loc("Apple System Media (Automatic)") : controller.rawValue).tag(controller)
                    }
                }
                .onChange(of: mediaController) { _, _ in
                    NotificationCenter.default.post(
                        name: Notification.Name.mediaControllerChanged,
                        object: nil
                    )
                }
            } header: {
                Text(loc("Media Source"))
                    .id("media_source")
            } footer: {
                if MusicManager.shared.isNowPlayingDeprecated {
                    HStack {
                        Text(loc("YouTube Music requires this third-party app to be installed: "))
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Link(
                            "https://github.com/pear-devs/pear-desktop",
                            destination: URL(string: "https://github.com/pear-devs/pear-desktop")!
                        )
                        .font(.caption)
                        .foregroundColor(.blue)
                    }
                } else {
                    Text(
                        loc("Apple System Media automatically tracks and controls whichever app is active (browsers, Spotify, Apple Music, and other media players) without manual switching.")
                    )
                    .foregroundStyle(.secondary)
                    .font(.caption)
                }
            }
            .id("media_source")
            .searchHighlight(highlightedId == "media_source")

            Section {
                Toggle(
                    loc("Show music live activity"),
                    isOn: $coordinator.musicLiveActivityEnabled.animation()
                )
                Toggle(loc("Show sneak peek on playback changes"), isOn: $enableSneakPeek)
                Picker(loc("Sneak Peek Style"), selection: $sneakPeekStyles) {
                    ForEach(SneakPeekStyle.allCases) { style in
                        Text(loc(style.rawValue)).tag(style)
                    }
                }
                HStack {
                    Stepper(value: $waitInterval, in: 0...10, step: 1) {
                        HStack {
                            Text(loc("Media inactivity timeout"))
                            Spacer()
                            Text("\(Defaults[.waitInterval], specifier: "%.0f") \(loc("seconds"))")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Picker(
                    selection: $hideNotchOption,
                    label: HStack {
                        Text(loc("Full screen behavior"))
                        customBadge(text: loc("Beta"))
                    }
                ) {
                    Text(loc("Hide for all apps")).tag(HideNotchOption.always)
                    Text(loc("Hide for media app only")).tag(
                        HideNotchOption.nowPlayingOnly)
                    Text(loc("Never hide")).tag(HideNotchOption.never)
                }
            } header: {
                Text(loc("Media playback live activity"))
                    .id("media_live_activity")
            }
            .id("media_live_activity")
            .searchHighlight(highlightedId == "media_live_activity")

            Section {
                MusicSlotConfigurationView()
                Defaults.Toggle(key: .enableLyrics) {
                    HStack {
                        Text(loc("Show lyrics below artist name"))
                        customBadge(text: loc("Beta"))
                    }
                }
                Button {
                    Task {
                        isSyncing = true
                        let confirmed = await MediaAutomationPermissionHelper.requestAndVerify()
                        await MainActor.run {
                            isMusicSyncConfirmed = confirmed
                            isSyncing = false
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        if isSyncing {
                            ProgressView()
                                .controlSize(.small)
                            Text(loc("Syncing Permissions..."))
                        } else if isMusicSyncConfirmed {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(loc("Music Permissions Synced (Spotify & Apple Music)"))
                                .foregroundStyle(.green)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text(loc("Sync Music Permissions (Spotify & Apple Music)"))
                        }
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isSyncing)
            } header: {
                Text(loc("Media controls"))
                    .id("media_controls")
            } footer: {
                Text(loc("Customize which controls appear in the music player. Grant automation access for Spotify and Apple Music to keep playback and lyrics precisely in sync."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .id("media_controls")
            .searchHighlight(highlightedId == "media_controls")
        }
        .formStyle(.grouped)
        .onAppear {
            isMusicSyncConfirmed = MediaAutomationPermissionHelper.isSyncConfirmed()
        }
        .tint(.effectiveAccent)
    }

    private var availableMediaControllers: [MediaControllerType] {
        if MusicManager.shared.isNowPlayingDeprecated {
            return MediaControllerType.allCases.filter { $0 != .nowPlaying }
        } else {
            return MediaControllerType.allCases
        }
    }
}

typealias Media = MediaSettingsView

