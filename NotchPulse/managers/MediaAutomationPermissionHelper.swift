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
            requestPermission(for: "com.spotify.client")
            requestPermission(for: "com.apple.Music")
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
        let scriptSource = "tell application id \"com.apple.Music\" to return"
        if let script = NSAppleScript(source: scriptSource) {
            var err: NSDictionary?
            script.executeAndReturnError(&err)
            if err == nil {
                UserDefaults.standard.set(true, forKey: "MediaSyncConfirmed")
                return true
            }
        }
        let spScript = "tell application id \"com.spotify.client\" to return"
        if let script = NSAppleScript(source: spScript) {
            var err: NSDictionary?
            script.executeAndReturnError(&err)
            if err == nil {
                UserDefaults.standard.set(true, forKey: "MediaSyncConfirmed")
                return true
            }
        }
        return false
    }

    @discardableResult
    static func requestPermission(for bundleIdentifier: String) -> Bool {
        // Executing a dummy AppleScript targeted at the bundle ID is the most reliable way 
        // to force macOS to display the Automation permission prompt to the user.
        let scriptSource = "tell application id \"\(bundleIdentifier)\" to return"
        guard let script = NSAppleScript(source: scriptSource) else { return false }
        
        var errorInfo: NSDictionary?
        script.executeAndReturnError(&errorInfo)
        
        if let error = errorInfo {
            print("[AutomationPermission] Request for \(bundleIdentifier) failed/denied: \(error)")
            return false
        }
        return true
    }
}
