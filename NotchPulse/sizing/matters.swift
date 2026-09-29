//
//  sizeMatters.swift
//  NotchPulse
//
//  Created by Harsh Vardhan  Goswami  on 05/08/24.
//

import Defaults
import Foundation
import SwiftUI

let downloadSneakSize: CGSize = .init(width: 65, height: 1)
let batterySneakSize: CGSize = .init(width: 160, height: 1)

let shadowPadding: CGFloat = 20
let maxNotchWidth: CGFloat = 1000
let minNotchWidth: CGFloat = 560
let defaultNotchWidth: CGFloat = 740

var openNotchWidth: CGFloat {
    max(minNotchWidth, min(maxNotchWidth, Defaults[.notchOpenWidth]))
}

var openNotchSize: CGSize {
    .init(width: openNotchWidth, height: 190)
}
let maxNotchWindowHeight: CGFloat = 460
let windowSize: CGSize = .init(width: maxNotchWidth + 60, height: maxNotchWindowHeight + shadowPadding)
let cornerRadiusInsets: (opened: (top: CGFloat, bottom: CGFloat), closed: (top: CGFloat, bottom: CGFloat)) = (opened: (top: 19, bottom: 24), closed: (top: 6, bottom: 14))

enum MusicPlayerImageSizes {
    static let cornerRadiusInset: (opened: CGFloat, closed: CGFloat) = (opened: 13.0, closed: 4.0)
    static let size = (opened: CGSize(width: 90, height: 90), closed: CGSize(width: 20, height: 20))
}

@MainActor func resolveScreen(screenUUID: String? = nil) -> NSScreen? {
    if let uuid = screenUUID, let screen = NSScreen.screen(withUUID: uuid) {
        return screen
    }
    let coordinator = NotchPulseViewCoordinator.shared
    if let prefUUID = coordinator.preferredScreenUUID, let screen = NSScreen.screen(withUUID: prefUUID) {
        return screen
    }
    if let selScreen = NSScreen.screen(withUUID: coordinator.selectedScreenUUID) {
        return selScreen
    }
    // Prefer built-in display or display with physical notch
    if let builtInWithNotch = NSScreen.screens.first(where: { $0.isBuiltIn || $0.safeAreaInsets.top > 0 || $0.auxiliaryTopLeftArea != nil }) {
        return builtInWithNotch
    }
    return NSScreen.main ?? NSScreen.screens.first
}

@MainActor func getScreenFrame(_ screenUUID: String? = nil) -> CGRect? {
    return resolveScreen(screenUUID: screenUUID)?.frame
}

@MainActor func getClosedNotchSize(screenUUID: String? = nil) -> CGSize {
    let isDynamicIsland = Defaults[.notchStyle] == .dynamicIsland
    let screen = resolveScreen(screenUUID: screenUUID)
    
    var notchHeight: CGFloat = isDynamicIsland ? 32 : Defaults[.nonNotchHeight]
    var notchWidth: CGFloat = isDynamicIsland ? 80 : 185

    if let screen = screen {
        // Calculate and set the exact width of the notch
        if let topLeftNotchpadding: CGFloat = screen.auxiliaryTopLeftArea?.width,
           let topRightNotchpadding: CGFloat = screen.auxiliaryTopRightArea?.width
        {
            let physicalWidth = screen.frame.width - topLeftNotchpadding - topRightNotchpadding
            notchWidth = isDynamicIsland ? 80 : max(150, physicalWidth)
        }

        // Check if the Mac has a notch
        if screen.safeAreaInsets.top > 0 {
            notchHeight = isDynamicIsland ? 32 : Defaults[.notchHeight]
            if !isDynamicIsland {
                if Defaults[.notchHeightMode] == .matchRealNotchSize {
                    notchHeight = screen.safeAreaInsets.top
                } else if Defaults[.notchHeightMode] == .matchMenuBar {
                    let menuBarH = screen.frame.maxY - screen.visibleFrame.maxY
                    notchHeight = menuBarH > 0 ? menuBarH : screen.safeAreaInsets.top
                }
            }
        } else {
            notchHeight = isDynamicIsland ? 32 : Defaults[.nonNotchHeight]
            if !isDynamicIsland && Defaults[.nonNotchHeightMode] == .matchMenuBar {
                let menuBarH = screen.frame.maxY - screen.visibleFrame.maxY
                notchHeight = menuBarH > 0 ? menuBarH : Defaults[.nonNotchHeight]
            }
        }
    }

    return .init(width: notchWidth, height: notchHeight)
}
