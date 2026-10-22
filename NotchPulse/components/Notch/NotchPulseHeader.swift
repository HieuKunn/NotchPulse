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
                        if Defaults[.enableAudioHub] && Defaults[.showAudioHubInNotch] {
                            Button(action: {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                    if coordinator.currentView == .audio {
                                        coordinator.currentView = .home
                                    } else {
                                        coordinator.currentView = .audio
                                    }
                                }
                            }) {
                                Capsule()
                                    .fill(coordinator.currentView == .audio ? Color.white.opacity(0.2) : .black)
                                    .frame(width: 30, height: 30)
                                    .overlay {
                                        Image(systemName: "speaker.wave.2.fill")
                                            .foregroundColor(coordinator.currentView == .audio ? .white : .gray)
                                            .padding()
                                            .imageScale(.medium)
                                    }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        if Defaults[.enableDisplayHub] && Defaults[.showDisplayHubInNotch] {
                            Button(action: {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                    if coordinator.currentView == .display {
                                        coordinator.currentView = .home
                                    } else {
                                        coordinator.currentView = .display
                                    }
                                }
                            }) {
                                Capsule()
                                    .fill(coordinator.currentView == .display ? Color.white.opacity(0.2) : .black)
                                    .frame(width: 30, height: 30)
                                    .overlay {
                                        Image(systemName: "sun.max.fill")
                                            .foregroundColor(coordinator.currentView == .display ? .white : .gray)
                                            .padding()
                                            .imageScale(.medium)
                                    }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        if Defaults[.showMirror] {
                            Button(action: {
                                vm.toggleCameraPreview()
                            }) {
                                Capsule()
                                    .fill(.black)
                                    .frame(width: 30, height: 30)
                                    .overlay {
                                        Image(systemName: "camera.fill")
                                            .foregroundColor(.white)
                                            .padding()
                                            .imageScale(.medium)
                                    }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        if Defaults[.settingsIconInNotch] || FeatureTourController.shared.isTourActive {
                            Button(action: {
                                DispatchQueue.main.async {
                                    SettingsWindowController.shared.showWindow()
                                }
                            }) {
                                Capsule()
                                    .fill(.black)
                                    .frame(width: 30, height: 30)
                                    .overlay {
                                        Image(systemName: "gearshape.fill")
                                            .foregroundColor(.white)
                                            .padding()
                                            .imageScale(.medium)
                                    }
                            }
                            .buttonStyle(PlainButtonStyle())
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

#Preview {
    NotchPulseHeader().environmentObject(NotchPulseViewModel())
}
