//
//  TabSelectionView.swift
//  NotchPulse
//
//  Created by Hugo Persson on 2024-08-25.
//

import Defaults
import SwiftUI

struct TabModel: Identifiable, Equatable {
    let id = UUID()
    let label: String
    let icon: String
    let view: NotchViews
    
    static func == (lhs: TabModel, rhs: TabModel) -> Bool {
        lhs.view == rhs.view
    }
}

struct TabSelectionView: View {
    @EnvironmentObject var vm: NotchPulseViewModel
    @ObservedObject var coordinator = NotchPulseViewCoordinator.shared
    @Default(.notchPulseShelf) var notchPulseShelf
    @Default(.enableSystemMonitor) var enableSystemMonitor
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
        if Defaults[.enableClipboardManager] {
            list.append(TabModel(label: "Clipboard", icon: "doc.on.clipboard.fill", view: .clipboard))
        }
        return list
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                TabButton(label: tab.label, icon: tab.icon, selected: coordinator.currentView == tab.view) {
                    vm.dragDetectorTargeting = false
                    vm.dropZoneTargeting = false
                    vm.generalDropTargeting = false
                    if coordinator.currentView != tab.view && vm.customOpenHeight != nil {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            vm.customOpenHeight = nil
                        }
                    }
                    withAnimation(.smooth) {
                        coordinator.currentView = tab.view
                    }
                }
                .frame(height: 26)
                .foregroundStyle(tab.view == coordinator.currentView ? .white : .gray)
                .background {
                    if tab.view == coordinator.currentView {
                        Capsule()
                            .fill(Color(nsColor: .secondarySystemFill))
                            .matchedGeometryEffect(id: "capsule", in: animation)
                    } else {
                        Capsule()
                            .fill(Color.clear)
                            .matchedGeometryEffect(id: "capsule", in: animation)
                            .hidden()
                    }
                }
            }
        }
        .clipShape(Capsule())
    }
}

#Preview {
    NotchPulseHeader().environmentObject(NotchPulseViewModel())
}
