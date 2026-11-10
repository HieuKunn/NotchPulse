import Foundation
import CoreServices
import AppKit

enum MediaAutomationPermissionHelper {
    static func requestAllPermissions() {
        DispatchQueue.global(qos: .userInitiated).async {
            _ = requestPermission(for: "com.spotify.client")
            _ = requestPermission(for: "com.apple.Music")
        }
    }

    static func requestAndVerify() async -> Bool {
        await Task.detached(priority: .userInitiated) {
            let sp = requestPermission(for: "com.spotify.client")
            let am = requestPermission(for: "com.apple.Music")
            let confirmed = sp || am
            if confirmed {
                UserDefaults.standard.set(true, forKey: "MediaSyncConfirmed")
            }
            return confirmed
        }.value
    }

    static func isSyncConfirmed() -> Bool {
        if UserDefaults.standard.bool(forKey: "MediaSyncConfirmed") {
            return true
        }
        return false
    }

    /// Checks the exact automation permission status for a bundle ID without displaying a prompt.
    static func checkAutomationStatus(for bundleIdentifier: String) -> PermissionStatus {
        var targetDesc = AEDesc()
        guard let bundleIDData = bundleIdentifier.data(using: .utf8) else { return .notDetermined }
        
        let createStatus = bundleIDData.withUnsafeBytes { ptr in
            AECreateDesc(typeApplicationBundleID, ptr.baseAddress, bundleIDData.count, &targetDesc)
        }
        
        guard createStatus == noErr else { return .notDetermined }
        defer { AEDisposeDesc(&targetDesc) }

        // Query status without prompting
        let permStatus = AEDeterminePermissionToAutomateTarget(&targetDesc, typeWildCard, typeWildCard, false)
        
        if permStatus == -1743 { // errAEEventNotPermitted (user denied)
            return .denied
        } else if permStatus == noErr {
            return .granted
        } else if permStatus == -1744 { // errAEEventWouldRequireUserConsent (not yet prompted)
            return .notDetermined
        }
        return isSyncConfirmed() ? .granted : .notDetermined
    }

    /// Evaluates overall automation status for Spotify and Apple Music, distinguishing .denied from .notDetermined.
    static func overallMusicAutomationStatus() -> PermissionStatus {
        let music = checkAutomationStatus(for: "com.apple.Music")
        let spotify = checkAutomationStatus(for: "com.spotify.client")
        return determineCombinedStatus(spotify: spotify, appleMusic: music)
    }

    /// Pure helper for evaluating overall status given Spotify and Apple Music statuses.
    static func determineCombinedStatus(spotify: PermissionStatus, appleMusic: PermissionStatus) -> PermissionStatus {
        if spotify == .granted && appleMusic == .granted {
            return .granted
        }
        if spotify == .granted || appleMusic == .granted {
            return .partiallyAuthorized
        }
        if spotify == .denied || appleMusic == .denied {
            return .denied
        }
        return .notDetermined
    }

    @discardableResult
    static func requestPermission(for bundleIdentifier: String) -> Bool {
        var targetDesc = AEDesc()
        guard let bundleIDData = bundleIdentifier.data(using: .utf8) else { return false }
        
        let createStatus = bundleIDData.withUnsafeBytes { ptr in
            AECreateDesc(typeApplicationBundleID, ptr.baseAddress, bundleIDData.count, &targetDesc)
        }
        
        if createStatus == noErr {
            let permStatus = AEDeterminePermissionToAutomateTarget(&targetDesc, typeWildCard, typeWildCard, true)
            AEDisposeDesc(&targetDesc)
            if permStatus == noErr {
                UserDefaults.standard.set(true, forKey: "MediaSyncConfirmed")
                return true
            }
        }
        
        let scriptSource = "tell application id \"\(bundleIdentifier)\" to return"
        guard let script = NSAppleScript(source: scriptSource) else { return false }
        
        var errorInfo: NSDictionary?
        script.executeAndReturnError(&errorInfo)
        
        if let error = errorInfo {
            print("[AutomationPermission] Request for \(bundleIdentifier) failed/denied: \(error)")
            return false
        }
        UserDefaults.standard.set(true, forKey: "MediaSyncConfirmed")
        return true
    }
}
