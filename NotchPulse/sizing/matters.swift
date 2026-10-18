import Defaults
import Foundation
import SwiftUI
import Darwin

/// Global hardware info caching whether this Mac machine has a physical screen notch.
/// Evaluated ONCE at runtime, cached in memory, zero overhead on repeated calls.
enum DeviceHardwareInfo {
    static let deviceHasPhysicalNotch: Bool = {
        // 1. First check if any connected screen already reports safeAreaInsets.top > 0 or auxiliary notch areas
        if NSScreen.screens.contains(where: { $0.safeAreaInsets.top > 0 || $0.auxiliaryTopLeftArea != nil }) {
            UserDefaults.standard.set(true, forKey: "DeviceHardwareInfo.hasNotch")
            return true
        }

        // 2. Check cached value in UserDefaults (e.g. clamshell mode with external display)
        if UserDefaults.standard.object(forKey: "DeviceHardwareInfo.hasNotch") != nil {
            return UserDefaults.standard.bool(forKey: "DeviceHardwareInfo.hasNotch")
        }

        // 3. Sysctl hardware model check (instant and definitive for Apple Silicon MacBooks with notch)
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return false }
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        let modelString = String(cString: model)

        // Apple Silicon models with hardware notch:
        // - MacBookPro18,1...18,4 (M1 Pro/Max 14/16")
        // - Mac14,2 (M2 Air 13"), Mac14,15 (M2 Air 15")
        // - Mac14,5, Mac14,6, Mac14,9, Mac14,10 (M2 Pro/Max 14/16")
        // - Mac15,1...15,13 (M3 Air/Pro)
        // - Mac16,* (M4 MacBook Pro)
        let isNotchModel = modelString.hasPrefix("MacBookPro18,")
            || (modelString.hasPrefix("Mac14,") && modelString != "Mac14,7")
            || modelString.hasPrefix("Mac15,")
            || modelString.hasPrefix("Mac16,")

        UserDefaults.standard.set(isNotchModel, forKey: "DeviceHardwareInfo.hasNotch")
        return isNotchModel
    }()
}

@MainActor func screenHasPhysicalNotch(_ screen: NSScreen?) -> Bool {
    guard let screen = screen else { return false }
    if screen.safeAreaInsets.top > 0 || screen.auxiliaryTopLeftArea != nil {
        return true
    }
    // If device is a notch model and this is the built-in screen
    if DeviceHardwareInfo.deviceHasPhysicalNotch {
        if screen.isBuiltIn {
            return true
        }
        if NSScreen.screens.count == 1 {
            return true
        }
    }
    return false
}

@MainActor func physicalNotchHeight(for screen: NSScreen?) -> CGFloat {
    guard let screen = screen else { return 34 }
    if screen.safeAreaInsets.top > 0 {
        return screen.safeAreaInsets.top
    }
    let menuBarH = screen.frame.maxY - screen.visibleFrame.maxY
    if menuBarH > 24 {
        return menuBarH
    }
    return 34
}

/// Computes the effective top gap for Dynamic Island.
/// If the target screen has a physical notch, Dynamic Island is automatically placed
/// below the physical notch (`physicalNotchHeight + userTopOffset`) so the capsule is never
/// obscured or tucked behind the hardware notch.
/// On screens without a notch (external displays or non-notch Macs), returns `userTopOffset`.
@MainActor func effectiveDynamicIslandTopOffset(for screen: NSScreen?, userOffset: CGFloat? = nil) -> CGFloat {
    let offset = userOffset ?? Defaults[.dynamicIslandTopOffset]
    if screenHasPhysicalNotch(screen) {
        return physicalNotchHeight(for: screen) + offset
    }
    return offset
}

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

public let compactDynamicIslandWidth: CGFloat = 126
public let compactDynamicIslandHeight: CGFloat = 32

@MainActor func getClosedNotchSize(screenUUID: String? = nil) -> CGSize {
    var notchHeight: CGFloat = Defaults[.nonNotchHeight]
    var notchWidth: CGFloat = 185

    let screen = resolveScreen(screenUUID: screenUUID)

    if let screen = screen {
        // Calculate and set the exact width of the notch
        if let topLeftNotchpadding: CGFloat = screen.auxiliaryTopLeftArea?.width,
           let topRightNotchpadding: CGFloat = screen.auxiliaryTopRightArea?.width
        {
            let rawWidth = screen.frame.width - topLeftNotchpadding - topRightNotchpadding
            if rawWidth > 0 {
                // Must cover the physical hardware notch cut-out completely (exactly as in Glance and original NotchPulse)
                notchWidth = max(185, rawWidth)
            }
        }

        // Check if the Mac has a notch
        if screen.safeAreaInsets.top > 0 {
            notchHeight = Defaults[.notchHeight]
            if Defaults[.notchHeightMode] == .matchRealNotchSize {
                notchHeight = screen.safeAreaInsets.top
            } else if Defaults[.notchHeightMode] == .matchMenuBar {
                let menuBarH = screen.frame.maxY - screen.visibleFrame.maxY
                notchHeight = menuBarH > 0 ? menuBarH : screen.safeAreaInsets.top
            }
        } else {
            notchHeight = Defaults[.nonNotchHeight]
            if Defaults[.nonNotchHeightMode] == .matchMenuBar {
                let menuBarH = screen.frame.maxY - screen.visibleFrame.maxY
                notchHeight = menuBarH > 0 ? menuBarH : Defaults[.nonNotchHeight]
            }
        }
    }

    return .init(width: notchWidth, height: notchHeight)
}
