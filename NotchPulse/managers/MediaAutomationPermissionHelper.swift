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
    static func requestPermission(for bundleIdentifier: String) -> OSStatus {
        guard let bundleIdData = bundleIdentifier.data(using: .utf8) else { return -1 }
        var targetDesc = AEAddressDesc()
        let createStatus: OSErr = bundleIdData.withUnsafeBytes { ptr in
            AECreateDesc(
                DescType(typeApplicationBundleID),
                ptr.baseAddress,
                bundleIdData.count,
                &targetDesc
            )
        }
        guard createStatus == noErr else { return OSStatus(createStatus) }
        defer { AEDisposeDesc(&targetDesc) }

        return AEDeterminePermissionToAutomateTarget(
            &targetDesc,
            typeWildCard,
            typeWildCard,
            true
        )
    }
}
