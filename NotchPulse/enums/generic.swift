//
//  generic.swift
//  NotchPulse
//
//  Created by Harsh Vardhan  Goswami  on 04/08/24.
//

import Foundation
import Defaults

public enum Style {
    case notch
    case floating
}

public enum ContentType: Int, Codable, Hashable, Equatable {
    case normal
    case menu
    case settings
}

public enum NotchState {
    case closed
    case open
}

public enum NotchViews {
    case home
    case shelf
    case stats
    case clipboard
    case audio
}

enum SettingsEnum {
    case general
    case about
    case charge
    case download
    case mediaPlayback
    case hud
    case shelf
    case extensions
    case audio
}

enum DownloadIndicatorStyle: String, Defaults.Serializable {
    case progress = "Progress"
    case percentage = "Percentage"
}

enum DownloadIconStyle: String, Defaults.Serializable {
    case onlyAppIcon = "Only app icon"
    case onlyIcon = "Only download icon"
    case iconAndAppIcon = "Icon and app icon"
}

enum MirrorShapeEnum: String, Defaults.Serializable {
    case rectangle = "Rectangular"
    case circle = "Circular"
}

enum WindowHeightMode: String, Defaults.Serializable {
    case matchMenuBar = "Match menubar height"
    case matchRealNotchSize = "Match real notch height"
    case custom = "Custom height"
}

enum SliderColorEnum: String, CaseIterable, Defaults.Serializable {
    case white = "White"
    case albumArt = "Match album art"
    case accent = "Accent color"
}

enum StandbyClockStyle: String, CaseIterable, Identifiable, Defaults.Serializable {
    case digitalStacked = "Digital Stacked"
    case dualWidget = "Analog & Calendar"
    case retroFlip = "Retro Flip Clock"
    case solarDial = "Solar Dial"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .digitalStacked: return "iOS Big Digital"
        case .dualWidget: return "Analog & Calendar"
        case .retroFlip: return "Retro Flip Clock"
        case .solarDial: return "Solar Minimalist"
        }
    }
    
    var systemIcon: String {
        switch self {
        case .digitalStacked: return "clock.fill"
        case .dualWidget: return "calendar.badge.clock"
        case .retroFlip: return "rectangle.split.2x1.fill"
        case .solarDial: return "sun.max.circle.fill"
        }
    }
}

enum StandbyTheme: String, CaseIterable, Identifiable, Defaults.Serializable {
    case neonSunset = "Neon Sunset"
    case oceanWave = "Ocean Wave"
    case cyberMint = "Cyber Mint"
    case pureMinimal = "Pure Minimal"
    case nightRed = "Night Red"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .neonSunset: return "Neon Sunset"
        case .oceanWave: return "Ocean Wave"
        case .cyberMint: return "Cyber Mint"
        case .pureMinimal: return "Pure Minimal"
        case .nightRed: return "Night Red"
        }
    }
}
