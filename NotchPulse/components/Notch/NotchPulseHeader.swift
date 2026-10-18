import Defaults
import SwiftUI

struct NotchPulseHeader: View {
    @EnvironmentObject var vm: NotchPulseViewModel

    @ObservedObject var coordinator = NotchPulseViewCoordinator.shared
    @StateObject var tvm = ShelfStateViewModel.shared

    private var isDynamicIsland: Bool {
        Defaults[.notchStyle] == .dynamicIsland
    }

    private var headerInset: CGFloat {
        max(22, cornerRadiusInsets.opened.top + 4)
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack {
                if Defaults[.enableSystemMonitor] || Defaults[.notchPulseShelf] || coordinator.alwaysShowTabs {
                    TabSelectionView()
                }
            }
            .padding(.leading, headerInset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .zIndex(2)

            let activeScreen = NSScreen.screen(withUUID: vm.screenUUID ?? coordinator.selectedScreenUUID)
            let hasPhysicalNotch = (activeScreen?.safeAreaInsets.top ?? 0) > 0 || activeScreen?.auxiliaryTopLeftArea != nil
            if hasPhysicalNotch && !isDynamicIsland {
                Rectangle()
                    .fill(.black)
                    .frame(width: vm.closedNotchSize.width)
                    .mask {
                        NotchShape()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.interactiveSpring(response: 0.38, dampingFraction: 0.8, blendDuration: 0)) {
                            vm.close()
                        }
                    }
            } else {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: isDynamicIsland ? 120 : vm.closedNotchSize.width)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.interactiveSpring(response: 0.38, dampingFraction: 0.8, blendDuration: 0)) {
                            vm.close()
                        }
                    }
            }

            HStack(spacing: 6) {
                if isHUDType(coordinator.sneakPeek.type) && coordinator.sneakPeek.show && Defaults[.showOpenNotchHUD] {
                    OpenNotchHUD(type: $coordinator.sneakPeek.type, value: $coordinator.sneakPeek.value, icon: $coordinator.sneakPeek.icon)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                } else {
                    HStack(spacing: 6) {
                        if Defaults[.enableAudioHub] && Defaults[.showAudioHubInNotch] {
                            HeaderActionButton(
                                icon: "speaker.wave.2.fill",
                                isActive: coordinator.currentView == .audio
                            ) {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                    if coordinator.currentView == .audio {
                                        coordinator.currentView = .home
                                    } else {
                                        coordinator.currentView = .audio
                                    }
                                }
                            }
                        }
                        if Defaults[.showMirror] {
                            HeaderActionButton(
                                icon: "camera.fill",
                                isActive: vm.isCameraExpanded
                            ) {
                                vm.toggleCameraPreview()
                            }
                        }
                        if Defaults[.settingsIconInNotch] || FeatureTourController.shared.isTourActive {
                            HeaderActionButton(
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
            .padding(.trailing, headerInset)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .zIndex(2)
        }
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

/// Native frosted glass circular action button for the Notch header
struct HeaderActionButton: View {
    let icon: String
    var isActive: Bool = false
    var activeTint: Color? = nil
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    private var buttonFillColor: Color {
        if isActive {
            if let activeTint = activeTint {
                return activeTint
            }
            return colorScheme == .dark ? Color.white.opacity(0.24) : Color.black.opacity(0.14)
        }
        if isHovering {
            return colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.08)
        }
        return colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04)
    }

    private var buttonBorderColor: Color {
        if isActive {
            return colorScheme == .dark ? Color.white.opacity(0.35) : Color.black.opacity(0.20)
        }
        if isHovering {
            return colorScheme == .dark ? Color.white.opacity(0.25) : Color.black.opacity(0.12)
        }
        return colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.06)
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(buttonFillColor)

                Circle()
                    .strokeBorder(buttonBorderColor, lineWidth: 0.8)

                Image(systemName: icon)
                    .font(.system(size: 11, weight: isActive ? .semibold : .medium))
                    .foregroundStyle(isActive ? .primary : (isHovering ? .primary : .secondary))
            }
            .frame(width: 26, height: 26)
            .contentShape(Circle())
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            withAnimation(.smooth(duration: 0.2)) {
                isHovering = hovering
            }
        }
    }
}

#Preview {
    NotchPulseHeader().environmentObject(NotchPulseViewModel())
}
