import AVFoundation
import AppKit
import Defaults
import Sparkle
import SwiftUI

// MARK: - Settings Destination Enum

enum SettingsDestination: String, CaseIterable, Identifiable {
    case general = "General"
    case appearance = "Appearance"
    case media = "Media"
    case shelf = "Shelf"
    case clipboard = "Clipboard"
    case calendar = "Calendar"
    case shortcuts = "Shortcuts"
    case hud = "HUD"
    case display = "Display"
    case audio = "Audio"
    case systemMonitor = "SystemMonitor"
    case faceID = "FaceID"
    case permissions = "Permissions"
    case advanced = "Advanced"
    case language = "Language"
    case about = "About"

    var id: String { rawValue }
}

struct SettingsSidebarCategory: Identifiable {
    let id: String
    let title: String
    let tabs: [SettingsTabItem]
}

// MARK: - Main Settings View

struct SettingsView: View {
    @State private var selectedTab: SettingsDestination = .general
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var searchText = ""
    @State private var isSearchActive = false
    @State private var accentColorUpdateTrigger = UUID()
    @State private var scrollToItemId: String? = nil
    @State private var highlightedItemId: String? = nil
    @State private var scrollTrigger = UUID()
    @Default(.appLanguage) private var appLanguage

    let updaterController: SPUStandardUpdaterController?

