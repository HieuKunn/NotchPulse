import AVFoundation
import Defaults
import EventKit
import KeyboardShortcuts
import LaunchAtLogin
import Sparkle
import SwiftUI

struct SettingsHighlightedIdKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    var settingsHighlightedId: String? {
        get { self[SettingsHighlightedIdKey.self] }
        set { self[SettingsHighlightedIdKey.self] = newValue }
    }
}

struct SettingsSearchHighlightModifier: ViewModifier {
    let isHighlighted: Bool

    func body(content: Content) -> some View {
        content
            .overlay {
                if isHighlighted {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.effectiveAccent, lineWidth: 2)
                        .shadow(color: Color.effectiveAccent.opacity(0.4), radius: 6)
                        .padding(-2)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: isHighlighted)
    }
}

extension View {
    func searchHighlight(_ isHighlighted: Bool) -> some View {
        modifier(SettingsSearchHighlightModifier(isHighlighted: isHighlighted))
    }
}

func checkVideoInput() -> Bool {
    AVCaptureDevice.default(for: .video) != nil
}

struct SettingsSectionItem: Identifiable, Hashable {
    let id: String
    let title: String
    let keywords: [String]
}

struct SettingsTabItem: Identifiable {
    let id: String
    let icon: String
    let sections: [SettingsSectionItem]
}

struct SettingsView: View {
    @State private var selectedTab = "General"
    @State private var searchText = ""
    @State private var accentColorUpdateTrigger = UUID()
    @State private var scrollToItemId: String? = nil
    @State private var highlightedItemId: String? = nil
    @State private var scrollTrigger = UUID()
    @Default(.appLanguage) private var appLanguage

    let updaterController: SPUStandardUpdaterController?

    private let allTabs: [SettingsTabItem] = [
        SettingsTabItem(
            id: "General",
            icon: "gear",
            sections: [
                SettingsSectionItem(
                    id: "feature_tour",
                    title: "Feature Tour",
                    keywords: ["Feature Tour", "Interactive Spotlight walkthrough highlighting all Notch features.", "Spotlight", "Tour", "Onboarding", "Hướng dẫn"]
                ),
                SettingsSectionItem(
                    id: "notch_style",
                    title: "Notch Style",
                    keywords: ["Notch Style", "MacBook Notch", "Dynamic Island", "Dynamic Island top offset", "Kiểu notch"]
                ),
                SettingsSectionItem(
                    id: "notch_dimensions",
                    title: "Notch Dimensions (Width)",
                    keywords: ["Notch Dimensions (Width)", "Notch Width", "Expanded Width", "Compact (580px)", "Standard (740px)", "Wide (860px)", "Controls the horizontal expansion length", "Chiều rộng"]
                ),
                SettingsSectionItem(
                    id: "system_features",
                    title: "System features",
                    keywords: ["System features", "Show menu bar icon", "Launch at login", "Show on all displays", "Preferred display", "Automatically switch displays", "Khởi động cùng hệ thống"]
                ),
                SettingsSectionItem(
                    id: "camera_mirror",
                    title: "Camera Mirror",
                    keywords: ["Camera Mirror", "Enable NotchPulse mirror", "Mirror shape", "Circle", "Square", "Rectangle", "Gương camera", "Gương soi", "Mirror"]
                ),
                SettingsSectionItem(
                    id: "notch_sizing",
                    title: "Notch sizing",
                    keywords: ["Notch sizing", "Notch height on notch displays", "Match real notch height", "Match menu bar height", "Custom height", "Notch height on non-notch displays", "Custom notch size", "Độ cao notch"]
                ),
                SettingsSectionItem(
                    id: "notch_behavior",
                    title: "Notch behavior",
                    keywords: ["Notch behavior", "Hover & Gestures", "Open notch on hover", "Enable haptic feedback", "Restore last tab on hover", "Hover delay", "Extend hover area", "Hover detection range", "Hành vi rê chuột", "Rê chuột mở notch"]
                )
            ]
        ),
        SettingsTabItem(
            id: "Appearance",
            icon: "paintbrush.fill",
            sections: [
                SettingsSectionItem(
                    id: "appearance_general",
                    title: "General",
                    keywords: ["Always show tabs", "Show settings icon in notch", "Giao diện"]
                ),
                SettingsSectionItem(
                    id: "appearance_media",
                    title: "Media",
                    keywords: ["Colored spectrogram", "Player tinting", "Enable blur effect behind album art", "Slider color", "Match album art", "Default"]
                ),
                SettingsSectionItem(
                    id: "appearance_visualizer",
                    title: "Custom music live activity animation",
                    keywords: ["Custom music live activity animation", "Use music visualizer spectrogram", "Selected animation", "Hiệu ứng sóng nhạc", "Custom vizualizers (Lottie)"]
                )
            ]
        ),
        SettingsTabItem(
            id: "Media",
            icon: "play.circle.fill",
            sections: [
                SettingsSectionItem(
                    id: "media_enable",
                    title: "Enable Media & Music Player",
                    keywords: ["Enable Media & Music Player", "Display track info, interactive playback controls, and lyrics in the Notch.", "Trình phát nhạc"]
                ),
                SettingsSectionItem(
                    id: "media_source",
                    title: "Media Source",
                    keywords: ["Media Source", "Music Source", "Now Playing", "Spotify", "Apple Music", "YouTube Music", "Nguồn phát"]
                ),
                SettingsSectionItem(
                    id: "media_live_activity",
                    title: "Media playback live activity",
                    keywords: ["Show music live activity", "Show sneak peek on playback changes", "Sneak Peek Style", "Standard", "Inline", "Compact", "Media inactivity timeout", "Full screen behavior", "Hide for all apps"]
                ),
                SettingsSectionItem(
                    id: "media_controls",
                    title: "Media controls",
                    keywords: ["Media controls", "Music Slot Configuration", "Layout Preview", "Progress bar style", "Seek step", "Backward 15s", "Forward 15s"]
                ),
                SettingsSectionItem(
                    id: "media_lyrics",
                    title: "Lyrics",
                    keywords: ["Lyrics", "Enable synced lyrics", "Apple Music synced lyrics", "Spotify synced lyrics", "Auto-scroll to current lyric line", "Lyrics font size", "Lyrics animation", "Lyrics blur", "Lời bài hát"]
                ),
                SettingsSectionItem(
                    id: "media_volume",
                    title: "Universal App Audio Engine",
                    keywords: ["Universal App Audio Engine", "App Volume Engine", "Adjust volume across all applications", "Âm lượng từng ứng dụng"]
                )
            ]
        ),
        SettingsTabItem(
            id: "Calendar",
            icon: "calendar",
            sections: [
                SettingsSectionItem(
                    id: "calendar_integration",
                    title: "Calendar integration",
                    keywords: ["Calendar integration", "Enable calendar and events", "Sync reminders", "Reminders integration", "Calendar access", "Reminders access", "Calendar permissions", "Lịch và nhắc nhở"]
                ),
                SettingsSectionItem(
                    id: "calendar_alternate",
                    title: "Alternate calendar",
                    keywords: ["Alternate calendar", "Lunar calendar", "Islamic calendar", "Hebrew calendar", "Show lunar calendar", "Lịch âm", "Lịch vạn niên"]
                ),
                SettingsSectionItem(
                    id: "calendar_options",
                    title: "Calendar options",
                    keywords: ["Show full event titles", "Always show full event titles", "Past events", "Show past events today", "Auto-scroll to next event", "Upcoming events"]
                )
            ]
        ),
        SettingsTabItem(
            id: "HUD",
            icon: "gauge.with.dots.needle.33percent",
            sections: [
                SettingsSectionItem(
                    id: "hud_volume",
                    title: "Volume HUD",
                    keywords: ["Volume HUD", "System volume indicator", "Replace native volume HUD", "Âm lượng", "Thanh âm lượng"]
                ),
                SettingsSectionItem(
                    id: "hud_brightness",
                    title: "Brightness HUD",
                    keywords: ["Brightness HUD", "Display brightness indicator", "Replace native brightness HUD", "Độ sáng màn hình"]
                ),
                SettingsSectionItem(
                    id: "hud_keyboard",
                    title: "Keyboard backlight HUD",
                    keywords: ["Keyboard backlight HUD", "Keyboard brightness indicator", "Đèn nền bàn phím"]
                ),
                SettingsSectionItem(
                    id: "hud_inline",
                    title: "Inline HUD",
                    keywords: ["Inline HUD", "Show compact inline HUD inside notch", "Standard HUD", "HUD gọn gàng trong notch"]
                ),
                SettingsSectionItem(
                    id: "hud_power",
                    title: "Power status notifications",
                    keywords: ["Show power status notifications", "Battery status", "Power adapter status", "Charging indicator", "Show HUD on lock screen", "Pin", "Thông báo cắm sạc"]
                )
            ]
        ),
        SettingsTabItem(
            id: "SystemMonitor",
            icon: "chart.bar.fill",
            sections: [
                SettingsSectionItem(
                    id: "sysmon_enable",
                    title: "System Monitor (Stats)",
                    keywords: ["System Monitor (Stats)", "Monitor real-time CPU, RAM, and GPU load", "System Monitoring Access", "Theo dõi hệ thống", "CPU", "RAM", "GPU"]
                ),
                SettingsSectionItem(
                    id: "sysmon_display",
                    title: "Display Options",
                    keywords: ["Show top resource-consuming processes", "Display Options", "Tiến trình tốn tài nguyên"]
                ),
                SettingsSectionItem(
                    id: "sysmon_cooling",
                    title: "Cooling & Fan Speed",
                    keywords: ["Cooling & Fan Speed", "CPU & GPU temperatures", "Fan speed", "RPM", "Fan profiles", "Auto", "Balanced", "Smart", "Max", "Custom", "Passive cooling (Fanless)", "Privileged helper tool", "SMC fan control", "Quạt tản nhiệt", "Nhiệt độ"]
                )
            ]
        ),
        SettingsTabItem(
            id: "FaceID",
            icon: "faceid",
            sections: [
                SettingsSectionItem(
                    id: "faceid_general",
                    title: "Face ID",
                    keywords: ["Face ID", "Allow NotchPulse to recognize your face", "Allow NotchPulse to unlock your Mac", "Mở khóa khuôn mặt"]
                ),
                SettingsSectionItem(
                    id: "faceid_camera",
                    title: "Face ID camera",
                    keywords: ["Camera access", "Face ID camera", "Built-in FaceTime HD Camera", "Continuity Camera"]
                ),
                SettingsSectionItem(
                    id: "faceid_security",
                    title: "Security & Fallback",
                    keywords: ["Apple biometrics fallback", "Allow Touch ID, Apple Watch, or system password", "Authorize system prompts", "Keychain encryption"]
                ),
                SettingsSectionItem(
                    id: "faceid_tolerance",
                    title: "Auto-lock & Recognition",
                    keywords: ["Auto-lock", "Auto-lock interval", "Lock on sleep", "Recognition tolerance", "Strict", "Balanced", "Relaxed", "Quality threshold", "Re-enroll face"]
                )
            ]
        ),
        SettingsTabItem(
            id: "Shelf",
            icon: "tray.fill",
            sections: [
                SettingsSectionItem(
                    id: "shelf_general",
                    title: "Notch Shelf",
                    keywords: ["Notch Shelf", "Drop zone", "Drag and drop", "Auto-clear items on drag-out", "Pin shelf open", "Kệ lưu trữ", "Kéo thả file"]
                ),
                SettingsSectionItem(
                    id: "shelf_storage",
                    title: "Shelf storage",
                    keywords: ["Shelf storage", "Temporary file tray", "File drop"]
                )
            ]
        ),
        SettingsTabItem(
            id: "Clipboard",
            icon: "doc.on.clipboard.fill",
            sections: [
                SettingsSectionItem(
                    id: "clipboard_general",
                    title: "Clipboard History",
                    keywords: ["Clipboard History", "Clipboard Manager", "Save copied text and images", "3-item viewport", "Lịch sử sao chép"]
                ),
                SettingsSectionItem(
                    id: "clipboard_options",
                    title: "Clipboard Options",
                    keywords: ["Clear clipboard history", "History capacity limit", "Image preview thumbnail", "One-click copy", "Relative timestamp"]
                )
            ]
        ),
        SettingsTabItem(
            id: "Audio",
            icon: "speaker.wave.2.fill",
            sections: [
                SettingsSectionItem(
                    id: "audio_hub",
                    title: "Audio Hub",
                    keywords: ["Audio Hub", "Audio output", "Audio input", "Sound devices", "Speakers", "Microphones", "Headphones", "Âm thanh"]
                ),
                SettingsSectionItem(
                    id: "audio_routing",
                    title: "Sound routing",
                    keywords: ["Default audio device", "Volume slider", "Mute toggle", "Sound routing"]
                )
            ]
        ),
        SettingsTabItem(
            id: "Display",
            icon: "sun.max.fill",
            sections: [
                SettingsSectionItem(
                    id: "display_hub",
                    title: "Display Hub",
                    keywords: ["Display Hub", "Screen brightness", "Hardware DDC/CI brightness control for external monitors", "Quản lý màn hình"]
                ),
                SettingsSectionItem(
                    id: "display_monitors",
                    title: "Connected Displays",
                    keywords: ["Connected Displays", "Multiple displays", "Monitors", "External display brightness", "Retina", "Hardware DDC"]
                ),
                SettingsSectionItem(
                    id: "display_features",
                    title: "Display Features",
                    keywords: ["Hardware DDC/CI Control", "Per-Display Brightness Sliders", "DDC/CI hardware brightness"]
                )
            ]
        ),
        SettingsTabItem(
            id: "Shortcuts",
            icon: "command.square.fill",
            sections: [
                SettingsSectionItem(
                    id: "shortcuts_media",
                    title: "Media Shortcuts",
                    keywords: ["Shortcuts", "Keyboard shortcuts", "Hotkeys", "Global key bindings", "Toggle Sneak Peek", "Phím tắt"]
                ),
                SettingsSectionItem(
                    id: "shortcuts_notch",
                    title: "Notch Shortcuts",
                    keywords: ["Toggle Notch Open", "Toggle notch", "Open shelf", "Toggle clipboard"]
                )
            ]
        ),
        SettingsTabItem(
            id: "Advanced",
            icon: "slider.horizontal.3",
            sections: [
                SettingsSectionItem(
                    id: "advanced_accent",
                    title: "Accent color",
                    keywords: ["Accent color", "System accent", "Custom accent color", "Color Presets", "Pick a color", "Blue", "Purple", "Pink", "Red", "Orange", "Yellow", "Green", "Graphite", "Màu chủ đạo"]
                ),
                SettingsSectionItem(
                    id: "advanced_appearance",
                    title: "Window Appearance",
                    keywords: ["Window Appearance", "Corner radius scaling", "Bo góc"]
                ),
                SettingsSectionItem(
                    id: "advanced_icon",
                    title: "App icon",
                    keywords: ["App icon", "Biểu tượng ứng dụng"]
                ),
                SettingsSectionItem(
                    id: "advanced_behavior",
                    title: "Window Behavior",
                    keywords: ["Window Behavior", "Hide title bar", "Show notch on lock screen", "Hide from screen recording", "Màn hình khóa"]
                )
            ]
        ),
        SettingsTabItem(
            id: "Language",
            icon: "globe",
            sections: [
                SettingsSectionItem(
                    id: "language_display",
                    title: "App Language",
                    keywords: ["App Language", "Language", "Ngôn ngữ", "Tiếng Việt", "English", "Deutsch", "Français", "Español", "日本語", "简体中文"]
                )
            ]
        ),
        SettingsTabItem(
            id: "About",
            icon: "info.circle.fill",
            sections: [
                SettingsSectionItem(
                    id: "about_app",
                    title: "About NotchPulse",
                    keywords: ["About", "NotchPulse", "Version", "Phiên bản", "Release notes", "Developer", "GitHub", "Thông tin"]
                ),
                SettingsSectionItem(
                    id: "about_updates",
                    title: "Software Update",
                    keywords: ["Automatically check for updates", "Automatically download updates", "Check for Updates…", "Cập nhật phần mềm"]
                )
            ]
        )
    ]

