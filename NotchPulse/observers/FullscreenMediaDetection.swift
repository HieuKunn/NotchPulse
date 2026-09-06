//
//  FullscreenMediaDetection.swift
//  NotchPulse
//
//  Created by Richard Kunkli on 06/09/2024.
//

import Cocoa
import Foundation
import Combine
import Defaults

// MARK: - FullScreenMonitor (Embedded from MacroVisionKit)

public actor FullScreenMonitor {
    public static let shared = FullScreenMonitor()
    
    // MARK: - Public Types
    public struct SpaceInfo: Equatable, Sendable {
        public let runningApps: [String]
        public let screenUUID: String?
        
        public var debugDescription: String {
            let screenName = screenUUID.map { String($0.prefix(8)) } ?? "Unknown"
            let apps = runningApps.isEmpty ? "Unknown" : runningApps.joined(separator: ", ")
            return "Screen: \(screenName) - Full Screen: \(apps)"
        }
        
        public static func == (lhs: SpaceInfo, rhs: SpaceInfo) -> Bool {
            return lhs.runningApps == rhs.runningApps &&
                   lhs.screenUUID == rhs.screenUUID
        }
    }
    
    // MARK: - Properties
    private var fullscreenSpaces: [SpaceInfo] = []
    private var spaceChangesContinuation: AsyncStream<[SpaceInfo]>.Continuation?
    private nonisolated(unsafe) var observerTokens: [NSObjectProtocol] = []
    
    // MARK: - Initialization
    private init() {
        fullscreenSpaces = Self.detectSpaces()
        setupObservers()
    }
    
    deinit {
        spaceChangesContinuation?.finish()
        removeObservers()
    }
    
    // MARK: - Private Methods
    private nonisolated func setupObservers() {
        let center = NSWorkspace.shared.notificationCenter
        
        let spaceChangeToken = center.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { [weak self] in
                await self?.updateSpaceInformation()
            }
        }
        
        let screenChangeToken = center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { [weak self] in
                await self?.updateSpaceInformation()
            }
        }
        
        observerTokens = [spaceChangeToken, screenChangeToken]
    }
    
    private nonisolated func removeObservers() {
        let center = NSWorkspace.shared.notificationCenter
        for token in observerTokens {
            center.removeObserver(token)
        }
        observerTokens.removeAll()
    }
    
    private func updateSpaceInformation() {
        let newSpaces = Self.detectSpaces()
        let newFullscreenSpaces = newSpaces
        
        if fullscreenSpaces != newFullscreenSpaces {
            fullscreenSpaces = newFullscreenSpaces
            spaceChangesContinuation?.yield(newFullscreenSpaces)
        }
    }

    private nonisolated static func detectSpaces() -> [SpaceInfo] {
        guard let displaySpaces = CGSCopyManagedDisplaySpaces(_CGSMainConnectionID()) as? [NSDictionary] else {
            return []
        }
        
        var newSpaces: [SpaceInfo] = []
        
        for displayDict in displaySpaces {
            guard let currentSpaceDict = displayDict["Current Space"] as? [String: Any],
                  let spacesList = displayDict["Spaces"] as? [[String: Any]],
                  let displayID = displayDict["Display Identifier"] as? String else {
                continue
            }
            
            let activeSpaceID = currentSpaceDict["ManagedSpaceID"] as? Int ?? -1
            
            guard let activeSpace = spacesList.first(where: { ($0["ManagedSpaceID"] as? Int) == activeSpaceID }) else {
                continue
            }
            
            let tileLayoutManager = activeSpace["TileLayoutManager"] as? [String: Any]
            let isFullScreen = tileLayoutManager != nil
            
            if isFullScreen {
                var runningApps: [String] = []
                
                if let pidVal = activeSpace["pid"] as? Int32,
                   let app = NSRunningApplication(processIdentifier: pidVal),
                   let bundleID = app.bundleIdentifier {
                    runningApps.append(bundleID)
                }
                
                if let tileManager = tileLayoutManager,
                   let tileWindows = tileManager["TileSpaces"] as? [[String: Any]] {
                    for tile in tileWindows {
                        if let windowPID = tile["pid"] as? Int32,
                           let app = NSRunningApplication(processIdentifier: windowPID),
                           let bundleID = app.bundleIdentifier,
                           !runningApps.contains(bundleID) {
                            runningApps.append(bundleID)
                        }
                    }
                }
                
                let space = SpaceInfo(
                    runningApps: runningApps,
                    screenUUID: displayID
                )
                
                newSpaces.append(space)
            }
        }
        
        return newSpaces
    }
    
    // MARK: - Public API
    public func detectFullscreenApps(debug: Bool = false) -> [SpaceInfo] {
        return fullscreenSpaces
    }
    
    public func spaceChanges() -> AsyncStream<[SpaceInfo]> {
        AsyncStream { continuation in
            self.spaceChangesContinuation = continuation
            continuation.yield(self.fullscreenSpaces)
            
            continuation.onTermination = { @Sendable _ in
                Task { [weak self] in
                    await self?.clearContinuation()
                }
            }
        }
    }
    
    private func clearContinuation() {
        spaceChangesContinuation = nil
    }
    
    @MainActor
    public func screen(for space: SpaceInfo) -> NSScreen? {
        guard let uuid = space.screenUUID else { return nil }
        
        return NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            let id = CGDirectDisplayID(number.uint32Value)
            guard let screenUUID = CGDisplayCreateUUIDFromDisplayID(id) else { return false }
            let uuidString = CFUUIDCreateString(nil, screenUUID.takeRetainedValue()) as String
            return uuidString == uuid
        }
    }
}

// MARK: - Private CGS API Definitions
private typealias CGSConnectionID = Int32
@_silgen_name("CGSMainConnectionID") private func _CGSMainConnectionID() -> CGSConnectionID
@_silgen_name("CGSCopyManagedDisplaySpaces") private func CGSCopyManagedDisplaySpaces(_ cid: CGSConnectionID) -> CFArray

public enum MacroVisionKit {
    public typealias FullScreenMonitor = NotchPulse.FullScreenMonitor
}

// MARK: - FullscreenMediaDetector
@MainActor
final class FullscreenMediaDetector: ObservableObject {
    static let shared = FullscreenMediaDetector()
    
    @Published var fullscreenStatus: [String: Bool] = [:]
    
    private var monitorTask: Task<Void, Never>?
    
    private init() {
        startMonitoring()
    }
    
    deinit {
        monitorTask?.cancel()
    }
    
    private func startMonitoring() {
        monitorTask = Task { @MainActor in
            let stream = await FullScreenMonitor.shared.spaceChanges()
            for await spaces in stream {
                updateStatus(with: spaces)
            }
        }
    }
    
    private func updateStatus(with spaces: [FullScreenMonitor.SpaceInfo]) {
        var newStatus: [String: Bool] = [:]
        
        for space in spaces {
            if let uuid = space.screenUUID {
                let shouldDetect: Bool
                if Defaults[.hideNotchOption] == .nowPlayingOnly, let musicSourceBundle = MusicManager.shared.bundleIdentifier  {
                    shouldDetect = space.runningApps.contains(musicSourceBundle)
                } else {
                    shouldDetect = true
                }
                newStatus[uuid] = shouldDetect
            }
        }
        
        self.fullscreenStatus = newStatus
    }
}

