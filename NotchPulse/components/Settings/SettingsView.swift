import Defaults
import Sparkle
import SwiftUI

struct SettingsView: View {
    @State private var selectedTab: String? = "General"
    @State private var searchText = ""
    @State private var accentColorUpdateTrigger = UUID()
    @Default(.appLanguage) private var appLanguage

    let updaterController: SPUStandardUpdaterController?

    struct SettingsTabItem: Identifiable {
        let id: String
        let icon: String
        let badgeColor: Color
        let section: TabSection
        let elements: [String]
    }

    enum TabSection: String, CaseIterable {
        case app = "App"
        case features = "Features"
        case system = "System"
    }

    private let allTabs: [SettingsTabItem] = [
        // App Section
        SettingsTabItem(
            id: "General",
            icon: "gear",
            badgeColor: .gray,
            section: .app,
            elements: [
                "Feature Tour", "Interactive Spotlight walkthrough highlighting all Notch features.",
                "Notch Dimensions (Width)", "Notch Width", "Compact (580px)", "Standard (740px)", "Wide (860px)",
                "Controls the horizontal expansion length when the notch or dynamic island is open.",
                "System features", "Show menu bar icon", "Launch at login", "Show on all displays", "Preferred display",
                "Notch sizing", "Notch height on notch displays", "Match real notch height", "Match menu bar height", "Custom height",
                "Notch height on non-notch displays", "Custom notch size",
                "Hover & Gestures", "Open notch on hover", "Extend hover area", "Hover area padding", "Minimum hover duration",
                "Enable gestures", "Gesture sensitivity",
                "Notch Style", "MacBook Notch", "Dynamic Island", "Dynamic Island top offset",
                "Camera Mirror", "Mirror shape", "Rectangle", "Circle",
                "Emojis", "Show emojis"
            ]
        ),
        SettingsTabItem(
            id: "Appearance",
            icon: "paintbrush.fill",
            badgeColor: .pink,
            section: .app,
            elements: [
                "General", "Always show tabs", "Show settings icon in notch",
                "Media", "Colored spectrogram", "Player tinting", "Enable blur effect behind album art", "Slider color",
                "Match album art", "Default",
                "Custom music live activity animation", "Use music visualizer spectrogram", "Selected animation", "No custom animation available",
                "Accent color", "System accent", "Custom accent color", "Blue", "Purple", "Pink", "Red", "Orange", "Yellow", "Green", "Graphite",
                "App icon"
            ]
        ),
        SettingsTabItem(
            id: "Media",
            icon: "play.circle.fill",
            badgeColor: .red,
            section: .app,
            elements: [
                "Enable Media & Music Player", "Display track info, interactive playback controls, and lyrics in the Notch.",
                "Media Source", "Music Source", "Now Playing", "Spotify", "Apple Music", "YouTube Music",
                "Media playback live activity", "Show music live activity", "Show sneak peek on playback changes", "Sneak Peek Style",
                "Standard", "Inline", "Compact", "Media inactivity timeout", "Full screen behavior", "Hide for all apps",
                "Media controls", "Music Slot Configuration", "Layout Preview", "Progress bar style", "Seek step", "Backward 15s", "Forward 15s",
                "Lyrics", "Enable synced lyrics", "Apple Music synced lyrics", "Spotify synced lyrics", "Auto-scroll to current lyric line",
                "Lyrics font size", "Lyrics animation", "Lyrics blur",
                "Universal App Audio Engine", "App Volume Engine", "Adjust volume across all applications"
            ]
        ),
        SettingsTabItem(
            id: "Calendar",
            icon: "calendar",
            badgeColor: .red,
            section: .app,
            elements: [
                "Calendar integration", "Enable calendar and events", "Sync reminders", "Reminders integration",
                "Alternate calendar", "Lunar calendar", "Islamic calendar", "Hebrew calendar", "Show lunar calendar",
                "Show full event titles", "Always show full event titles",
                "Past events", "Show past events today", "Auto-scroll to next event", "Upcoming events",
                "Calendar access", "Reminders access", "Calendar permissions"
            ]
        ),
        SettingsTabItem(
            id: "HUD",
            icon: "gauge.with.dots.needle.33percent",
            badgeColor: .orange,
            section: .app,
            elements: [
                "Volume HUD", "System volume indicator", "Replace native volume HUD",
                "Brightness HUD", "Display brightness indicator", "Replace native brightness HUD",
                "Keyboard backlight HUD", "Keyboard brightness indicator",
                "Inline HUD", "Show compact inline HUD inside notch", "Standard HUD",
                "Show power status notifications", "Battery status", "Power adapter status", "Charging indicator",
                "Show HUD on lock screen"
            ]
        ),
        SettingsTabItem(
            id: "SystemMonitor",
            icon: "chart.bar.fill",
            badgeColor: .green,
            section: .app,
            elements: [
                "System Monitor (Stats)", "Monitor real-time CPU, RAM, and GPU load in a dedicated Notch tab inspired by the 'Stats' app.",
                "System Monitoring Access: Active (Darwin Mach & IOKit native APIs)",
                "Show top resource-consuming processes", "Display Options",
                "Cooling & Fan Speed", "CPU & GPU temperatures", "Fan speed", "RPM", "Fan profiles",
                "Auto", "Balanced", "Smart", "Max", "Custom", "Passive cooling (Fanless)", "Privileged helper tool", "SMC fan control"
            ]
        ),

        // Features Section
        SettingsTabItem(
            id: "FaceID",
            icon: "faceid",
            badgeColor: .blue,
            section: .features,
            elements: [
                "Face ID", "Allow NotchPulse to recognize your face", "Allow NotchPulse to unlock your Mac",
                "Camera access", "Face ID camera", "Built-in FaceTime HD Camera", "Continuity Camera",
                "Apple biometrics fallback", "Allow Touch ID, Apple Watch, or system password",
                "Authorize system prompts", "Automatically verify with Face ID when macOS requires admin approval or installer confirmation.",
                "Auto-lock", "Auto-lock interval", "Lock on sleep", "Recognition tolerance", "Strict", "Balanced", "Relaxed",
                "Quality threshold", "Re-enroll face", "Security", "Keychain encryption"
            ]
        ),
        SettingsTabItem(
            id: "Shelf",
            icon: "tray.fill",
            badgeColor: .purple,
            section: .features,
            elements: [
                "Notch Shelf", "Drop zone", "Drag and drop", "Auto-clear items on drag-out", "Pin shelf open",
                "Shelf storage", "Temporary file tray", "File drop"
            ]
        ),
        SettingsTabItem(
            id: "Clipboard",
            icon: "doc.on.clipboard.fill",
            badgeColor: .cyan,
            section: .features,
            elements: [
                "Clipboard History", "Clipboard Manager", "Save copied text and images", "3-item viewport",
                "Clear clipboard history", "History capacity limit", "Image preview thumbnail", "One-click copy", "Relative timestamp"
            ]
        ),
        SettingsTabItem(
            id: "Audio",
            icon: "speaker.wave.2.fill",
            badgeColor: .indigo,
            section: .features,
            elements: [
                "Audio Hub", "Audio output", "Audio input", "Sound devices", "Speakers", "Microphones",
                "Headphones", "Default audio device", "Volume slider", "Mute toggle", "Sound routing"
            ]
        ),
        SettingsTabItem(
            id: "Display",
            icon: "sun.max.fill",
            badgeColor: .yellow,
            section: .features,
            elements: [
                "Display Hub", "Screen brightness", "Multiple displays", "Monitors", "External display brightness",
                "DDC/CI hardware brightness", "Mirror display"
            ]
        ),
        SettingsTabItem(
            id: "Shortcuts",
            icon: "command.square.fill",
            badgeColor: .gray,
            section: .features,
            elements: [
                "Shortcuts", "Keyboard shortcuts", "Hotkeys", "Global key bindings", "Toggle notch", "Open shelf",
                "Toggle clipboard", "Toggle mute", "Play/Pause", "Next track", "Previous track"
            ]
        ),

        // System Section
        SettingsTabItem(
            id: "Advanced",
            icon: "slider.horizontal.3",
            badgeColor: .gray,
            section: .system,
            elements: [
                "Reset settings", "Restore default preferences", "Clear app cache", "Re-run Onboarding",
                "Start Feature Tour", "Accessibility permission", "Diagnostic logs"
            ]
        ),
        SettingsTabItem(
            id: "Language",
            icon: "globe",
            badgeColor: .blue,
            section: .system,
            elements: [
                "App Language", "Language", "Ngôn ngữ", "Tiếng Việt", "English", "Deutsch", "Français", "Español", "日本語", "简体中文"
            ]
        ),
        SettingsTabItem(
            id: "About",
            icon: "info.circle.fill",
            badgeColor: .gray,
            section: .system,
            elements: [
                "About", "NotchPulse", "Version", "Phiên bản", "Automatically check for updates",
                "Automatically download updates", "Check for Updates…", "Release notes", "Developer", "GitHub"
            ]
        )
    ]

