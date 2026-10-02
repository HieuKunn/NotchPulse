//
//  TabSelectionView.swift
//  NotchPulse
//
//  Created by Hugo Persson on 2024-08-25.
//

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
            list.append(TabModel(label: "Stats", icon: "cpu", view: .stats))
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
            AudioDeviceManager.shared.refreshApps()
            let isExpanded = (UserDefaults.standard.object(forKey: "NotchPulse_AudioHubAppsExpanded") as? Bool) ?? true
            let targetHeight = AudioHubNotchView.calculateHeight(selectedTab: AudioDeviceManager.shared.selectedTab, isAppsExpanded: isExpanded)
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                vm.customOpenHeight = targetHeight
            }
        } else if tabView != .stats && vm.customOpenHeight != nil {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                vm.customOpenHeight = nil
            }
        }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            coordinator.currentView = tabView
        }
    }

    @ViewBuilder
    private func tabBackground(isSelected: Bool) -> some View {
        if isSelected {
            Capsule()
                .fill(Color(nsColor: .secondarySystemFill))
                .matchedGeometryEffect(id: "capsule", in: animation)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                let isSelected = (tab.view == coordinator.currentView)
                let isSpotlight = (vm.featureTourTarget == String(describing: tab.view))
                TabButton(label: tab.label, icon: tab.icon, selected: isSelected) {
                    selectTab(tab.view)
                }
                .frame(height: 26)
                .foregroundStyle(isSelected ? Color.white : Color.gray)
                .background(tabBackground(isSelected: isSelected))
            }
        }
        .clipShape(Capsule())
    }
}

#Preview {
    NotchPulseHeader().environmentObject(NotchPulseViewModel())
}
