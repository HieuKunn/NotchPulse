//
//  MediaAutomationPermissionHelper.swift
//  NotchPulse
//
//  Helper to determine and request AppleEvents Automation permissions
//  for Spotify and Apple Music to ensure synchronized playback & lyrics.
//

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
