import Defaults
import SwiftUI

struct TabModel: Identifiable, Equatable {
    var id: NotchViews { view }
    let label: String
    let icon: String
    let view: NotchViews
    
    static func == (lhs: TabModel, rhs: TabModel) -> Bool {
        lhs.view == rhs.view
    }
}

@available(macOS 14.0, *)
struct TabSelectionView: View {
    @EnvironmentObject var vm: NotchPulseViewModel
    @ObservedObject var coordinator = NotchPulseViewCoordinator.shared
    @Default(.notchPulseShelf) var notchPulseShelf
    @Default(.enableSystemMonitor) var enableSystemMonitor
    @Default(.enableClipboardManager) var enableClipboardManager
    @Namespace var animation

    var tabs: [TabModel] {
        var list: [TabModel] = [
            TabModel(label: "Home", icon: "house.fill", view: .home)
        ]
        if notchPulseShelf {
            list.append(TabModel(label: "Shelf", icon: "tray.fill", view: .shelf))
        }
        if enableSystemMonitor {
            list.append(TabModel(label: "Stats", icon: "chart.bar.fill", view: .stats))
        }
        if enableClipboardManager {
            list.append(TabModel(label: "Clipboard", icon: "doc.on.clipboard.fill", view: .clipboard))
        }
        return list
    }

    @MainActor
    private func selectTab(_ tabView: NotchViews) {
        (NSApp.delegate as? AppDelegate)?.resetAllDropAndDragTargeting()
        vm.dragDetectorTargeting = false
        vm.dropZoneTargeting = false
        vm.generalDropTargeting = false
        vm.anyDropZoneTargeting = false
        CalendarStateViewModel.shared.isFullMonthExpanded = false
        if tabView == .audio {
            AudioDeviceManager.shared.refreshDevices()
            let targetHeight = AudioHubNotchView.calculateHeight(selectedTab: AudioDeviceManager.shared.selectedTab)
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                vm.customOpenHeight = targetHeight
            }
        } else if tabView != .stats && vm.customOpenHeight != nil {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                vm.customOpenHeight = nil
            }
        }
        if tabView != .stats {
            SystemMonitorManager.shared.stopMonitoring()
            SystemMonitorManager.shared.stopThermalMonitoring()
        }
        MusicManager.shared.isUIActive = (tabView == .home)
        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            coordinator.currentView = tabView
        }
    }

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 2) {
            ForEach(tabs) { tab in
                let isSelected = (tab.view == coordinator.currentView)
                Button {
                    selectTab(tab.view)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                    }
                    .padding(.horizontal, 11)
                    .frame(height: 22)
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .background {
                        if isSelected {
                            ZStack {
                                Capsule()
                                    .fill(colorScheme == .dark ? Color.white.opacity(0.20) : Color.white.opacity(0.85))
                                Capsule()
                                    .strokeBorder(
                                        colorScheme == .dark ? Color.white.opacity(0.28) : Color.black.opacity(0.10),
                                        lineWidth: 0.8
                                    )
                            }
                            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.08), radius: 2, y: 1)
                            .matchedGeometryEffect(id: "activeTab", in: animation)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(2)
        .background {
            ZStack {
                Capsule()
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05))
                Capsule()
                    .strokeBorder(
                        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08),
                        lineWidth: 0.8
                    )
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: coordinator.currentView)
    }
}

#Preview {
    NotchPulseHeader().environmentObject(NotchPulseViewModel())
}