    private func matchingSections(for tab: SettingsTabItem) -> [SettingsSectionItem] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let normalizedQuery = trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)

        return tab.sections.filter { section in
            let localizedTitle = loc(section.title)
            if localizedTitle.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).contains(normalizedQuery) {
                return true
            }
            for kw in section.keywords {
                let localizedKw = loc(kw)
                if localizedKw.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).contains(normalizedQuery) {
                    return true
                }
            }
            return false
        }
    }

    private var filteredTabs: [SettingsTabItem] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return allTabs }
        let normalizedQuery = trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)

        return allTabs.filter { tab in
            let title = tabTitle(for: tab.id)
            if title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).contains(normalizedQuery) {
                return true
            }
            return !matchingSections(for: tab).isEmpty
        }
    }

    private func selectSearchItem(tabId: String, sectionId: String) {
        selectedTab = tabId
        scrollToItemId = sectionId
        highlightedItemId = sectionId
        scrollTrigger = UUID()

        // Automatically fade out highlight after 1.8 seconds
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1800))
            withAnimation(.easeOut(duration: 0.4)) {
                if highlightedItemId == sectionId {
                    highlightedItemId = nil
                }
            }
        }
    }

    init(updaterController: SPUStandardUpdaterController? = nil) {
        self.updaterController = updaterController
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                // Logo + App Name Header (Pushed down below traffic lights, larger text)
                HStack(spacing: 9) {
                    if let appIcon = NSImage(named: "AppIcon") ?? NSApp.applicationIconImage {
                        Image(nsImage: appIcon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    } else {
                        Image(systemName: "sparkles")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 6) {
                        Text("NotchPulse")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.primary)

                        Text("v\(Bundle.main.releaseVersionNumber ?? "5.5")")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.55))
                            )
                    }

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 9)

                // Search Bar in Settings
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)

                    TextField(loc("Search Settings..."), text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .onSubmit {
                            if let firstTab = filteredTabs.first {
                                let matches = matchingSections(for: firstTab)
                                if let firstMatch = matches.first {
                                    selectSearchItem(tabId: firstTab.id, sectionId: firstMatch.id)
                                } else {
                                    selectedTab = firstTab.id
                                }
                            }
                        }

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

                // Vertical Settings Tabs
                List(selection: $selectedTab) {
                    if filteredTabs.isEmpty {
                        VStack(spacing: 6) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 18))
                                .foregroundStyle(.secondary)
                            Text(loc("No settings found"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 24)
                    } else if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ForEach(allTabs) { tab in
                            NavigationLink(value: tab.id) {
                                HStack(spacing: 8) {
                                    Image(systemName: tab.icon)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(selectedTab == tab.id ? Color.white : Color(nsColor: .secondaryLabelColor))
                                        .frame(width: 18, alignment: .center)

                                    Text(tabTitle(for: tab.id))
                                        .foregroundStyle(selectedTab == tab.id ? Color.white : Color.primary)
                                }
                            }
                        }
                    } else {
                        ForEach(filteredTabs) { tab in
                            let matches = matchingSections(for: tab)
                            Section {
                                NavigationLink(value: tab.id) {
                                    HStack(spacing: 8) {
                                        Image(systemName: tab.icon)
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(selectedTab == tab.id ? Color.white : Color(nsColor: .secondaryLabelColor))
                                            .frame(width: 18, alignment: .center)

                                        Text(tabTitle(for: tab.id))
                                            .foregroundStyle(selectedTab == tab.id ? Color.white : Color.primary)
                                    }
                                }
                                .simultaneousGesture(TapGesture().onEnded {
                                    if let first = matches.first {
                                        selectSearchItem(tabId: tab.id, sectionId: first.id)
                                    } else if let firstSec = tab.sections.first {
                                        selectSearchItem(tabId: tab.id, sectionId: firstSec.id)
                                    }
                                })

                                ForEach(matches) { sec in
                                    Button {
                                        selectSearchItem(tabId: tab.id, sectionId: sec.id)
                                    } label: {
                                        HStack(spacing: 6) {
                                            Text("↳")
                                                .foregroundStyle(selectedTab == tab.id && scrollToItemId == sec.id ? Color.effectiveAccent : .secondary)
                                            Text(loc(sec.title))
                                                .font(.system(size: 11, weight: selectedTab == tab.id && scrollToItemId == sec.id ? .semibold : .regular))
                                                .foregroundStyle(selectedTab == tab.id && scrollToItemId == sec.id ? Color.effectiveAccent : .primary)
                                                .lineLimit(1)
                                            Spacer()
                                        }
                                        .padding(.leading, 24)
                                        .padding(.vertical, 3)
                                        .padding(.trailing, 6)
                                        .background(
                                            selectedTab == tab.id && scrollToItemId == sec.id
                                                ? Color.effectiveAccent.opacity(0.12)
                                                : Color.clear
                                        )
                                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .font(.system(size: 14, weight: .medium))
                .listStyle(SidebarListStyle())
                .scrollIndicators(.hidden)
            }
            .tint(.effectiveAccent)
            .toolbar(removing: .sidebarToggle)
            .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 270)
        } detail: {
            ScrollViewReader { proxy in
                detailContent
                    .environment(\.settingsHighlightedId, highlightedItemId)
                    .formStyle(.grouped)
                    .scrollIndicators(.hidden)
                    .background(ScrollViewScrollerHider())
                    .safeAreaInset(edge: .top, spacing: 0) {
                        SettingsDetailHeaderBar(
                            title: tabTitle(for: selectedTab),
                            showQuitButton: true
                        )
                    }
                    .background(Color(nsColor: .windowBackgroundColor))
                    .ignoresSafeArea(edges: .top)
                    .onChange(of: scrollTrigger) { _, _ in
                        guard let targetId = scrollToItemId else { return }
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(70))
                            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                                proxy.scrollTo(targetId, anchor: .center)
                            }
                            try? await Task.sleep(for: .milliseconds(120))
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                proxy.scrollTo(targetId, anchor: .center)
                            }
                        }
                    }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .formStyle(.grouped)
        .frame(minWidth: 720, minHeight: 560)
        .tint(.effectiveAccent)
        .id("\(accentColorUpdateTrigger)-\(appLanguage.rawValue)")
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("AccentColorChanged"))) { _ in
            accentColorUpdateTrigger = UUID()
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selectedTab {
        case "General":
            GeneralSettings()
        case "Appearance":
            Appearance()
        case "Media":
            Media()
        case "Calendar":
            CalendarSettings()
        case "HUD":
            HUD()
        case "SystemMonitor":
            SystemMonitorSettingsView()
        case "FaceID":
            FaceIDSettingsView()
        case "Shelf":
            Shelf()
        case "Clipboard":
            ClipboardSettingsView()
        case "Audio":
            AudioSettingsView()
        case "Display":
            DisplaySettingsView()
        case "Shortcuts":
            Shortcuts()
        case "Extensions":
            GeneralSettings()
        case "Advanced":
            Advanced()
        case "Language":
            LanguageSettingsView()
        case "About":
            let controller = updaterController ?? SettingsWindowController.shared.updaterController
            if let controller = controller {
                About(updaterController: controller)
            } else {
                About(
                    updaterController: SPUStandardUpdaterController(
                        startingUpdater: false,
                        updaterDelegate: AppUpdaterDelegate.shared,
                        userDriverDelegate: AppUpdaterDelegate.shared))
            }
        default:
            GeneralSettings()
        }
    }

    private func tabTitle(for tab: String) -> String {
        L10n.tr(tab, lang: appLanguage)
    }
}

