//
//  MediaChecker.swift
//  NotchPulse
//
//  Created by Alexander on 2025-07-26.
//

import Foundation

final class MediaChecker: Sendable {

    enum MediaCheckerError: Error {
        case missingResources
    }

    func checkDeprecationStatus() -> Bool {
        // Fast, reliable native check without spawning fragile external perl sub-processes
        // that get killed by Gatekeeper quarantine or sandbox policies on clean user installs.
        let systemFrameworkPath = "/System/Library/PrivateFrameworks/MediaRemote.framework"
        guard FileManager.default.fileExists(atPath: systemFrameworkPath) else {
            print("MediaChecker: System MediaRemote framework not found at \(systemFrameworkPath)")
            return true
        }

        // Verify the bundle can be opened and standard functions are resolvable
        guard let bundle = CFBundleCreate(kCFAllocatorDefault, NSURL(fileURLWithPath: systemFrameworkPath)),
              CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteSendCommand" as CFString) != nil else {
            print("MediaChecker: Unable to resolve MRMediaRemoteSendCommand in MediaRemote.framework")
            return true
        }

        // Verify the bundled adapter resources exist
        let hasScript = Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl") != nil ||
            (Bundle.main.resourcePath.map { FileManager.default.fileExists(atPath: $0 + "/mediaremote-adapter.pl") } ?? false)
        let hasHelper = Bundle.main.url(forResource: "MediaRemoteAdapterTestClient", withExtension: nil) != nil ||
            (Bundle.main.resourcePath.map { FileManager.default.fileExists(atPath: $0 + "/MediaRemoteAdapterTestClient") } ?? false)
        let frameworkPath = Bundle.main.privateFrameworksPath?.appending("/MediaRemoteAdapter.framework") ??
            (Bundle.main.resourcePath.map { $0 + "/../Frameworks/MediaRemoteAdapter.framework" } ?? "")
        let hasFramework = FileManager.default.fileExists(atPath: frameworkPath)

        guard hasScript, hasFramework, hasHelper else {
            print("MediaChecker: App bundle is missing internal mediaremote-adapter resources")
            return true
        }

        // MediaRemote and internal adapter are functional
        return false
    }
}