    private var filteredTabs: [SettingsTabItem] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return allTabs }
        let normalizedQuery = trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)

        return allTabs.filter { tab in
            let title = tabTitle(for: tab.id)
            let normalizedTitle = title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            if normalizedTitle.contains(normalizedQuery) { return true }

            for item in tab.elements {
                let localized = loc(item)
                let normalizedItem = localized.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                if normalizedItem.contains(normalizedQuery) { return true }
            }
            return false
        }
    }

    private func matchingSubtext(for tab: SettingsTabItem) -> String? {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalizedQuery = trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)

        let title = tabTitle(for: tab.id)
        let normalizedTitle = title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        if normalizedTitle.contains(normalizedQuery) { return nil }

        for item in tab.elements {
            let localized = loc(item)
            let normalizedItem = localized.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            if normalizedItem.contains(normalizedQuery) {
                return localized
            }
        }
        return nil
    }

    init(updaterController: SPUStandardUpdaterController? = nil) {
        self.updaterController = updaterController
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                if filteredTabs.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text(loc("No settings found"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 32)
                } else if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    // Search results view: flat list with matching hints
                    ForEach(filteredTabs) { tab in
                        NavigationLink(value: tab.id) {
                            SidebarItemRow(
                                title: tabTitle(for: tab.id),
                                icon: tab.icon,
                                badgeColor: tab.badgeColor,
                                subtext: matchingSubtext(for: tab)
                            )
                        }
                    }
                } else {
                    // Grouped macOS System Settings layout
                    Section(header: Text(loc("App"))) {
                        ForEach(filteredTabs.filter { $0.section == .app }) { tab in
                            NavigationLink(value: tab.id) {
                                SidebarItemRow(
                                    title: tabTitle(for: tab.id),
                                    icon: tab.icon,
                                    badgeColor: tab.badgeColor
                                )
                            }
                        }
                    }

                    Section(header: Text(loc("Features"))) {
                        ForEach(filteredTabs.filter { $0.section == .features }) { tab in
                            NavigationLink(value: tab.id) {
                                SidebarItemRow(
                                    title: tabTitle(for: tab.id),
                                    icon: tab.icon,
                                    badgeColor: tab.badgeColor
                                )
                            }
                        }
                    }

                    Section(header: Text(loc("System"))) {
                        ForEach(filteredTabs.filter { $0.section == .system }) { tab in
                            NavigationLink(value: tab.id) {
                                SidebarItemRow(
                                    title: tabTitle(for: tab.id),
                                    icon: tab.icon,
                                    badgeColor: tab.badgeColor
                                )
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .searchable(text: $searchText, placement: .sidebar, prompt: Text(loc("Search")))
            .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
            .tint(Color.effectiveAccent)
        } detail: {
            detailContent
                .safeAreaInset(edge: .top, spacing: 0) {
                    SettingsDetailHeaderBar(
                        title: tabTitle(for: selectedTab ?? "General"),
                        showQuitButton: true
                    )
                }
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 740, minHeight: 580)
        .tint(Color.effectiveAccent)
        .id("\(accentColorUpdateTrigger)-\(appLanguage.rawValue)")
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("AccentColorChanged"))) { _ in
            accentColorUpdateTrigger = UUID()
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selectedTab {
        case "General":
            GeneralSettingsPage()
        case "Appearance":
            AppearanceSettingsPage()
        case "Media":
            MediaSettingsPage()
        case "Calendar":
            CalendarSettingsPage()
        case "HUD":
            HUDSettingsPage()
        case "SystemMonitor":
            SystemMonitorSettingsPage()
        case "FaceID":
            FaceIDSettingsView()
        case "Shelf":
            ShelfSettingsPage()
        case "Clipboard":
            ClipboardSettingsPage()
        case "Audio":
            AudioSettingsPage()
        case "Display":
            DisplaySettingsPage()
        case "Shortcuts":
            ShortcutsSettingsPage()
        case "Advanced":
            AdvancedSettingsPage()
        case "Language":
            LanguageSettingsPage()
        case "About":
            let controller = updaterController ?? SettingsWindowController.shared.updaterController
            if let controller = controller {
                AboutSettingsPage(updaterController: controller)
            } else {
                AboutSettingsPage(
                    updaterController: SPUStandardUpdaterController(
                        startingUpdater: false,
                        updaterDelegate: AppUpdaterDelegate.shared,
                        userDriverDelegate: AppUpdaterDelegate.shared))
            }
        default:
            GeneralSettingsPage()
        }
    }

    private func tabTitle(for tab: String) -> String {
        L10n.tr(tab, lang: appLanguage)
    }
}

// MARK: - Native Apple System Settings Sidebar Row
struct SidebarItemRow: View {
    let title: String
    let icon: String
    let badgeColor: Color
    var subtext: String? = nil

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(badgeColor.gradient)
                    .frame(width: 24, height: 24)

                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)

                if let subtext {
                    Text("↳ \(subtext)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