/// Dedicated macOS-style top header bar matching System Settings (Sonoma/Sequoia).
/// Pinned at top with frosted material backdrop (.bar) without harsh divider lines,
/// letting form content glide cleanly underneath with native material blur.
struct SettingsDetailHeaderBar: View {
    let title: String
    var showQuitButton: Bool = false
    @Default(.appLanguage) private var appLanguage
    @State private var isQuitHovered = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)

                Spacer()

                if showQuitButton {
                    Button(role: .destructive) {
                        if let appDelegate = NSApp.delegate as? AppDelegate {
                            appDelegate.isUserInitiatedQuit = true
                            appDelegate.quitApplication()
                        } else if let appDelegate = AppDelegate.shared {
                            appDelegate.isUserInitiatedQuit = true
                            appDelegate.quitApplication()
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "power")
                            Text(loc("Quit app"))
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isQuitHovered ? Color.red : Color.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isQuitHovered ? Color.red.opacity(0.12) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isQuitHovered = hovering
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .frame(height: 52)

            Divider()
        }
        .background(.bar)
    }
}

/// Native AppKit bridge to ensure vertical scroll indicators are completely hidden
/// across all macOS versions, regardless of system "Show scroll bars: Always" preferences.
private struct ScrollViewScrollerHider: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            hideScroller(for: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            hideScroller(for: nsView)
        }
    }

    private func hideScroller(for view: NSView) {
        var current: NSView? = view
        while let p = current {
            if let sv = p as? NSScrollView {
                sv.hasVerticalScroller = false
                sv.hasHorizontalScroller = false
                sv.verticalScroller = nil
                sv.autohidesScrollers = true
                break
            }
            current = p.superview
        }
    }
}

struct NotchWidthLivePreview: View {
    let width: CGFloat
    let style: NotchStyle
    
    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .frame(height: 64)
                    .overlay(
                        Rectangle()
                            .fill(Color.primary.opacity(0.04))
                            .frame(height: 20),
                        alignment: .top
                    )
                
                VStack(spacing: 0) {
                    if style == .dynamicIsland {
                        Spacer().frame(height: 6)
                    }
                    
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.black.opacity(0.8))
                            .frame(width: 8, height: 8)
                        
                        Spacer()
                        
                        Text("\(Int(width)) px")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                        
                        Spacer()
                        