    private let allTabs: [SettingsTabItem] = [
        SettingsTabItem(
            id: .general,
            icon: "gearshape",
            badgeColor: Color(nsColor: .systemGray),
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
                    keywords: ["System features", "Show menu bar icon", "Launch at login", "Preload expanded notch after launch", "Show on all displays", "Preferred display", "Automatically switch displays", "Khởi động cùng hệ thống"]
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
            id: .appearance,
            icon: "paintbrush",
            badgeColor: Color(nsColor: .systemIndigo),
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
            id: .media,
            icon: "play",
            badgeColor: Color.pink,
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
            id: .shelf,
            icon: "tray",
            badgeColor: Color.indigo,
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
            id: .clipboard,
            icon: "doc.on.clipboard",
            badgeColor: Color.teal,
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
            id: .calendar,
            icon: "calendar",
            badgeColor: Color.red,
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
            id: .shortcuts,
            icon: "command",
            badgeColor: Color.purple,
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
            id: .hud,
            icon: "gauge.with.dots.needle.33percent",
            badgeColor: Color.orange,
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
            id: .display,
            icon: "sun.max",
            badgeColor: Color.blue,
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
            id: .audio,
            icon: "speaker.wave.2",
            badgeColor: Color.red,
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
            id: .systemMonitor,
            icon: "chart.bar",
            badgeColor: Color.green,
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
            id: .faceID,
            icon: "faceid",
            badgeColor: Color.blue,
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
            id: .permissions,
            icon: "lock.shield",
            badgeColor: Color(nsColor: .systemBlue),
            sections: [
                SettingsSectionItem(
                    id: "permissions_overview",
                    title: "Privacy & Permissions",
                    keywords: ["Privacy", "Permissions", "Camera", "Accessibility", "Calendar", "Reminders", "Automation", "Quyền riêng tư"]
                ),
                SettingsSectionItem(
                    id: "permissions_features",
                    title: "Feature Permissions",
                    keywords: ["Camera", "Accessibility", "Calendar", "Reminders", "Music", "Automation", "Cấp quyền"]
                ),
                SettingsSectionItem(
                    id: "permissions_unneeded",
                    title: "Unneeded Permissions",
                    keywords: ["Screen Recording", "Full Disk Access", "Quyền không cần thiết"]
                )
            ]
        ),
        SettingsTabItem(
            id: .advanced,
            icon: "slider.horizontal.3",
            badgeColor: Color.gray,
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
            id: .language,
            icon: "globe",
            badgeColor: Color.blue,
            sections: [
                SettingsSectionItem(
                    id: "language_display",
                    title: "App Language",
                    keywords: ["App Language", "Language", "Ngôn ngữ", "Tiếng Việt", "English", "Deutsch", "Français", "Español", "日本語", "简体中文"]
                )
            ]
        ),
        SettingsTabItem(
            id: .about,
            icon: "info.circle",
            badgeColor: Color.gray,
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

    private var categorizedSections: [SettingsSidebarCategory] {
        let tabMap = Dictionary(uniqueKeysWithValues: allTabs.map { ($0.id, $0) })

        func getTabs(_ destinations: [SettingsDestination]) -> [SettingsTabItem] {
            destinations.compactMap { tabMap[$0] }
        }

        return [
            SettingsSidebarCategory(
                id: "general_category",
                title: loc("General"),
                tabs: getTabs([.general, .appearance])
            ),
            SettingsSidebarCategory(
                id: "notch_media_category",
                title: loc("Notch & Media"),
                tabs: getTabs([.media, .shelf, .clipboard])
            ),
            SettingsSidebarCategory(
                id: "productivity_category",
                title: loc("Productivity"),
                tabs: getTabs([.calendar, .shortcuts])
            ),
            SettingsSidebarCategory(
                id: "hardware_system_category",
                title: loc("Hardware & System"),
                tabs: getTabs([.hud, .display, .audio, .systemMonitor])
            ),
            SettingsSidebarCategory(
                id: "security_permissions_category",
                title: loc("Security & Permissions"),
                tabs: getTabs([.faceID, .permissions])
            ),
            SettingsSidebarCategory(
                id: "app_category",
                title: loc("App"),
                tabs: getTabs([.advanced, .language, .about])
            )
        ]
    }

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

    private func selectSearchItem(destination: SettingsDestination, sectionId: String) {
        selectTab(destination)
        scrollToItemId = sectionId
        highlightedItemId = sectionId
        scrollTrigger = UUID()

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1800))
            withAnimation(.easeOut(duration: 0.4)) {
                if highlightedItemId == sectionId {
                    highlightedItemId = nil
                }
            }
        }
    }

    private func selectTab(_ destination: SettingsDestination) {
        selectedTab = destination
    }

    init(updaterController: SPUStandardUpdaterController? = nil) {
        self.updaterController = updaterController
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            settingsSidebar
        } detail: {
            settingsDetail
        }
        .navigationSplitViewStyle(.balanced)
        .formStyle(.grouped)
        .toggleStyle(.switch)
        .frame(minWidth: 720, minHeight: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    let next: NavigationSplitViewVisibility = (columnVisibility == .detailOnly) ? .all : .detailOnly
                    if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                        columnVisibility = next
                    } else {
                        withAnimation { columnVisibility = next }
                    }
                } label: {
                    Label(
                        columnVisibility == .detailOnly ? loc("Show Sidebar") : loc("Hide Sidebar"),
                        systemImage: "sidebar.left"
                    )
                }
                .keyboardShortcut("s", modifiers: [.control, .command])
                .help(columnVisibility == .detailOnly ? loc("Show Sidebar") : loc("Hide Sidebar"))
            }
        }
        .id("\(accentColorUpdateTrigger)-\(appLanguage.rawValue)")
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("AccentColorChanged"))) { _ in
            accentColorUpdateTrigger = UUID()
        }
    }

    @ViewBuilder
    private var settingsSidebar: some View {
        SettingsSidebarListView(
            selectedTab: $selectedTab,
            searchText: $searchText,
            isPresented: $isSearchActive,
            filteredTabs: filteredTabs,
            categories: categorizedSections,
            matchingSections: matchingSections(for:),
            tabTitle: tabTitle(for:),
            selectTab: selectTab
        )
        .searchable(
            text: $searchText,
            isPresented: $isSearchActive,
            placement: .sidebar,
            prompt: loc("Search Settings...")
        )
        .navigationSplitViewColumnWidth(240)
    }

    @ViewBuilder
    private var settingsDetail: some View {
        ScrollViewReader { proxy in
            detailContent
                .environment(\.settingsHighlightedId, highlightedItemId)
                .formStyle(.grouped)
                .scrollIndicators(.hidden)
                .safeAreaInset(edge: .top, spacing: 0) {
                    SettingsDetailHeaderBar(
                        title: tabTitle(for: selectedTab)
                    )
                    .zIndex(1)
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

    @ViewBuilder
    private var detailContent: some View {
        switch selectedTab {
        case .general:
            GeneralSettingsView()
        case .appearance:
            AppearanceSettingsView()
        case .media:
            MediaSettingsView()
        case .calendar:
            CalendarSettingsView()
        case .hud:
            HUDSettingsView()
        case .systemMonitor:
            SystemMonitorSettingsView()
        case .faceID:
            FaceIDSettingsView()
        case .permissions:
            PermissionsSettingsView()
        case .shelf:
            ShelfSettingsView()
        case .clipboard:
            ClipboardSettingsView()
        case .audio:
            AudioSettingsView()
        case .display:
            DisplaySettingsView()
        case .shortcuts:
            ShortcutsSettingsView()
        case .advanced:
            AdvancedSettingsView()
        case .language:
            LanguageSettingsView()
        case .about:
            let controller = updaterController ?? SettingsWindowController.shared.updaterController
            if let controller = controller {
                AboutSettingsView(updaterController: controller)
            } else {
                AboutSettingsView(
                    updaterController: SPUStandardUpdaterController(
                        startingUpdater: false,
                        updaterDelegate: AppUpdaterDelegate.shared,
                        userDriverDelegate: AppUpdaterDelegate.shared))
            }
        }
    }

    private func tabTitle(for destination: SettingsDestination) -> String {
        L10n.tr(destination.rawValue, lang: appLanguage)
    }
}

// MARK: - Sidebar List with Categorized Sections & Search

private struct SettingsSidebarListView: View {
    @Environment(\.isSearching) private var isSearching
    @Binding var selectedTab: SettingsDestination
    @Binding var searchText: String
    @Binding var isPresented: Bool
    let filteredTabs: [SettingsTabItem]
    let categories: [SettingsSidebarCategory]
    let matchingSections: (SettingsTabItem) -> [SettingsSectionItem]
    let tabTitle: (SettingsDestination) -> String
    let selectTab: (SettingsDestination) -> Void

    @State private var searchSelection: SettingsDestination? = nil

    private var activeSelection: Binding<SettingsDestination?> {
        Binding(
            get: {
                if isSearching || isPresented || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return searchSelection
                }
                return selectedTab
            },
            set: { newValue in
                guard let newValue else { return }
                selectTab(newValue)
                if isSearching || isPresented || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    searchSelection = newValue
                }
            }
        )
    }

    private var isSearchFilterActive: Bool {
        isSearching || isPresented || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        List(selection: activeSelection) {
            if isSearchFilterActive {
                if filteredTabs.isEmpty {
                    ContentUnavailableView {
                        Label(loc("No settings found"), systemImage: "magnifyingglass")
                    }
                } else {
                    ForEach(filteredTabs) { tab in
                        sidebarRow(for: tab)
                    }
                }
            } else {
                ForEach(categories) { category in
                    Section(header: Text(category.title)) {
                        ForEach(category.tabs) { tab in
                            sidebarRow(for: tab)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollIndicators(.hidden)
        .onChange(of: isSearching) { _, newVal in
            if !newVal { searchSelection = nil }
        }
        .onChange(of: isPresented) { _, newVal in
            if !newVal { searchSelection = nil }
        }
    }

    @ViewBuilder
    private func sidebarRow(for tab: SettingsTabItem) -> some View {
        let matches = matchingSections(tab)
        let isRowSelected = (activeSelection.wrappedValue == tab.id)

        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(tabTitle(tab.id))

                if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !matches.isEmpty {
                    Text(matches.map { loc($0.title) }.joined(separator: " • "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        } icon: {
            Image(systemName: tab.icon)
                .font(.body.weight(.medium))
                .foregroundStyle(isRowSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.tint))
                .frame(width: 20, height: 20, alignment: .center)
        }
        .tag(tab.id)
    }
}
