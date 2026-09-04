//
//  TabSelectionView.swift
//  boringNotch
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
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Default(.boringShelf) var boringShelf
    @Default(.enableSystemMonitor) var enableSystemMonitor
    @Namespace var animation

    var tabs: [TabModel] {
        var list: [TabModel] = [
            TabModel(label: "Home", icon: "house.fill", view: .home)
        ]
        if boringShelf {
            list.append(TabModel(label: "Shelf", icon: "tray.fill", view: .shelf))
        }
        if enableSystemMonitor {
            list.append(TabModel(label: "Stats", icon: "cpu", view: .stats))
        }
        return list
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                TabButton(label: tab.label, icon: tab.icon, selected: coordinator.currentView == tab.view) {
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
    BoringHeader().environmentObject(BoringViewModel())
}
