//
//  SettingsView.swift
//  NotchPulse
//
//  NOTE: Tất cả mọi thứ mọi dòng hiển thị trong setting đều dùng tiếng anh (All labels, descriptions, and UI text in Settings MUST be in English).
//
//  Created by Richard Kunkli on 07/08/2024.
//

import AVFoundation
import Defaults
import EventKit
import KeyboardShortcuts
import LaunchAtLogin
import Sparkle
import SwiftUI
import SwiftUIIntrospect

struct SettingsView: View {
    @State private var selectedTab = "General"
    @State private var accentColorUpdateTrigger = UUID()
    @Default(.appLanguage) private var appLanguage

    let updaterController: SPUStandardUpdaterController?

    init(updaterController: SPUStandardUpdaterController? = nil) {
        self.updaterController = updaterController
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                NavigationLink(value: "General") {
                    Label(tabTitle(for: "General"), systemImage: "gear")
                }
                NavigationLink(value: "Appearance") {
                    Label(tabTitle(for: "Appearance"), systemImage: "paintbrush.fill")
                }
                NavigationLink(value: "Media") {
                    Label(tabTitle(for: "Media"), systemImage: "play.circle.fill")
                }
                NavigationLink(value: "Calendar") {
                    Label(tabTitle(for: "Calendar"), systemImage: "calendar")
                }
                NavigationLink(value: "HUD") {
                    Label(tabTitle(for: "HUD"), systemImage: "gauge.with.dots.needle.33percent")
                }
                NavigationLink(value: "SystemMonitor") {
                    Label(tabTitle(for: "SystemMonitor"), systemImage: "chart.bar.fill")
                }
                NavigationLink(value: "FaceID") {
                    Label(tabTitle(for: "FaceID"), systemImage: "faceid")
                }
//                NavigationLink(value: "Downloads") {
//                    Label(tabTitle(for: "Downloads"), systemImage: "square.and.arrow.down")
//                }
                NavigationLink(value: "Shelf") {
                    Label(tabTitle(for: "Shelf"), systemImage: "tray.fill")
                }
                NavigationLink(value: "Clipboard") {
                    Label(tabTitle(for: "Clipboard"), systemImage: "doc.on.clipboard.fill")
                }
                NavigationLink(value: "Shortcuts") {
                    Label(tabTitle(for: "Shortcuts"), systemImage: "command.square.fill")
                }
                // NavigationLink(value: "Extensions") {
                //     Label(tabTitle(for: "Extensions"), systemImage: "puzzlepiece.extension")
                // }
                NavigationLink(value: "Advanced") {
                    Label(tabTitle(for: "Advanced"), systemImage: "slider.horizontal.3")
                }
                NavigationLink(value: "Language") {
                    Label(tabTitle(for: "Language"), systemImage: "globe")
                }
                NavigationLink(value: "About") {
                    Label(tabTitle(for: "About"), systemImage: "info.circle.fill")
                }
            }
            .listStyle(SidebarListStyle())
            .tint(.effectiveAccent)
            .toolbar(removing: .sidebarToggle)
            .navigationSplitViewColumnWidth(200)
        } detail: {
            VStack(spacing: 0) {
                SettingsDetailHeaderBar(
                    title: tabTitle(for: selectedTab),
                    showQuitButton: true
                )

                ZStack(alignment: .top) {
                    Group {
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
                        case "Shortcuts":
                            Shortcuts()
                        case "Extensions":
                            GeneralSettings()
                        case "Advanced":
                            Advanced()
                        case "Language":
                            LanguageSettingsView()
                        case "About":
                            if let controller = updaterController {
                                About(updaterController: controller)
                            } else {
                                // Fallback with a default controller
                                About(
                                    updaterController: SPUStandardUpdaterController(
                                        startingUpdater: false, updaterDelegate: nil,
                                        userDriverDelegate: nil))
                            }
                        default:
                            GeneralSettings()
                        }
                    }
                    .hideScrollbar()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .mask {
                        VStack(spacing: 0) {
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0.0),
                                    .init(color: .black, location: 1.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 20)

                            Rectangle()
                                .fill(Color.black)
                        }
                    }
                    .clipped()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(edges: .top)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar(removing: .sidebarToggle)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("")
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 700)
        .applyGlassEffect()
        .tint(.effectiveAccent)
        .id("\(accentColorUpdateTrigger)-\(appLanguage.rawValue)")
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("AccentColorChanged"))) { _ in
            accentColorUpdateTrigger = UUID()
        }
    }

    private func tabTitle(for tab: String) -> String {
        L10n.tr(tab, lang: appLanguage)
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
                    .shadow(color: .black.opacity(0.35), radius: 4, x: 0, y: 2)
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
                Text("560 px (Compact)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Text("Live preview active on Notch")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("960 px (Extra Wide)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct GeneralSettings: View {
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
        NotificationCenter.default.post(name: .previewNotchWidth, object: width)
        
        autoClosePreviewTask?.cancel()
        if !isEditing {
            autoClosePreviewTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(3500))
                guard !Task.isCancelled else { return }
                NotificationCenter.default.post(name: .closeNotchPreview, object: nil)
            }
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
                    SpotlightTourManager.shared.showTour(useAppLanguage: true)
                }) {
                    HStack {
                        Image(systemName: "sparkles.tv.fill")
                            .foregroundColor(.white)
                            .font(.system(size: 16))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(loc("Interactive Spotlight Tour"))
                                .font(.system(size: 13, weight: .semibold))
                            Text(loc("Walk through interactive guides for Notch, Shelf, Music, Calendar & Settings"))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }

            styleSection
            dimensionsSection
            systemFeaturesSection
            notchSizingSection
            NotchBehaviour()
            gestureControls()
        }
        .scrollContentBackground(.hidden)
        .hideScrollbar()
        .accentColor(.effectiveAccent)
        .onChange(of: openNotchOnHover) {
            if !openNotchOnHover {
                enableGestures = true
            }
        }
    }

    @ViewBuilder
    func gestureControls() -> some View {
        Section {
            Defaults.Toggle(key: .enableGestures) {
                Text(loc("Enable gestures"))
            }
                .disabled(!openNotchOnHover)
            if enableGestures {
                Toggle(loc("Change media with horizontal gestures"), isOn: .constant(false))
                    .disabled(true)
                Defaults.Toggle(key: .closeGestureEnabled) {
                    Text(loc("Close gesture"))
                }
                Slider(value: $gestureSensitivity, in: 100...300, step: 100) {
                    HStack {
                        Text(loc("Gesture sensitivity"))
                        Spacer()
                        Text(
                            Defaults[.gestureSensitivity] == 100
                                ? loc("High") : Defaults[.gestureSensitivity] == 200 ? loc("Medium") : loc("Low")
                        )
                        .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            HStack {
                Text(loc("Gesture control"))
                customBadge(text: loc("Beta"))
            }
        } footer: {
            Text(
                loc("Two-finger swipe up on notch to close, two-finger swipe down on notch to open when **Open notch on hover** option is disabled")
            )
            .multilineTextAlignment(.trailing)
            .foregroundStyle(.secondary)
            .font(.caption)
        }
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
            
            Section {
                Picker(loc("Option key behaviour"), selection: $optionKeyAction) {
                    ForEach(OptionKeyAction.allCases) { opt in
                        Text(opt.rawValue).tag(opt)
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
            }
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
            }
            .disabled(!Defaults[.hudReplacement])
        }
        .scrollContentBackground(.hidden)
        .hideScrollbar()
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
    @Default(.enableSystemMonitor) var enableSystemMonitor
    @Default(.systemMonitorShowProcesses) var showProcesses
    @ObservedObject var monitor = SystemMonitorManager.shared

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

            Section {
                Defaults.Toggle(key: .systemMonitorShowProcesses) {
                    Text(loc("Show top resource-consuming processes"))
                }
            } header: {
                Text(loc("Display Options"))
            }
            .disabled(!enableSystemMonitor)

            Section {
                VStack(spacing: 12) {
                    HStack(spacing: 16) {
                        // Mini CPU
                        HStack(spacing: 8) {
                            Image(systemName: "cpu")
                                .foregroundStyle(.blue)
                            VStack(alignment: .leading) {
                                Text(loc("CPU"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(String(format: "%.0f%%", monitor.cpuTotal))
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Divider()

                        // Mini RAM
                        HStack(spacing: 8) {
                            Image(systemName: "memorychip")
                                .foregroundStyle(.green)
                            VStack(alignment: .leading) {
                                Text(loc("RAM"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(String(format: "%.1f / %.0f GB", monitor.ramUsedGB, monitor.ramTotalGB))
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                Text("\(loc("Swap")): \(monitor.swapUsedFormatted)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Divider()

                        // Mini GPU
                        HStack(spacing: 8) {
                            Image(systemName: "display")
                                .foregroundStyle(.purple)
                            VStack(alignment: .leading) {
                                Text(loc("GPU"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(String(format: "%.0f%%", monitor.gpuUsage))
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text(loc("Live Preview"))
            }
            .disabled(!enableSystemMonitor)
        }
        .scrollContentBackground(.hidden)
        .hideScrollbar()
        .accentColor(.effectiveAccent)
        .onAppear {
            monitor.startMonitoring()
        }
        .onDisappear {
            monitor.stopMonitoring()
        }
    }
}

struct Media: View {
    @Default(.waitInterval) var waitInterval
    @Default(.mediaController) var mediaController
    @ObservedObject var coordinator = NotchPulseViewCoordinator.shared
    @Default(.hideNotchOption) var hideNotchOption
    @Default(.enableSneakPeek) private var enableSneakPeek
    @Default(.sneakPeekStyles) var sneakPeekStyles

    @Default(.enableLyrics) var enableLyrics
    @State private var isSyncing: Bool = false
    @State private var isMusicSyncConfirmed: Bool = MediaAutomationPermissionHelper.isSyncConfirmed()

    var body: some View {
        Form {
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
            
            Section {
                Toggle(
                    loc("Show music live activity"),
                    isOn: $coordinator.musicLiveActivityEnabled.animation()
                )
                Toggle(loc("Show sneak peek on playback changes"), isOn: $enableSneakPeek)
                Picker(loc("Sneak Peek Style"), selection: $sneakPeekStyles) {
                    ForEach(SneakPeekStyle.allCases) { style in
                        Text(style.rawValue).tag(style)
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
            }
            
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
            }  footer: {
                Text(loc("Customize which controls appear in the music player. Grant automation access for Spotify and Apple Music to keep playback and lyrics precisely in sync."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            isMusicSyncConfirmed = MediaAutomationPermissionHelper.isSyncConfirmed()
        }
        .scrollContentBackground(.hidden)
        .hideScrollbar()
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
            Defaults.Toggle(key: .showCalendar) {
                Text(loc("Show calendar"))
            }
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

            Section(header: Text(loc("Lunar Calendar Region"))) {
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
        .scrollContentBackground(.hidden)
        .hideScrollbar()
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
    @State private var showBuildNumber: Bool = false
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

                UpdaterSettingsView(updater: updaterController.updater)

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
            .scrollContentBackground(.hidden)
            .hideScrollbar()
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
    @Default(.shelfTapToOpen) var shelfTapToOpen: Bool
    @Default(.quickShareProvider) var quickShareProvider
    @Default(.shakeAutoCloseDelay) var shakeAutoCloseDelay
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
                Defaults.Toggle(key: .notchPulseShelf) {
                    Text(loc("Enable shelf"))
                }
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
                        Text(loc("Auto-close delay after shake"))
                        Spacer()
                        Text("\(Int(shakeAutoCloseDelay))s")
                            .foregroundStyle(.secondary)
                    }
                }
                Text(loc("When shaking to open the shelf while dragging a file, it will automatically close after this duration if you do not drop the file into the shelf."))
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
                            .foregroundColor(.accentColor)
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
                        .foregroundColor(.accentColor)
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
        }
        .scrollContentBackground(.hidden)
        .hideScrollbar()
        .accentColor(.effectiveAccent)
    }
}

struct Appearance: View {
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
            }

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
                        Text(option.rawValue)
                    }
                }
            } header: {
                Text(loc("Media"))
            }

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
            }

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
                Defaults.Toggle(key: .showNotHumanFace) {
                    Text(loc("Show cool face animation while inactive"))
                }
            } header: {
                HStack {
                    Text(loc("Additional features"))
                }
            }
        }
        .accentColor(.effectiveAccent)
    }

    func checkVideoInput() -> Bool {
        if AVCaptureDevice.default(for: .video) != nil {
            return true
        }

        return false
    }
}

struct Advanced: View {
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
            case .blue: return Color(red: 0.0, green: 0.478, blue: 1.0)
            case .purple: return Color(red: 0.686, green: 0.322, blue: 0.871)
            case .pink: return Color(red: 1.0, green: 0.176, blue: 0.333)
            case .red: return Color(red: 1.0, green: 0.271, blue: 0.227)
            case .orange: return Color(red: 1.0, green: 0.584, blue: 0.0)
            case .yellow: return Color(red: 1.0, green: 0.8, blue: 0.0)
            case .green: return Color(red: 0.4, green: 0.824, blue: 0.176)
            case .graphite: return Color(red: 0.557, green: 0.557, blue: 0.576)
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
            .onAppear {
                initializeAccentColorState()
            }
            
            Section {
                Defaults.Toggle(key: .enableShadow) {
                    Text(loc("Enable window shadow"))
                }
                Defaults.Toggle(key: .cornerRadiusScaling) {
                    Text(loc("Corner radius scaling"))
                }
            } header: {
                Text(loc("Window Appearance"))
            }
            
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
        }
        .scrollContentBackground(.hidden)
        .hideScrollbar()
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
    @ObservedObject var clipboardManager = ClipboardManager.shared
    @Default(.enableClipboardManager) var enableClipboardManager
    @Default(.clipboardMaxItems) var clipboardMaxItems

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .enableClipboardManager) {
                    Text(loc("Enable Clipboard Manager"))
                }

                if enableClipboardManager {
                    Stepper(loc("History limit: %lld items", clipboardMaxItems), value: $clipboardMaxItems, in: 5...50, step: 5)
                    
                    Button(loc("Clear clipboard history"), role: .destructive) {
                        clipboardManager.clearHistory()
                    }
                    .disabled(clipboardManager.history.isEmpty)
                }
            } header: {
                Text(loc("Clipboard History"))
            } footer: {
                Text(loc("NotchPulse securely keeps track of your recent text and image clips. Tap any clip in the Notch clipboard tab to re-copy it instantly."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .hideScrollbar()
        .accentColor(.effectiveAccent)
    }
}

struct Shortcuts: View {
    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder(loc("Toggle Sneak Peek:"), name: .toggleSneakPeek)
            } header: {
                Text(loc("Media"))
            } footer: {
                Text(
                    loc("Sneak Peek shows the media title and artist under the notch for a few seconds.")
                )
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.secondary)
                .font(.caption)
            }
            Section {
                KeyboardShortcuts.Recorder(loc("Toggle Notch Open:"), name: .toggleNotchOpen)
            }
        }
        .scrollContentBackground(.hidden)
        .hideScrollbar()
        .accentColor(.effectiveAccent)
    }
}

func proFeatureBadge() -> some View {
    Text(loc("Upgrade to Pro"))
        .foregroundStyle(Color(red: 0.545, green: 0.196, blue: 0.98))
        .font(.footnote.bold())
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 4).stroke(
                Color(red: 0.545, green: 0.196, blue: 0.98), lineWidth: 1))
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

extension View {
    @ViewBuilder
    func applyGlassEffect() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background {
                FaceIDVisualEffectView(material: .sidebar, blendingMode: .behindWindow)
                    .ignoresSafeArea()
            }
    }
}

/// Dedicated top header bar displayed across all settings tabs in the detail column.
/// Provides an Apple-standard frosted glass backdrop and divider so scrolling content
/// disappears cleanly behind it rather than colliding with title text.
struct SettingsDetailHeaderBar: View {
    let title: String
    var showQuitButton: Bool = false
    @Default(.appLanguage) private var appLanguage

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color.primary)
                .lineLimit(1)

            Spacer()

            if showQuitButton {
                Button {
                    if let appDelegate = NSApp.delegate as? AppDelegate {
                        appDelegate.isUserInitiatedQuit = true
                        appDelegate.quitApplication()
                    } else if let appDelegate = AppDelegate.shared {
                        appDelegate.isUserInitiatedQuit = true
                        appDelegate.quitApplication()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "power")
                        Text(loc("Quit app"))
                    }
                    .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .frame(minHeight: 52)
        .background {
            Color(nsColor: .windowBackgroundColor)
        }
        .zIndex(100)
    }
}

// MARK: - Language Settings View
struct LanguageSettingsView: View {
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
        }
        .formStyle(.grouped)
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 24)
    }
}

extension View {
    fileprivate func hideScrollbar() -> some View {
        self.introspect(.scrollView, on: .macOS(.v12, .v13, .v14, .v15)) { (scrollView: NSScrollView) in
            scrollView.hasVerticalScroller = false
            scrollView.hasHorizontalScroller = false
            scrollView.autohidesScrollers = true
        }
    }
}

