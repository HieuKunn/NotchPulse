import Defaults
import Foundation

/// Background visual style for the fullscreen Launchpad Home overlay.
enum LaunchpadBackgroundStyle: String, CaseIterable, Identifiable, Codable, Defaults.Serializable {
    case systemGlass = "System Glass"
    case dimmed = "Dimmed Wallpaper"

    var id: String { rawValue }
}

/// Optional screen corner trigger to open Launchpad Home on pointer dwell.
enum LaunchpadHotCorner: String, CaseIterable, Identifiable, Codable, Defaults.Serializable {
    case none = "Disabled"
    case topLeft = "Top Left"
    case topRight = "Top Right"
    case bottomLeft = "Bottom Left"
    case bottomRight = "Bottom Right"

    var id: String { rawValue }
}

/// Represents a discovered macOS application displayed in Launchpad Home.
struct LaunchpadAppItem: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var name: String
    var bundlePath: String
    var bundleIdentifier: String?
    var categoryType: String?

    var isSystemProtected: Bool {
        bundlePath.hasPrefix("/System/")
    }

    var bundleURL: URL {
        URL(fileURLWithPath: bundlePath)
    }
}

/// Represents a user-created or system-grouped folder containing applications.
struct LaunchpadFolderItem: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var items: [LaunchpadAppItem]
}

/// Either a standalone app tile or a folder tile inside a Launchpad page.
enum LaunchpadNode: Identifiable, Codable, Hashable, Sendable {
    case app(LaunchpadAppItem)
    case folder(LaunchpadFolderItem)

    var id: String {
        switch self {
        case .app(let app):
            return "app:\(app.id)"
        case .folder(let folder):
            return "folder:\(folder.id.uuidString)"
        }
    }

    var displayName: String {
        switch self {
        case .app(let app):
            return app.name
        case .folder(let folder):
            return folder.name
        }
    }

    var isFolder: Bool {
        if case .folder = self { return true }
        return false
    }

    var asApp: LaunchpadAppItem? {
        if case .app(let app) = self { return app }
        return nil
    }

    var asFolder: LaunchpadFolderItem? {
        if case .folder(let folder) = self { return folder }
        return nil
    }
}

/// A single page of tiles in the horizontal Launchpad Home pager.
struct LaunchpadPage: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var nodes: [LaunchpadNode]
}

/// Persisted snapshot of page order and folders.
struct LaunchpadLayoutSnapshot: Codable, Sendable {
    var version: Int = 1
    var pages: [LaunchpadPage]
}

