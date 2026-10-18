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

            if !isDynamicIsland {
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
                    .frame(width: 120)
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
            .padding(.trailing, headerInset)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .zIndex(2)
        }
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