                        Image(systemName: "waveform")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.effectiveAccent)
                    }
                    .padding(.horizontal, 12)
                    .frame(
                        width: max(160, min(360, 160 + (width - 560) / (960 - 560) * 200)),
                        height: 28
                    )
                    .background(
                        style == .dynamicIsland ?
                        AnyView(Capsule().fill(Color.black)) :
                        AnyView(
                            UnevenRoundedRectangle(
                                cornerRadii: .init(
                                    topLeading: 0,
                                    bottomLeading: 12,
                                    bottomTrailing: 12,
                                    topTrailing: 0
                                )
                            ).fill(Color.black)
                        )
                    )
                    .animation(.spring(response: 0.25, dampingFraction: 0.8), value: width)
                    .animation(.spring(response: 0.25, dampingFraction: 0.8), value: style)
                }
            }
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            
            HStack {
                Text(loc("560 px (Compact)"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Text(loc("Live preview active on Notch"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(loc("960 px (Extra Wide)"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct GeneralSettings: View {
    @Environment(\.settingsHighlightedId) private var highlightedId
    @State private var screens: [(uuid: String, name: String)] = NSScreen.screens.compactMap { screen in
        guard let uuid = screen.displayUUID else { return nil }
        return (uuid, screen.localizedName)
    }
    @EnvironmentObject var vm: NotchPulseViewModel
    @ObservedObject var coordinator = NotchPulseViewCoordinator.shared

    @Default(.mirrorShape) var mirrorShape
    @Default(.showEmojis) var showEmojis
    @Default(.gestureSensitivity) var gestureSensitivity
    @Default(.minimumHoverDuration) var minimumHoverDuration
    @Default(.nonNotchHeight) var nonNotchHeight
    @Default(.nonNotchHeightMode) var nonNotchHeightMode
    @Default(.notchHeight) var notchHeight
    @Default(.notchHeightMode) var notchHeightMode
    @Default(.showOnAllDisplays) var showOnAllDisplays
    @Default(.automaticallySwitchDisplay) var automaticallySwitchDisplay
    @Default(.enableGestures) var enableGestures
    @Default(.openNotchOnHover) var openNotchOnHover
    @Default(.extendHoverArea) var extendHoverArea
    @Default(.hoverAreaPadding) var hoverAreaPadding
    @Default(.notchStyle) var notchStyle
    @Default(.dynamicIslandTopOffset) var dynamicIslandTopOffset
    @Default(.notchOpenWidth) var notchOpenWidth

    @State private var autoClosePreviewTask: Task<Void, Never>? = nil

    private func triggerWidthPreview(width: CGFloat, isEditing: Bool = false) {
        SharingStateManager.shared.preventNotchClose = true
        NotificationCenter.default.post(name: .previewNotchWidth, object: width)
        
        autoClosePreviewTask?.cancel()
        if !isEditing {
            autoClosePreviewTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(3500))
                guard !Task.isCancelled else { return }
                SharingStateManager.shared.preventNotchClose = false
                NotificationCenter.default.post(name: .closeNotchPreview, object: nil)
            }
        }
    }

    @ViewBuilder
    private var cameraMirrorSection: some View {
        Section {
            Defaults.Toggle(key: .showMirror) {
                Text(loc("Enable NotchPulse mirror"))
            }
            .disabled(!checkVideoInput())

            Picker(loc("Mirror shape"), selection: $mirrorShape) {
                Text(loc("Circle"))
                    .tag(MirrorShapeEnum.circle)
                Text(loc("Square"))
                    .tag(MirrorShapeEnum.rectangle)
            }
        } header: {
            Text(loc("Camera Mirror"))
                .id("camera_mirror")
        } footer: {
            Text(loc("Display a live selfie camera preview directly in your Notch or Dynamic Island."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var styleSection: some View {
        Section {
            HStack(spacing: 14) {
                // Option 1: Classic MacBook Notch
                Button {
                    notchStyle = .notch
                } label: {
                    VStack(spacing: 8) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(nsColor: .controlBackgroundColor))
                                .frame(height: 52)

                            // Mini Notch illustration (attached to top)
                            VStack(spacing: 0) {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.35))
                                    .frame(height: 3)
                                NotchShape(topCornerRadius: 3, bottomCornerRadius: 6)
                                    .fill(notchStyle == .notch ? Color.accentColor : Color.primary.opacity(0.7))
                                    .frame(width: 60, height: 16)
                                Spacer()
                            }
                        }

                        HStack(spacing: 5) {
                            Image(systemName: notchStyle == .notch ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(notchStyle == .notch ? Color.accentColor : .secondary)
                            Text(loc("MacBook Notch"))
                                .font(.subheadline)
                                .fontWeight(notchStyle == .notch ? .semibold : .regular)
                        }
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(notchStyle == .notch ? Color.accentColor : Color.gray.opacity(0.25), lineWidth: notchStyle == .notch ? 2 : 1)
                    )
                }
                .buttonStyle(.plain)

                // Option 2: Floating Dynamic Island
                Button {
                    notchStyle = .dynamicIsland
                } label: {
                    VStack(spacing: 8) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(nsColor: .controlBackgroundColor))
                                .frame(height: 52)

                            // Mini Dynamic Island illustration (floating pill)
                            VStack(spacing: 0) {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.35))
                                    .frame(height: 3)
                                Capsule()
                                    .fill(notchStyle == .dynamicIsland ? Color.accentColor : Color.primary.opacity(0.7))
                                    .frame(width: 52, height: 13)
                                    .padding(.top, 5)
                                Spacer()
                            }
                        }

                        HStack(spacing: 5) {
                            Image(systemName: notchStyle == .dynamicIsland ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(notchStyle == .dynamicIsland ? Color.accentColor : .secondary)
                            Text(loc("Dynamic Island"))
                                .font(.subheadline)
                                .fontWeight(notchStyle == .dynamicIsland ? .semibold : .regular)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 4)

            // Show top offset slider only for Dynamic Island
            if notchStyle == .dynamicIsland {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(loc("Top Gap (Distance from Screen Edge)"))
                        Spacer()
                        Text("\(Int(dynamicIslandTopOffset)) px")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $dynamicIslandTopOffset, in: 0...24, step: 1) {
                        Text(loc("Top Gap"))
                    } minimumValueLabel: {
                        Text("0px")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } maximumValueLabel: {
                        Text("24px")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(loc("Sets the floating gap between the top bezel and the Dynamic Island capsule."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        } header: {
            Text(loc("Notch / Island Style"))
        }
    }

    @ViewBuilder
    private var dimensionsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(loc("Expanded Width"))
                    Spacer()
                    Text("\(Int(notchOpenWidth)) px")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .fontWeight(.medium)
                    
                    Button(loc("Reset")) {
                        notchOpenWidth = 740
                        triggerWidthPreview(width: 740, isEditing: false)
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .disabled(notchOpenWidth == 740)
                }
                
                // Live Visual Preview directly inside Settings
                NotchWidthLivePreview(width: notchOpenWidth, style: notchStyle)
                
                Slider(
                    value: $notchOpenWidth,
                    in: 560...960,
                    step: 10,
                    label: {
                        Text(loc("Notch Width"))
                    },
                    minimumValueLabel: {
                        Text("560px")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    },
                    maximumValueLabel: {
                        Text("960px")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    },
                    onEditingChanged: { editing in
                        triggerWidthPreview(width: notchOpenWidth, isEditing: editing)
                    }
                )
                
                HStack(spacing: 8) {
                    Button(loc("Compact (580px)")) {
                        notchOpenWidth = 580
                        triggerWidthPreview(width: 580, isEditing: false)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    Button(loc("Standard (740px)")) {
                        notchOpenWidth = 740
                        triggerWidthPreview(width: 740, isEditing: false)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    Button(loc("Wide (860px)")) {
                        notchOpenWidth = 860
                        triggerWidthPreview(width: 860, isEditing: false)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.top, 2)
                
                Text(loc("Controls the horizontal expansion length when the notch or dynamic island is open. The notch opens and resizes live on your screen as you drag the slider."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            .onChange(of: notchOpenWidth) { _, newWidth in
                triggerWidthPreview(width: newWidth, isEditing: true)
            }
            .onDisappear {
                autoClosePreviewTask?.cancel()
                SharingStateManager.shared.preventNotchClose = false
                NotificationCenter.default.post(name: .closeNotchPreview, object: nil)
            }
        } header: {
            Text(loc("Notch Dimensions (Width)"))
        }
    }

    @ViewBuilder
    private var systemFeaturesSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { Defaults[.menubarIcon] },
                set: { Defaults[.menubarIcon] = $0 }
            )) {
                Text(loc("Show menu bar icon"))
            }
            .tint(.effectiveAccent)
            LaunchAtLogin.Toggle(loc("Launch at login"))
            Defaults.Toggle(key: .showOnAllDisplays) {
                Text(loc("Show on all displays"))
            }
            .onChange(of: showOnAllDisplays) {
                NotificationCenter.default.post(
                    name: Notification.Name.showOnAllDisplaysChanged, object: nil)
            }
            Picker(loc("Preferred display"), selection: $coordinator.preferredScreenUUID) {
                ForEach(screens, id: \.uuid) { screen in
                    Text(screen.name).tag(screen.uuid as String?)
                }
            }
            .onAppear {
                screens = NSScreen.screens.compactMap { screen in
                    guard let uuid = screen.displayUUID else { return nil }
                    return (uuid, screen.localizedName)
                }
            }
            .onChange(of: NSScreen.screens) {
                screens = NSScreen.screens.compactMap { screen in
                    guard let uuid = screen.displayUUID else { return nil }
                    return (uuid, screen.localizedName)
                }
            }
            .disabled(showOnAllDisplays)
            
            Defaults.Toggle(key: .automaticallySwitchDisplay) {
                Text(loc("Automatically switch displays"))
            }
            .onChange(of: automaticallySwitchDisplay) {
                NotificationCenter.default.post(
                    name: Notification.Name.automaticallySwitchDisplayChanged, object: nil)
            }
            .disabled(showOnAllDisplays)
        } header: {
            Text(loc("System features"))
        }
    }

    @ViewBuilder
    private var notchSizingSection: some View {
        Section {
            Picker(
                selection: $notchHeightMode,
                label:
                    Text(loc("Notch height on notch displays"))
            ) {
                Text(loc("Match real notch height"))
                    .tag(WindowHeightMode.matchRealNotchSize)
                Text(loc("Match menu bar height"))
                    .tag(WindowHeightMode.matchMenuBar)
                Text(loc("Custom height"))
                    .tag(WindowHeightMode.custom)
            }
            .onChange(of: notchHeightMode) {
                switch notchHeightMode {
                case .matchRealNotchSize:
                    notchHeight = 38
                case .matchMenuBar:
                    notchHeight = 44
                case .custom:
                    notchHeight = 38
                }
                NotificationCenter.default.post(
                    name: Notification.Name.notchHeightChanged, object: nil)
            }
            if notchHeightMode == .custom {
                Slider(value: $notchHeight, in: 15...45, step: 1) {
                    Text(loc("Custom notch size - %@", String(format: "%.0f", notchHeight)))
                }
                .onChange(of: notchHeight) {
                    NotificationCenter.default.post(
                        name: Notification.Name.notchHeightChanged, object: nil)
                }
            }
            Picker(loc("Notch height on non-notch displays"), selection: $nonNotchHeightMode) {
                Text(loc("Match menubar height"))
                    .tag(WindowHeightMode.matchMenuBar)
                Text(loc("Match real notch height"))
                    .tag(WindowHeightMode.matchRealNotchSize)
                Text(loc("Custom height"))
                    .tag(WindowHeightMode.custom)
            }
            .onChange(of: nonNotchHeightMode) {
                switch nonNotchHeightMode {
                case .matchMenuBar:
                    nonNotchHeight = 24
                case .matchRealNotchSize:
                    nonNotchHeight = 32
                case .custom:
                    nonNotchHeight = 32
                }
                NotificationCenter.default.post(
                    name: Notification.Name.notchHeightChanged, object: nil)
            }
            if nonNotchHeightMode == .custom {
                Slider(value: $nonNotchHeight, in: 0...40, step: 1) {
                    Text(loc("Custom notch size - %@", String(format: "%.0f", nonNotchHeight)))
                }
                .onChange(of: nonNotchHeight) {
                    NotificationCenter.default.post(
                        name: Notification.Name.notchHeightChanged, object: nil)
                }
            }
        } header: {
            Text(loc("Notch sizing"))
        }
    }

    var body: some View {
        Form {
            Section {
                Button(action: {
                    FeatureTourController.shared.startTour()
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkles")
                            .foregroundColor(.white)
                            .font(.system(size: 16))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(loc("Feature Tour"))
                                .font(.system(size: 13, weight: .semibold))
                            Text(loc("Interactive Spotlight walkthrough highlighting all Notch features."))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .contentShape(Rectangle())
            }
            .id("feature_tour")
            .searchHighlight(highlightedId == "feature_tour")

            styleSection
                .id("notch_style")
                .searchHighlight(highlightedId == "notch_style")

            dimensionsSection
                .id("notch_dimensions")
                .searchHighlight(highlightedId == "notch_dimensions")

            systemFeaturesSection
                .id("system_features")
                .searchHighlight(highlightedId == "system_features")

            cameraMirrorSection
                .id("camera_mirror")
                .searchHighlight(highlightedId == "camera_mirror")

            notchSizingSection
                .id("notch_sizing")
                .searchHighlight(highlightedId == "notch_sizing")

            NotchBehaviour()
                .id("notch_behavior")
                .searchHighlight(highlightedId == "notch_behavior")
        }
        .accentColor(.effectiveAccent)
    }

    @ViewBuilder
    func NotchBehaviour() -> some View {
        Section {
            Defaults.Toggle(key: .openNotchOnHover) {
                Text(loc("Open notch on hover"))
            }
            Defaults.Toggle(key: .enableHaptics) {
                    Text(loc("Enable haptic feedback"))
            }
            VStack(alignment: .leading, spacing: 4) {
                Toggle(loc("Restore last tab on hover"), isOn: $coordinator.openLastTabByDefault)
                Text(loc("When opening the notch on hover, restore the last selected tab (e.g. CPU/RAM Stats, Battery) instead of resetting to Home."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if openNotchOnHover {
                Slider(value: $minimumHoverDuration, in: 0...1, step: 0.1) {
                    HStack {
                        Text(loc("Hover delay"))
                        Spacer()
                        Text("\(minimumHoverDuration, specifier: "%.1f")s")
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: minimumHoverDuration) {
                    NotificationCenter.default.post(
                        name: Notification.Name.notchHeightChanged, object: nil)
                }

                Defaults.Toggle(key: .extendHoverArea) {
                    Text(loc("Extend hover area"))
                }
                .onChange(of: extendHoverArea) {
                    NotificationCenter.default.post(
                        name: Notification.Name.expandedDragDetectionChanged,
                        object: nil
                    )
                }
                
                if extendHoverArea {
                    Slider(value: $hoverAreaPadding, in: 5...60, step: 5) {
                        HStack {
                            Text(loc("Hover detection range"))
                            Spacer()
                            Text("\(hoverAreaPadding, specifier: "%.0f") px")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onChange(of: hoverAreaPadding) {
                        NotificationCenter.default.post(
                            name: Notification.Name.expandedDragDetectionChanged,
                            object: nil
                        )
                    }
                    Text(loc("Expands the sensitivity area for hovering to open the notch, separate from Drag & Drop distance."))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        } header: {
            Text(loc("Notch behavior"))
        }
    }
}



//struct Downloads: View {
//    @Default(.selectedDownloadIndicatorStyle) var selectedDownloadIndicatorStyle
//    @Default(.selectedDownloadIconStyle) var selectedDownloadIconStyle
//    var body: some View {
//        Form {
//            warningBadge("We don't support downloads yet", "It will be supported later on.")
//            Section {
//                Defaults.Toggle(key: .enableDownloadListener) {
//                    Text("Show download progress")
//                }
//                    .disabled(true)
//                Defaults.Toggle(key: .enableSafariDownloads) {
//                    Text("Enable Safari Downloads")
//                }
//                    .disabled(!Defaults[.enableDownloadListener])
//                Picker("Download indicator style", selection: $selectedDownloadIndicatorStyle) {
//                    Text("Progress bar")
//                        .tag(DownloadIndicatorStyle.progress)
//                    Text("Percentage")
//                        .tag(DownloadIndicatorStyle.percentage)
//                }
//                Picker("Download icon style", selection: $selectedDownloadIconStyle) {
//                    Text("Only app icon")
//                        .tag(DownloadIconStyle.onlyAppIcon)
//                    Text("Only download icon")
//                        .tag(DownloadIconStyle.onlyIcon)
//                    Text("Both")
//                        .tag(DownloadIconStyle.iconAndAppIcon)
//                }
//
//            } header: {
//                HStack {
//                    Text("Download indicators")
//                    comingSoonTag()
//                }
//            }
//            Section {
//                List {
//                    ForEach([].indices, id: \.self) { index in
//                        Text("\(index)")
//                    }
//                }
//                .frame(minHeight: 96)
//                .overlay {
//                    if true {
//                        Text("No excluded apps")
//                            .foregroundStyle(Color(.secondaryLabelColor))
//                    }
//                }
//                .actionBar(padding: 0) {
//                    Group {
//                        Button {
//                        } label: {
//                            Image(systemName: "plus")
//                                .frame(width: 25, height: 16, alignment: .center)
//                                .contentShape(Rectangle())
//                                .foregroundStyle(.secondary)
//                        }
//
//                        Divider()
//                        Button {
//                        } label: {
//                            Image(systemName: "minus")
//                                .frame(width: 20, height: 16, alignment: .center)
//                                .contentShape(Rectangle())
//                                .foregroundStyle(.secondary)
//                        }
//                    }
//                }
//            } header: {
//                HStack(spacing: 4) {
//                    Text("Exclude apps")
//                    comingSoonTag()
//                }
//            }
//        }
//        .navigationTitle("Downloads")
//    }
//}

struct HUD: View {
    @Environment(\.settingsHighlightedId) private var highlightedId
    @EnvironmentObject var vm: NotchPulseViewModel
    @Default(.inlineHUD) var inlineHUD
    @Default(.enableGradient) var enableGradient
    @Default(.optionKeyAction) var optionKeyAction
    @Default(.hudReplacement) var hudReplacement
    @ObservedObject var coordinator = NotchPulseViewCoordinator.shared
    @State private var accessibilityAuthorized = false
    
    var body: some View {
        Form {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc("Replace system HUD"))
                            .font(.headline)
                        Text(loc("Replaces the standard macOS volume, display brightness, and keyboard brightness HUDs with a custom design."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 40)
                    Defaults.Toggle("", key: .hudReplacement)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.large)
                    .disabled(!accessibilityAuthorized)
                }
                
                if !accessibilityAuthorized {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(loc("Accessibility access is required to replace the system HUD."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            Button(loc("Request Accessibility")) {
                                XPCHelperClient.shared.requestAccessibilityAuthorization()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(.top, 6)
                }
            }
            .id("hud_volume")
            .searchHighlight(highlightedId == "hud_volume")
            
            Section {
                Picker(loc("Option key behaviour"), selection: $optionKeyAction) {
                    ForEach(OptionKeyAction.allCases) { opt in
                        Text(loc(opt.rawValue)).tag(opt)
                    }
                }
                
                Picker(loc("Progress bar style"), selection: $enableGradient) {
                    Text(loc("Hierarchical"))
                        .tag(false)
                    Text(loc("Gradient"))
                        .tag(true)
                }
                Defaults.Toggle(key: .systemEventIndicatorShadow) {
                    Text(loc("Enable glowing effect"))
                }
                Defaults.Toggle(key: .systemEventIndicatorUseAccent) {
                    Text(loc("Tint progress bar with accent color"))
                }
            } header: {
                Text(loc("General"))
            }
            .disabled(!hudReplacement)
            
            Section {
                Defaults.Toggle(key: .showOpenNotchHUD) {
                    Text(loc("Show HUD in open notch"))
                }
                Defaults.Toggle(key: .showOpenNotchHUDPercentage) {
                    Text(loc("Show percentage"))
                }
                .disabled(!Defaults[.showOpenNotchHUD])
            } header: {
                HStack {
                    Text(loc("Open Notch"))
                    customBadge(text: loc("Beta"))
                }
                .id("hud_power")
            }
            .id("hud_power")
            .searchHighlight(highlightedId == "hud_power")
            .disabled(!hudReplacement)
            
            Section {
                Picker(loc("HUD style"), selection: $inlineHUD) {
                    Text(loc("Default"))
                        .tag(false)
                    Text(loc("Inline"))
                        .tag(true)
                }
                .onChange(of: Defaults[.inlineHUD]) {
                    if Defaults[.inlineHUD] {
                        withAnimation {
                            Defaults[.systemEventIndicatorShadow] = false
                            Defaults[.enableGradient] = false
                        }
                    }
                }
                
                Defaults.Toggle(key: .showClosedNotchHUDPercentage) {
                    Text(loc("Show percentage"))
                }
            } header: {
                Text(loc("Closed Notch"))
                    .id("hud_inline")
            }
            .id("hud_inline")
            .searchHighlight(highlightedId == "hud_inline")
            .disabled(!Defaults[.hudReplacement])
        }
        .accentColor(.effectiveAccent)
        .task {
            accessibilityAuthorized = await XPCHelperClient.shared.isAccessibilityAuthorized()
        }
        .onAppear {
            XPCHelperClient.shared.startMonitoringAccessibilityAuthorization(every: 1.0)
        }
        .onDisappear {
            XPCHelperClient.shared.stopMonitoringAccessibilityAuthorization()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { @MainActor in
                accessibilityAuthorized = await XPCHelperClient.shared.isAccessibilityAuthorized()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .accessibilityAuthorizationChanged)) { notification in
            if let granted = notification.userInfo?["granted"] as? Bool {
                accessibilityAuthorized = granted
            }
        }
    }
}

struct SystemMonitorSettingsView: View {
    @Environment(\.settingsHighlightedId) private var highlightedId
    @Default(.enableSystemMonitor) var enableSystemMonitor
    @Default(.systemMonitorShowProcesses) var showProcesses
    @ObservedObject private var monitor = SystemMonitorManager.shared

    private enum MonitorMetric { case cpu, ram }
    @State private var expandedMetric: MonitorMetric?

    var body: some View {
        Form {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc("System Monitor (Stats)"))
                            .font(.headline)
                        Text(loc("Monitor real-time CPU, RAM, and GPU load in a dedicated Notch tab inspired by the 'Stats' app."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 40)
                    Defaults.Toggle("", key: .enableSystemMonitor)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.large)
                }

                HStack(spacing: 8) {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 14))
                    Text(loc("System Monitoring Access: Active (Darwin Mach & IOKit native APIs)"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }
            .id("sysmon_enable")
            .searchHighlight(highlightedId == "sysmon_enable")

            Section {
                Defaults.Toggle(key: .systemMonitorShowProcesses) {
                    Text(loc("Show top resource-consuming processes"))
                }
            } header: {
                Text(loc("Display Options"))
                    .id("sysmon_display")
            }
            .id("sysmon_display")
            .searchHighlight(highlightedId == "sysmon_display")
            .disabled(!enableSystemMonitor)

            Section {
                VStack(spacing: 12) {
                    HStack(spacing: 16) {
                        // Mini CPU — click to expand the per-app CPU list (largest first)
                        MonitorTileButton(
                            icon: "cpu",
                            tint: .blue,
                            title: loc("CPU"),
                            value: String(format: "%.0f%%", monitor.cpuTotal),
                            subtitle: nil,
                            isExpanded: expandedMetric == .cpu,
                            action: { expandedMetric = (expandedMetric == .cpu) ? nil : .cpu }
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Divider()

                        // Mini RAM — click to expand the per-app memory list (largest first)
                        MonitorTileButton(
                            icon: "memorychip",
                            tint: .green,
                            title: loc("RAM"),
                            value: String(format: "%.1f / %.0f GB", monitor.ramUsedGB, monitor.ramTotalGB),
                            subtitle: "\(loc("Swap")): \(monitor.swapUsedFormatted)",
                            isExpanded: expandedMetric == .ram,
                            action: { expandedMetric = (expandedMetric == .ram) ? nil : .ram }
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Divider()

                        // Mini GPU
                        MonitorTileButton(
                            icon: "display",
                            tint: .purple,
                            title: loc("GPU"),
                            value: String(format: "%.0f%%", monitor.gpuUsage),
                            subtitle: nil,
                            isExpanded: false,
                            action: {}
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 4)

                    if showProcesses, expandedMetric == .cpu {
                        MonitorProcessList(
                            title: loc("CPU"), icon: "cpu", tint: .blue,
                            items: monitor.topCpuProcesses,
                            emptyText: loc("No processes using CPU right now")
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    if showProcesses, expandedMetric == .ram {
                        MonitorProcessList(
                            title: loc("RAM"), icon: "memorychip", tint: .green,
                            items: monitor.topRamProcesses,
                            emptyText: loc("No processes using memory right now")
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .animation(.smooth(duration: 0.22), value: expandedMetric)
            } header: {
                Text(loc("Preview"))
            }
            .disabled(!enableSystemMonitor)
            Section {
                HardwareFanDiagnosticsView()
            } header: {
                Text(loc("Hardware Fan Control & Profiles"))
                    .id("sysmon_cooling")
            } footer: {
                Text(loc("Apple Silicon SMC fan hardware controls & operational profiles guide."))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .id("sysmon_cooling")
            .searchHighlight(highlightedId == "sysmon_cooling")
        }
        .accentColor(.effectiveAccent)
        .onAppear {
            monitor.shouldFetchProcesses = (expandedMetric != nil)
            monitor.startMonitoring()
        }
        .onChange(of: expandedMetric) { _, metric in
            monitor.shouldFetchProcesses = (metric != nil)
            if monitor.shouldFetchProcesses {
                monitor.requestMetricsUpdate()
            }
        }
        .onDisappear {
            expandedMetric = nil
            monitor.shouldFetchProcesses = false
            monitor.stopMonitoring()
        }
    }
}

/// Hardware SMC fan operational profile guide.
private struct HardwareFanDiagnosticsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(loc("Fan Profiles & Behavior"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(loc("Controlled via Notch"))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 6) {
                FanProfileRow(
                    title: loc("Auto (Apple Default)"),
                    summary: loc("macOS kernel handles fan speed automatically. Fans stay at minimum RPM or turn off completely during light tasks to save battery and maintain silence.")
                )

                FanProfileRow(
                    title: loc("Balanced"),
                    summary: loc("Maintains optimal thermal-to-noise balance, capping fan speed around ~60% (~4,400 RPM) to keep the system cool without excessive noise.")
                )

                FanProfileRow(
                    title: loc("Smart (Predictive)"),
                    summary: loc("Monitors SoC thermal acceleration to ramp up fans preemptively before sudden heat spikes, preventing thermal throttling.")
                )

                FanProfileRow(
                    title: loc("Max 100%"),
                    summary: loc("Locks fans to maximum hardware RPM (~6,550 RPM) for intensive rendering, video export, heavy compilation, or gaming.")
                )

                FanProfileRow(
                    title: loc("Custom (Manual)"),
                    summary: loc("Drag the fan slider directly from the Notch interface to lock fans at any specific percentage or RPM target.")
                )
            }

            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.top, 1)

                Text(loc("You can switch fan profiles or drag the custom speed slider directly inside the Notch / Dynamic Island without opening Settings."))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 4)
            .padding(.horizontal, 2)
        }
        .padding(.vertical, 4)
    }
}

private struct FanProfileRow: View {
    let title: String
    let summary: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
            Text(summary)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.03)))
    }
}

/// Clickable metric tile — expands into the per-app process list (Activity Monitor style).
private struct MonitorTileButton: View {
    let icon: String
    let tint: Color
    let title: String
    let value: String
    let subtitle: String?
    let isExpanded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 3) {
                        Text(title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if isExpanded {
                            Image(systemName: "chevron.up")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.secondary)
                        } else {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Text(value)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Top-consumers list, sorted largest → smallest, refreshed live by SystemMonitorManager.
private struct MonitorProcessList: View {
    let title: String
    let icon: String
    let tint: Color
    let items: [MonitorProcessItem]
    let emptyText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundStyle(tint)
                Text(loc("Top apps by \(title)"))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(loc("largest first"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if items.isEmpty {
                Text(emptyText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(spacing: 8) {
                        Text("\(index + 1).")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .frame(width: 22, alignment: .leading)
                        Text(item.name)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 12)
                        Text(item.value)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(tint)
                            .monospacedDigit()
                    }
                    .padding(.vertical, 1)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.04))
        )
    }
}

struct Media: View {
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
                        .controlSize(.large)
                }
            }
            .id("media_enable")
            .searchHighlight(highlightedId == "media_enable")

            Section {
                Picker(loc("Music Source"), selection: $mediaController) {
                    ForEach(availableMediaControllers) { controller in
                        Text(controller.rawValue).tag(controller)
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
                        .foregroundColor(.blue)  // Ensures it's visibly a link
                    }
                } else {
                    Text(
                        loc("'Now Playing' was the only option on previous versions and works with all media apps.")
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
                    label:
                        HStack {
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
            }  footer: {
                Text(loc("Customize which controls appear in the music player. Grant automation access for Spotify and Apple Music to keep playback and lyrics precisely in sync."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .id("media_controls")
            .searchHighlight(highlightedId == "media_controls")
        }
        .onAppear {
            isMusicSyncConfirmed = MediaAutomationPermissionHelper.isSyncConfirmed()
        }
        .accentColor(.effectiveAccent)
    }

    // Only show controller options that are available on this macOS version
    private var availableMediaControllers: [MediaControllerType] {
        if MusicManager.shared.isNowPlayingDeprecated {
            return MediaControllerType.allCases.filter { $0 != .nowPlaying }
        } else {
            return MediaControllerType.allCases
        }
    }
}

struct CalendarSettings: View {
    @Environment(\.settingsHighlightedId) private var highlightedId
    @ObservedObject private var calendarManager = CalendarManager.shared
    @Default(.showCalendar) var showCalendar: Bool
    @Default(.hideCompletedReminders) var hideCompletedReminders
    @Default(.hideAllDayEvents) var hideAllDayEvents
    @Default(.autoScrollToNextEvent) var autoScrollToNextEvent
    @Default(.appLanguage) private var appLanguage
    @Default(.alternateCalendarType) private var alternateCalendarType
    @Default(.showLunarCalendar) private var showLunarCalendar

    var body: some View {
        Form {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc("Enable Calendar"))
                            .font(.headline)
                        Text(loc("Show upcoming calendar events, reminders, and lunar dates in the Notch."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 40)
                    Defaults.Toggle("", key: .showCalendar)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.large)
                }
            }
            .id("calendar_integration")
            .searchHighlight(highlightedId == "calendar_integration")

            Section(header: Text(loc("Display Options")).id("calendar_options")) {
                Defaults.Toggle(key: .hideCompletedReminders) {
                    Text(loc("Hide completed reminders"))
                }
                Defaults.Toggle(key: .hideAllDayEvents) {
                    Text(loc("Hide all-day events"))
                }
                Defaults.Toggle(key: .autoScrollToNextEvent) {
                    Text(loc("Auto-scroll to next event"))
                }
                Defaults.Toggle(key: .showFullEventTitles) {
                    Text(loc("Always show full event titles"))
                }
            }
            .id("calendar_options")
            .searchHighlight(highlightedId == "calendar_options")

            Section(header: Text(loc("Lunar Calendar Region")).id("calendar_alternate")) {
                Picker(loc("Lunar Calendar Region"), selection: $alternateCalendarType) {
                    ForEach(AlternateCalendarType.allCases) { type in
                        Text(type.localizedName(for: appLanguage)).tag(type)
                    }
                }

                Defaults.Toggle(key: .showLunarCalendar) {
                    Text(loc("Show lunar date in month grid"))
                }

                Text(loc("Supports lunar calendar calculation according to local regional timezone (Vietnam UTC+7, Taiwan / China UTC+8)."))
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            .id("calendar_alternate")
            .searchHighlight(highlightedId == "calendar_alternate")

            Section(header: Text(loc("Calendars"))) {
                if calendarManager.calendarAuthorizationStatus != .fullAccess {
                    Text(loc("Calendar access is denied. Please enable it in System Settings."))
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding()
                    Button(loc("Open Calendar Settings")) {
                        if let settingsURL = URL(
                            string:
                                "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
                        ) {
                            NSWorkspace.shared.open(settingsURL)
                        }
                    }
                } else {
                    List {
                        ForEach(calendarManager.eventCalendars, id: \.id) { calendar in
                            Toggle(
                                isOn: Binding(
                                    get: { calendarManager.getCalendarSelected(calendar) },
                                    set: { isSelected in
                                        Task {
                                            await calendarManager.setCalendarSelected(
                                                calendar, isSelected: isSelected)
                                        }
                                    }
                                )
                            ) {
                                Text(calendar.title)
                            }
                            .accentColor(lighterColor(from: calendar.color))
                            .disabled(!showCalendar)
                        }
                    }
                }
            }
            Section(header: Text(loc("Reminders"))) {
                if calendarManager.reminderAuthorizationStatus != .fullAccess {
                    Text(loc("Reminder access is denied. Please enable it in System Settings."))
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding()
                    Button(loc("Open Reminder Settings")) {
                        if let settingsURL = URL(
                            string:
                                "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders"
                        ) {
                            NSWorkspace.shared.open(settingsURL)
                        }
                    }
                } else {
                    List {
                        ForEach(calendarManager.reminderLists, id: \.id) { calendar in
                            Toggle(
                                isOn: Binding(
                                    get: { calendarManager.getCalendarSelected(calendar) },
                                    set: { isSelected in
                                        Task {
                                            await calendarManager.setCalendarSelected(
                                                calendar, isSelected: isSelected)
                                        }
                                    }
                                )
                            ) {
                                Text(calendar.title)
                            }
                            .accentColor(lighterColor(from: calendar.color))
                            .disabled(!showCalendar)
                        }
                    }
                }
            }
        }
        .accentColor(.effectiveAccent)
        .onAppear {
            Task {
                await calendarManager.checkCalendarAuthorization()
                await calendarManager.checkReminderAuthorization()
            }
        }
    }
}

func lighterColor(from nsColor: NSColor, amount: CGFloat = 0.14) -> Color {
    let srgb = nsColor.usingColorSpace(.sRGB) ?? nsColor
    var (r, g, b, a): (CGFloat, CGFloat, CGFloat, CGFloat) = (0,0,0,0)
    srgb.getRed(&r, green: &g, blue: &b, alpha: &a)

    func lighten(_ c: CGFloat) -> CGFloat {
        let increased = c + (1.0 - c) * amount
        return min(max(increased, 0), 1)
    }

    let nr = lighten(r)
    let ng = lighten(g)
    let nb = lighten(b)

    return Color(red: Double(nr), green: Double(ng), blue: Double(nb), opacity: Double(a))
}

struct About: View {
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

struct Shelf: View {
    @Environment(\.settingsHighlightedId) private var highlightedId
    @Default(.shelfTapToOpen) var shelfTapToOpen: Bool
    @Default(.quickShareProvider) var quickShareProvider
    @Default(.shakeAutoCloseDelay) var shakeAutoCloseDelay
    @Default(.shelfDragOpenPadding) var shelfDragOpenPadding
    @StateObject private var quickShareService = QuickShareService.shared

    private var selectedProvider: QuickShareProvider? {
        quickShareService.availableProviders.first(where: { $0.id == quickShareProvider })
    }
    
    init() {
        Task { await QuickShareService.shared.discoverAvailableProviders() }
    }
    
    var body: some View {
        Form {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc("Enable Shelf"))
                            .font(.headline)
                        Text(loc("Temporary storage for drag & drop files and quick sharing directly in the Notch."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 40)
                    Defaults.Toggle("", key: .notchPulseShelf)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.large)
                }
            }
            .id("shelf_general")
            .searchHighlight(highlightedId == "shelf_general")

            Section {
                Defaults.Toggle(key: .openShelfByDefault) {
                    Text(loc("Open shelf by default if items are present"))
                }
                Defaults.Toggle(key: .copyOnDrag) {
                    Text(loc("Copy items on drag"))
                }
                Defaults.Toggle(key: .autoRemoveShelfItems) {
                    Text(loc("Remove from shelf after dragging"))
                }

                Slider(value: $shakeAutoCloseDelay, in: 2...20, step: 1) {
                    HStack {
                        Text(loc("Shelf auto-close delay"))
                        Spacer()
                        Text("\(Int(shakeAutoCloseDelay))s")
                            .foregroundStyle(.secondary)
                    }
                }
                Text(loc("After the shelf opens — by shaking while dragging a file, or by hovering the dragged file near the notch — it closes automatically after this many seconds if you do not drop anything. While you keep holding the file over the shelf, it never closes."))
                    .font(.caption)
                    .foregroundColor(.secondary)

                Slider(value: $shelfDragOpenPadding, in: 0...240, step: 10) {
                    HStack {
                        Text(loc("File-drag open area"))
                        Spacer()
                        Text(shelfDragOpenPadding == 0 ? loc("Off") : "+\(Int(shelfDragOpenPadding))px")
                            .foregroundStyle(.secondary)
                    }
                }
                Text(loc("While dragging a file, hovering this close to the notch opens the shelf instantly — no shake needed. Lets you drag files straight out of the Dock (e.g. the Downloads stack) into the shelf. Set to 0 to require the shake gesture instead."))
                    .font(.caption)
                    .foregroundColor(.secondary)

            } header: {
                HStack {
                    Text(loc("General"))
                }
            }
            
            Section {
                Picker(loc("Quick Share Service"), selection: $quickShareProvider) {
                    ForEach(quickShareService.availableProviders, id: \.id) { provider in
                        HStack {
                            Group {
                                if let imgData = provider.imageData, let nsImg = NSImage(data: imgData) {
                                    Image(nsImage: nsImg)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                } else {
                                    Image(systemName: "square.and.arrow.up")
                                }
                            }
                            .frame(width: 16, height: 16)
                            .foregroundStyle(.secondary)
                            Text(provider.id)
                        }
                        .tag(provider.id)
                    }
                }
                .pickerStyle(.menu)
                
                if let selectedProvider = selectedProvider {
                    HStack {
                        Group {
                            if let imgData = selectedProvider.imageData, let nsImg = NSImage(data: imgData) {
                                Image(nsImage: nsImg)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                            } else {
                                Image(systemName: "square.and.arrow.up")
                            }
                        }
                        .frame(width: 16, height: 16)
                        .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(loc("Currently selected")): \(selectedProvider.id)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(loc("Files dropped on the shelf will be shared via this service"))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                
            } header: {
                HStack {
                    Text(loc("Quick Share"))
                }
            } footer: {
                Text(loc("Choose which service to use when sharing files from the shelf. Click the shelf button to select files, or drag files onto it to share immediately."))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .id("shelf_storage")
            .searchHighlight(highlightedId == "shelf_storage")
        }
        .accentColor(.effectiveAccent)
    }
}

struct Appearance: View {
    @Environment(\.settingsHighlightedId) private var highlightedId
    @ObservedObject var coordinator = NotchPulseViewCoordinator.shared
    @Default(.mirrorShape) var mirrorShape
    @Default(.sliderColor) var sliderColor
    @Default(.useMusicVisualizer) var useMusicVisualizer
    @Default(.customVisualizers) var customVisualizers
    @Default(.selectedVisualizer) var selectedVisualizer

    let icons: [String] = ["logo2"]
    @State private var selectedIcon: String = "logo2"
    @State private var selectedListVisualizer: CustomVisualizer? = nil
    @State private var isPresented: Bool = false
    @State private var name: String = ""
    @State private var url: String = ""
    @State private var speed: CGFloat = 1.0
    var body: some View {
        Form {
            Section {
                Toggle(loc("Always show tabs"), isOn: $coordinator.alwaysShowTabs)
                Defaults.Toggle(key: .settingsIconInNotch) {
                    Text(loc("Show settings icon in notch"))
                }

            } header: {
                Text(loc("General"))
                    .id("appearance_general")
            }
            .id("appearance_general")
            .searchHighlight(highlightedId == "appearance_general")

            Section {
                Defaults.Toggle(key: .coloredSpectrogram) {
                    Text(loc("Colored spectrogram"))
                }
                Defaults
                    .Toggle(loc("Player tinting"), key: .playerColorTinting)
                Defaults.Toggle(key: .lightingEffect) {
                    Text(loc("Enable blur effect behind album art"))
                }
                Picker(loc("Slider color"), selection: $sliderColor) {
                    ForEach(SliderColorEnum.allCases, id: \.self) { option in
                        Text(loc(option.rawValue))
                    }
                }
            } header: {
                Text(loc("Media"))
                    .id("appearance_media")
            }
            .id("appearance_media")
            .searchHighlight(highlightedId == "appearance_media")

            Section {
                Toggle(
                    loc("Use music visualizer spectrogram"),
                    isOn: $useMusicVisualizer.animation()
                )
                .disabled(true)
                if !useMusicVisualizer {
                    if customVisualizers.count > 0 {
                        Picker(
                            loc("Selected animation"),
                            selection: $selectedVisualizer
                        ) {
                            ForEach(
                                customVisualizers,
                                id: \.self
                            ) { visualizer in
                                Text(visualizer.name)
                                    .tag(visualizer)
                            }
                        }
                    } else {
                        HStack {
                            Text(loc("Selected animation"))
                            Spacer()
                            Text(loc("No custom animation available"))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                HStack {
                    Text(loc("Custom music live activity animation"))
                    customBadge(text: loc("Coming soon"))
                }
                .id("appearance_visualizer")
            }
            .id("appearance_visualizer")
            .searchHighlight(highlightedId == "appearance_visualizer")

            Section {
                List {
                    ForEach(customVisualizers, id: \.self) { visualizer in
                        HStack {
                            LottieView(
                                url: visualizer.url, speed: visualizer.speed,
                                loopMode: .loop
                            )
                            .frame(width: 30, height: 30, alignment: .center)
                            Text(visualizer.name)
                            Spacer(minLength: 0)
                            if selectedVisualizer == visualizer {
                                Text(loc("selected"))
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.secondary)
                                    .padding(.trailing, 8)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.vertical, 2)
                        .background(
                            selectedListVisualizer != nil
                                ? selectedListVisualizer == visualizer
                                    ? Color.effectiveAccent : Color.clear : Color.clear,
                            in: RoundedRectangle(cornerRadius: 5)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if selectedListVisualizer == visualizer {
                                selectedListVisualizer = nil
                                return
                            }
                            selectedListVisualizer = visualizer
                        }
                    }
                }
                .safeAreaPadding(
                    EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0)
                )
                .frame(minHeight: 120)
                .actionBar {
                    HStack(spacing: 5) {
                        Button {
                            name = ""
                            url = ""
                            speed = 1.0
                            isPresented.toggle()
                        } label: {
                            Image(systemName: "plus")
                                .foregroundStyle(.secondary)
                                .contentShape(Rectangle())
                        }
                        Divider()
                        Button {
                            if selectedListVisualizer != nil {
                                let visualizer = selectedListVisualizer!
                                selectedListVisualizer = nil
                                customVisualizers.remove(
                                    at: customVisualizers.firstIndex(of: visualizer)!)
                                if visualizer == selectedVisualizer && customVisualizers.count > 0 {
                                    selectedVisualizer = customVisualizers[0]
                                }
                            }
                        } label: {
                            Image(systemName: "minus")
                                .foregroundStyle(.secondary)
                                .contentShape(Rectangle())
                        }
                    }
                }
                .controlSize(.small)
                .buttonStyle(PlainButtonStyle())
                .overlay {
                    if customVisualizers.isEmpty {
                        Text(loc("No custom visualizer"))
                            .foregroundStyle(Color(.secondaryLabelColor))
                            .padding(.bottom, 22)
                    }
                }
                .sheet(isPresented: $isPresented) {
                    VStack(alignment: .leading) {
                        Text(loc("Add new visualizer"))
                            .font(.largeTitle.bold())
                            .padding(.vertical)
                        TextField(loc("Name"), text: $name)
                        TextField(loc("Lottie JSON URL"), text: $url)
                        HStack {
                            Text(loc("Speed"))
                            Spacer(minLength: 80)
                            Text("\(speed, specifier: "%.1f")s")
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(.secondary)
                            Slider(value: $speed, in: 0...2, step: 0.1)
                        }
                        .padding(.vertical)
                        HStack {
                            Button {
                                isPresented.toggle()
                            } label: {
                                Text(loc("Cancel"))
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }

                            Button {
                                let visualizer: CustomVisualizer = .init(
                                    UUID: UUID(),
                                    name: name,
                                    url: URL(string: url)!,
                                    speed: speed
                                )

                                if !customVisualizers.contains(visualizer) {
                                    customVisualizers.append(visualizer)
                                }

                                isPresented.toggle()
                            } label: {
                                Text(loc("Add"))
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                            .buttonStyle(BorderedProminentButtonStyle())
                        }
                    }
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .controlSize(.extraLarge)
                    .padding()
                }
            } header: {
                HStack(spacing: 0) {
                    Text(loc("Custom vizualizers (Lottie)"))
                    if !Defaults[.customVisualizers].isEmpty {
                        Text(" – \(Defaults[.customVisualizers].count)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .accentColor(.effectiveAccent)
    }
}

struct Advanced: View {
    @Environment(\.settingsHighlightedId) private var highlightedId
    @Default(.useCustomAccentColor) var useCustomAccentColor
    @Default(.customAccentColorData) var customAccentColorData
    @Default(.showOnLockScreen) var showOnLockScreen
    @Default(.hideFromScreenRecording) var hideFromScreenRecording
    
    @State private var customAccentColor: Color = .accentColor
    @State private var selectedPresetColor: PresetAccentColor? = nil
    let icons: [String] = ["logo2"]
    @State private var selectedIcon: String = "logo2"
    
    // macOS accent colors
    enum PresetAccentColor: String, CaseIterable, Identifiable {
        case blue = "Blue"
        case purple = "Purple"
        case pink = "Pink"
        case red = "Red"
        case orange = "Orange"
        case yellow = "Yellow"
        case green = "Green"
        case graphite = "Graphite"
        
        var id: String { self.rawValue }
        
        var color: Color {
            switch self {
            case .blue: return .blue
            case .purple: return .purple
            case .pink: return .pink
            case .red: return .red
            case .orange: return .orange
            case .yellow: return .yellow
            case .green: return .green
            case .graphite: return .gray
            }
        }
    }
    
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    // Toggle between system and custom
                    Picker(loc("Accent color"), selection: $useCustomAccentColor) {
                        Text(loc("System")).tag(false)
                        Text(loc("Custom")).tag(true)
                    }
                    .pickerStyle(.segmented)
                    
                    if !useCustomAccentColor {
                        // System accent info
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 12) {
                                AccentCircleButton(
                                    isSelected: true,
                                    color: .accentColor,
                                    isSystemDefault: true
                                ) {}
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(loc("Using System Accent"))
                                        .font(.body)
                                    Text(loc("Your macOS system accent color"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                    } else {
                        // Custom color options
                        VStack(alignment: .leading, spacing: 12) {
                            Text(loc("Color Presets"))
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                            
                            HStack(spacing: 12) {
                                ForEach(PresetAccentColor.allCases) { preset in
                                    AccentCircleButton(
                                        isSelected: selectedPresetColor == preset,
                                        color: preset.color,
                                        isMulticolor: false
                                    ) {
                                        selectedPresetColor = preset
                                        customAccentColor = preset.color
                                        saveCustomColor(preset.color)
                                        forceUiUpdate()
                                    }
                                }
                                Spacer()
                            }
                            
                            Divider()
                                .padding(.vertical, 4)
                            
                            // Custom color picker
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(loc("Pick a Color"))
                                        .font(.body)
                                    Text(loc("Choose any color"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                                
                                ColorPicker(selection: Binding(
                                    get: { customAccentColor },
                                    set: { newColor in
                                        customAccentColor = newColor
                                        selectedPresetColor = nil
                                        saveCustomColor(newColor)
                                        forceUiUpdate()
                                    }
                                ), supportsOpacity: false) {
                                    ZStack {
                                        Circle()
                                            .fill(customAccentColor)
                                            .frame(width: 32, height: 32)
                                        
                                        if selectedPresetColor == nil {
                                            Circle()
                                                .strokeBorder(.primary.opacity(0.3), lineWidth: 2)
                                                .frame(width: 32, height: 32)
                                        }
                                    }
                                }
                                .labelsHidden()
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text(loc("Accent color"))
            } footer: {
                Text(loc("Choose between your system accent color or customize it with your own selection."))
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .id("advanced_accent")
            .searchHighlight(highlightedId == "advanced_accent")
            .onAppear {
                initializeAccentColorState()
            }
            
            Section {
                Defaults.Toggle(key: .cornerRadiusScaling) {
                    Text(loc("Corner radius scaling"))
                }
            } header: {
                Text(loc("Window Appearance"))
            }
            .id("advanced_appearance")
            .searchHighlight(highlightedId == "advanced_appearance")
            
            Section {
                HStack {
                    ForEach(icons, id: \.self) { icon in
                        Spacer()
                        VStack {
                            Image(icon)
                                .resizable()
                                .frame(width: 80, height: 80)
                                .background(
                                    RoundedRectangle(cornerRadius: 20, style: .circular)
                                        .strokeBorder(
                                             icon == selectedIcon ? Color.effectiveAccent : .clear,
                                              lineWidth: 2.5
                                        )
                                )

                            Text(loc("Default"))
                                .fontWeight(.medium)
                                .font(.caption)
                                .foregroundStyle(icon == selectedIcon ? .white : .secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .fill(icon == selectedIcon ? Color.effectiveAccent : .clear)
                                )
                        }
                        .onTapGesture {
                            withAnimation {
                                selectedIcon = icon
                            }
                            NSApp.applicationIconImage = NSImage(named: icon)
                        }
                        Spacer()
                    }
                }
                .disabled(true)
            } header: {
                HStack {
                    Text(loc("App icon"))
                    customBadge(text: loc("Coming soon"))
                }
            }
            .id("advanced_icon")
            .searchHighlight(highlightedId == "advanced_icon")
            
            Section {
                Defaults.Toggle(key: .hideTitleBar) {
                    Text(loc("Hide title bar"))
                }
                Defaults.Toggle(key: .showOnLockScreen) {
                    Text(loc("Show notch on lock screen"))
                }
                Defaults.Toggle(key: .hideFromScreenRecording) {
                    Text(loc("Hide from screen recording"))
                }
            } header: {
                Text(loc("Window Behavior"))
            }
            .id("advanced_behavior")
            .searchHighlight(highlightedId == "advanced_behavior")
        }
        .accentColor(.effectiveAccent)
        .onAppear {
            loadCustomColor()
        }
    }
    
    private func forceUiUpdate() {
        // Force refresh the UI
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Notification.Name("AccentColorChanged"), object: nil)
        }
    }
    
    private func saveCustomColor(_ color: Color) {
        let nsColor = NSColor(color)
        if let colorData = try? NSKeyedArchiver.archivedData(withRootObject: nsColor, requiringSecureCoding: false) {
            Defaults[.customAccentColorData] = colorData
            forceUiUpdate()
        }
    }
    
    private func loadCustomColor() {
        if let colorData = Defaults[.customAccentColorData],
           let nsColor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: colorData) {
            customAccentColor = Color(nsColor: nsColor)
            
            // Check if loaded color matches a preset
            selectedPresetColor = nil
            for preset in PresetAccentColor.allCases {
                if colorsAreEqual(Color(nsColor: nsColor), preset.color) {
                    selectedPresetColor = preset
                    break
                }
            }
        }
    }
    
    private func colorsAreEqual(_ color1: Color, _ color2: Color) -> Bool {
        let nsColor1 = NSColor(color1).usingColorSpace(.sRGB) ?? NSColor(color1)
        let nsColor2 = NSColor(color2).usingColorSpace(.sRGB) ?? NSColor(color2)
        
        return abs(nsColor1.redComponent - nsColor2.redComponent) < 0.01 &&
               abs(nsColor1.greenComponent - nsColor2.greenComponent) < 0.01 &&
               abs(nsColor1.blueComponent - nsColor2.blueComponent) < 0.01
    }
    
    private func initializeAccentColorState() {
        if !useCustomAccentColor {
            selectedPresetColor = nil // Multicolor is selected when useCustomAccentColor is false
        } else {
            loadCustomColor()
        }
    }
}

// MARK: - Accent Circle Button Component
struct AccentCircleButton: View {
    let isSelected: Bool
    let color: Color
    var isSystemDefault: Bool = false
    var isMulticolor: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                // Color circle
                Circle()
                    .fill(color)
                    .frame(width: 32, height: 32)
                
                // Subtle border
                Circle()
                    .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                    .frame(width: 32, height: 32)
                
                // Apple-style highlight ring around the middle when selected
                if isSelected {
                    Circle()
                        .strokeBorder(
                            Color.white.opacity(0.5),
                            lineWidth: 2
                        )
                        .frame(width: 28, height: 28)
                }
            }
        }
        .buttonStyle(.plain)
        .help(isSystemDefault ? loc("Your macOS system accent color") : "")
    }
}

struct ClipboardSettingsView: View {
    @Environment(\.settingsHighlightedId) private var highlightedId
    @ObservedObject var clipboardManager = ClipboardManager.shared
    @Default(.enableClipboardManager) var enableClipboardManager
    @Default(.clipboardMaxItems) var clipboardMaxItems

    var body: some View {
        Form {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc("Enable Clipboard Manager"))
                            .font(.headline)
                        Text(loc("Keep track of your recent text and image clips to easily re-copy them from the Notch."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 40)
                    Defaults.Toggle("", key: .enableClipboardManager)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.large)
                }
            }
            .id("clipboard_general")
            .searchHighlight(highlightedId == "clipboard_general")

            if enableClipboardManager {
                Section {
                    Stepper(loc("History limit: %lld items", clipboardMaxItems), value: $clipboardMaxItems, in: 5...50, step: 5)
                    
                    Button(loc("Clear clipboard history"), role: .destructive) {
                        clipboardManager.clearHistory()
                    }
                    .disabled(clipboardManager.history.isEmpty)
                } header: {
                    Text(loc("Clipboard History"))
                } footer: {
                    Text(loc("NotchPulse securely keeps track of your recent text and image clips. Tap any clip in the Notch clipboard tab to re-copy it instantly."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .id("clipboard_options")
                .searchHighlight(highlightedId == "clipboard_options")
            }
        }
        .accentColor(.effectiveAccent)
    }
}

struct AudioSettingsView: View {
    @Environment(\.settingsHighlightedId) private var highlightedId
    @Default(.enableAudioHub) var enableAudioHub
    @ObservedObject var audioManager = AudioDeviceManager.shared

    var body: some View {
        Form {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc("Enable Audio Hub"))
                            .font(.headline)
                        Text(loc("Manage audio devices, per-device volume & mute directly from the Notch."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 40)
                    Defaults.Toggle("", key: .enableAudioHub)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.large)
                }
            }
            .id("audio_hub")
            .searchHighlight(highlightedId == "audio_hub")

            if enableAudioHub {
                Section(header: Text(loc("Features"))) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(loc("Quick Device Switcher"))
                                    .font(.subheadline.weight(.medium))
                                Text(loc("Switch between speakers, headphones, and microphones with one click."))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(loc("Per-Device Volume & Mute"))
                                    .font(.subheadline.weight(.medium))
                                Text(loc("Adjust volume sliders and mute states independently for each connected audio device."))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .id("audio_routing")
                .searchHighlight(highlightedId == "audio_routing")
            }
        }
        .accentColor(.effectiveAccent)
    }
}

struct DisplaySettingsView: View {
    @Environment(\.settingsHighlightedId) private var highlightedId
    @Default(.enableDisplayHub) var enableDisplayHub
    @ObservedObject var brightnessManager = BrightnessManager.shared

    var body: some View {
        Form {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc("Enable Display Hub"))
                            .font(.headline)
                        Text(loc("Hardware DDC/CI brightness control for external monitors directly from the Notch."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 40)
                    Defaults.Toggle("", key: .enableDisplayHub)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.large)
                }
            }
            .id("display_hub")
            .searchHighlight(highlightedId == "display_hub")

            if enableDisplayHub {
                Section(header: Text(loc("Connected Displays")).id("display_monitors")) {
                    ForEach(brightnessManager.availableDisplays()) { target in
                        HStack {
                            Image(systemName: target.isBuiltin ? "laptopcomputer" : "display")
                                .foregroundStyle(.secondary)
                                .frame(width: 20)
                            Text(target.localizedName)
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Text(target.isBuiltin ? loc("Retina") : loc("Hardware DDC"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .id("display_monitors")
                .searchHighlight(highlightedId == "display_monitors")

                Section(header: Text(loc("Features")).id("display_features")) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "sun.max.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(loc("Hardware DDC/CI Control"))
                                    .font(.subheadline.weight(.medium))
                                Text(loc("Directly adjust backlight of third-party external monitors (Dell, LG, Asus, Samsung, HKC, etc.)."))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "slider.horizontal.below.rectangle")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(loc("Per-Display Brightness Sliders"))
                                    .font(.subheadline.weight(.medium))
                                Text(loc("Independent sliders with scroll-wheel fine-tuning and quick preset buttons."))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .id("display_features")
                .searchHighlight(highlightedId == "display_features")
            }
        }
        .accentColor(.effectiveAccent)
    }
}

struct Shortcuts: View {
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
            } header: {
                Text(loc("Notch"))
                    .id("shortcuts_notch")
            }
            .id("shortcuts_notch")
            .searchHighlight(highlightedId == "shortcuts_notch")
        }
        .accentColor(.effectiveAccent)
    }
}


func comingSoonTag() -> some View {
    Text(loc("Coming soon"))
        .foregroundStyle(.secondary)
        .font(.footnote.bold())
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(Color(nsColor: .secondarySystemFill))
        .clipShape(.capsule)
}

func customBadge(text: String) -> some View {
    Text(text)
        .foregroundStyle(.secondary)
        .font(.footnote.bold())
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(Color(nsColor: .secondarySystemFill))
        .clipShape(.capsule)
}

func warningBadge(_ text: String, _ description: String) -> some View {
    Section {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 22))
                .foregroundStyle(.yellow)
            VStack(alignment: .leading) {
                Text(text)
                    .font(.headline)
                Text(description)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

#Preview {
    HUD()
}


// MARK: - Language Settings View
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
    }
}

