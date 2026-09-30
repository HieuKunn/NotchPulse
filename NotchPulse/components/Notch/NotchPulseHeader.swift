//
//  NotchPulseHeader.swift
//  NotchPulse
//
//  Created by Harsh Vardhan  Goswami  on 04/08/24.
//

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
        isDynamicIsland ? 22 : max(22, cornerRadiusInsets.opened.top + 4)
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
            if !isDynamicIsland && (activeScreen?.safeAreaInsets.top ?? 0 > 0) {
                Rectangle()
                    .fill(.black)
                    .frame(width: vm.closedNotchSize.width)
                    .mask {
                        NotchShape()
                    }
            } else {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: vm.closedNotchSize.width)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        vm.close()
                    }
            }

            HStack(spacing: 6) {
                if isHUDType(coordinator.sneakPeek.type) && coordinator.sneakPeek.show && Defaults[.showOpenNotchHUD] {
                    OpenNotchHUD(type: $coordinator.sneakPeek.type, value: $coordinator.sneakPeek.value, icon: $coordinator.sneakPeek.icon)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                } else {
                    HStack(spacing: 6) {
                        if Defaults[.showMirror] {
                            Button(action: {
                                vm.toggleCameraPreview()
                            }) {
                                Capsule()
                                    .fill(.black)
                                    .frame(width: 30, height: 30)
                                    .overlay {
                                        Image(systemName: "web.camera")
                                            .foregroundColor(.white)
                                            .padding()
                                            .imageScale(.medium)
                                    }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        if Defaults[.settingsIconInNotch] {
                            Button(action: {
                                DispatchQueue.main.async {
                                    SettingsWindowController.shared.showWindow()
                                }
                            }) {
                                Capsule()
                                    .fill(.black)
                                    .frame(width: 30, height: 30)
                                    .overlay {
                                        Image(systemName: "gear")
                                            .foregroundColor(.white)
                                            .padding()
                                            .imageScale(.medium)
                                    }
                            }
                            .buttonStyle(PlainButtonStyle())
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
