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
