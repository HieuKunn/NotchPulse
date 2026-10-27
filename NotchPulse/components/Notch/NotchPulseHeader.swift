import Defaults
import SwiftUI

struct NotchPulseHeader: View {
    @EnvironmentObject var vm: NotchPulseViewModel

    @ObservedObject var coordinator = NotchPulseViewCoordinator.shared
    @StateObject var tvm = ShelfStateViewModel.shared

    @Default(.enableAudioHub) var enableAudioHub
    @Default(.showAudioHubInNotch) var showAudioHubInNotch
    @Default(.enableDisplayHub) var enableDisplayHub
    @Default(.showMirror) var showMirror
    @Default(.settingsIconInNotch) var settingsIconInNotch

    private var isDynamicIsland: Bool {
        Defaults[.notchStyle] == .dynamicIsland
    }

    private var headerInset: CGFloat {
        isDynamicIsland ? 16 : max(16, cornerRadiusInsets.opened.top - 2)
    }

    private var topPadding: CGFloat {
        isDynamicIsland ? 3 : 0
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack {
                if Defaults[.enableSystemMonitor] || Defaults[.notchPulseShelf] || coordinator.alwaysShowTabs {
                    TabSelectionView()
                }
            }
            .padding(.leading, isDynamicIsland ? headerInset : (headerInset + cornerRadiusInsets.opened.top))
            .frame(maxWidth: .infinity, alignment: .leading)
            .zIndex(2)

            Rectangle()
                .fill(isDynamicIsland ? Color.clear : Color.black)
                .frame(width: isDynamicIsland ? 120 : vm.closedNotchSize.width)
                .conditionalModifier(!isDynamicIsland) { view in
                    view.mask { NotchShape() }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.interactiveSpring(response: 0.38, dampingFraction: 0.8, blendDuration: 0)) {
                        ShelfStateViewModel.shared.isPinned = false
                        CalendarStateViewModel.shared.isPinned = false
                        vm.close()
                    }
                }

            HStack(spacing: 6) {
                if isHUDType(coordinator.sneakPeek.type) && coordinator.sneakPeek.show && Defaults[.showOpenNotchHUD] {
                    OpenNotchHUD(type: $coordinator.sneakPeek.type, value: $coordinator.sneakPeek.value, icon: $coordinator.sneakPeek.icon)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                } else {
                    HStack(spacing: 6) {
                        if enableAudioHub && showAudioHubInNotch {
                            HeaderGlassIconButton(
                                icon: "speaker.wave.2.fill",
                                isActive: coordinator.currentView == .audio
                            ) {
                                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                    if coordinator.currentView == .audio {
                                        coordinator.currentView = .home
                                        vm.customOpenHeight = nil
                                    } else {
                                        AudioDeviceManager.shared.refreshDevices()
                                        vm.customOpenHeight = AudioHubNotchView.calculateHeight(selectedTab: AudioDeviceManager.shared.selectedTab)
                                        coordinator.currentView = .audio
                                    }
                                }
                            }
                        }
                        if enableDisplayHub {
                            HeaderGlassIconButton(
                                icon: "sun.max.fill",
                                isActive: coordinator.currentView == .display
                            ) {
                                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                    if coordinator.currentView == .display {
                                        coordinator.currentView = .home
                                        vm.customOpenHeight = nil
                                    } else {
                                        BrightnessManager.shared.refreshAllDisplays()
                                        vm.customOpenHeight = DisplayHubNotchView.calculateHeight()
                                        coordinator.currentView = .display
                                    }
                                }
                            }
                        }
                        if showMirror {
                            HeaderGlassIconButton(
                                icon: "camera.fill",
                                isActive: vm.isCameraExpanded
                            ) {
                                vm.toggleCameraPreview()
                            }
                        }
                        if settingsIconInNotch || FeatureTourController.shared.isTourActive {
                            HeaderGlassIconButton(
                                icon: "gearshape.fill",
                                isActive: false
                            ) {
                                DispatchQueue.main.async {
                                    SettingsWindowController.shared.showWindow()
                                }
                            }
                            .background(
                                ScreenFrameReader { frame in
                                    FeatureTourController.shared.settingsGearScreenRect = frame
                                }
                            )
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
            .animation(.smooth(duration: 0.22), value: coordinator.sneakPeek.show)
            .font(.system(.headline, design: .rounded))
            .padding(.trailing, isDynamicIsland ? headerInset : (headerInset + cornerRadiusInsets.opened.top))
            .frame(maxWidth: .infinity, alignment: .trailing)
            .zIndex(2)
        }
        .padding(.top, topPadding)
        .foregroundColor(.gray)
        .environmentObject(vm)
    }

    func isHUDType(_ type: SneakContentType) -> Bool {
        switch type {
        case .volume, .brightness, .backlight, .mic, .battery:
            return true
        default:
            return false
        }
    }
}

// MARK: - Native Header Glass Icon Button
struct HeaderGlassIconButton: View {
    let icon: String
    var isActive: Bool = false
    var action: () -> Void
    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(
                        isActive
                            ? Color.white.opacity(0.24)
                            : (isHovered ? Color.white.opacity(0.12) : Color.white.opacity(0.06))
                    )
                    .frame(width: 28, height: 28)

                Circle()
                    .stroke(
                        isActive ? Color.white.opacity(0.30) : Color.white.opacity(0.08),
                        lineWidth: 0.5
                    )
                    .frame(width: 28, height: 28)

                Image(systemName: icon)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(
                        isActive ? Color.white : (isHovered ? Color.primary : Color.secondary)
                    )
                    .imageScale(.medium)
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.smooth(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
}

#Preview {
    NotchPulseHeader().environmentObject(NotchPulseViewModel())
}
