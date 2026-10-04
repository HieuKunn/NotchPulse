//
//  NowPlayingController.swift
//  NotchPulse
//
//  Created by Alexander on 2025-03-29.
//

import AppKit
import Combine
import Foundation

final class NowPlayingController: ObservableObject, MediaControllerProtocol {
    func updatePlaybackInfo() async {
        await fetchFavoriteStateIfSupported()
    }

    // MARK: - Properties
    @Published private(set) var playbackState: PlaybackState = .init(
        bundleIdentifier: "com.apple.Music"
    )

    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> {
        $playbackState.eraseToAnyPublisher()
    }

    var supportsVolumeControl: Bool {
        let bundleID = playbackState.bundleIdentifier
        return bundleID == "com.apple.Music" || bundleID == "com.spotify.client" || !bundleID.isEmpty
    }

    var supportsFavorite: Bool {
        let bundleID = playbackState.bundleIdentifier
        return bundleID == "com.apple.Music"
    }

    func setFavorite(_ favorite: Bool) async {
        let bundleID = playbackState.bundleIdentifier
        
        if bundleID == "com.apple.Music" {
            let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music")
            if !runningApps.isEmpty {
                let script = """
                tell application "Music"
                    try
                        set favorited of current track to \(favorite ? "true" : "false")
                    end try
                end tell
                """
                try? await AppleScriptHelper.executeVoid(script)
            }
        }
        
        // Update the favorite state locally and fetch updated info
        try? await Task.sleep(for: .milliseconds(150))
        await updatePlaybackInfo()
    }

    private var lastMusicItem:
        (title: String, artist: String, album: String, duration: TimeInterval, artworkData: Data?)?

    // MARK: - Media Remote Functions
    private let mediaRemoteBundle: CFBundle
    private let MRMediaRemoteSendCommandFunction: @convention(c) (Int, AnyObject?) -> Void
    private let MRMediaRemoteSetElapsedTimeFunction: @convention(c) (Double) -> Void
    private let MRMediaRemoteSetShuffleModeFunction: @convention(c) (Int) -> Void
    private let MRMediaRemoteSetRepeatModeFunction: @convention(c) (Int) -> Void

    private var process: Process?
    private var pipeHandler: JSONLinesPipeHandler?
    private var streamTask: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?

    // MARK: - Initialization
    init?() {
        guard
            let bundle = CFBundleCreate(
                kCFAllocatorDefault,
                NSURL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework")),
            let MRMediaRemoteSendCommandPointer = CFBundleGetFunctionPointerForName(
                bundle, "MRMediaRemoteSendCommand" as CFString),
            let MRMediaRemoteSetElapsedTimePointer = CFBundleGetFunctionPointerForName(
                bundle, "MRMediaRemoteSetElapsedTime" as CFString),
            let MRMediaRemoteSetShuffleModePointer = CFBundleGetFunctionPointerForName(
                bundle, "MRMediaRemoteSetShuffleMode" as CFString),
            let MRMediaRemoteSetRepeatModePointer = CFBundleGetFunctionPointerForName(
                bundle, "MRMediaRemoteSetRepeatMode" as CFString)
            
        else { return nil }

        mediaRemoteBundle = bundle
        MRMediaRemoteSendCommandFunction = unsafeBitCast(
            MRMediaRemoteSendCommandPointer, to: (@convention(c) (Int, AnyObject?) -> Void).self)
        MRMediaRemoteSetElapsedTimeFunction = unsafeBitCast(
            MRMediaRemoteSetElapsedTimePointer, to: (@convention(c) (Double) -> Void).self)
        MRMediaRemoteSetShuffleModeFunction = unsafeBitCast(
            MRMediaRemoteSetShuffleModePointer, to: (@convention(c) (Int) -> Void).self)
        MRMediaRemoteSetRepeatModeFunction = unsafeBitCast(
            MRMediaRemoteSetRepeatModePointer, to: (@convention(c) (Int) -> Void).self)

        // Auto-reconnect adapter whenever Mac wakes from sleep to prevent stale Mach connections
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(600))
                await self?.setupNowPlayingObserver()
            }
        }

        Task { await setupNowPlayingObserver() }
    }

    deinit {
        streamTask?.cancel()
        
        if let observer = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            wakeObserver = nil
        }

        if let pipeHandler = self.pipeHandler {
            Task { await pipeHandler.close() }
        }
        
        if let process = self.process {
            if process.isRunning {
                process.interrupt()
                process.terminate()
            }
        }

        self.process = nil
        self.pipeHandler = nil
    }

    // MARK: - Helper
    private func getEffectiveBundleID() -> String {
        if !playbackState.bundleIdentifier.isEmpty {
            return playbackState.bundleIdentifier
        }
        if let id = MusicManager.shared.bundleIdentifier, !id.isEmpty {
            return id
        }
        if !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty {
            return "com.apple.Music"
        }
        if !NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").isEmpty {
            return "com.spotify.client"
        }
        return ""
    }

    // MARK: - Media Key Fallback
    private func postMediaKeyEvent(for command: Int) {
        let keyType: Int32?
        switch command {
        case 0, 1, 2:
            keyType = 16 // NX_KEYTYPE_PLAY
        case 4:
            keyType = 17 // NX_KEYTYPE_NEXT
        case 5:
            keyType = 18 // NX_KEYTYPE_PREVIOUS
        default:
            keyType = nil
        }
        guard let key = keyType else { return }

        func sendKey(down: Bool) {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xa00 : 0xb00)
            let data1 = Int((key << 16) | (down ? 0xa00 : 0xb00))
            let ev = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: flags,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: data1,
                data2: -1
            )
            ev?.cgEvent?.post(tap: .cghidEventTap)
        }
        sendKey(down: true)
        sendKey(down: false)
    }

    // MARK: - Protocol Implementation
    func play() async {
        MRMediaRemoteSendCommandFunction(0, nil)
        let bundleID = getEffectiveBundleID()
        if bundleID == "com.apple.Music" || bundleID.contains("Music") {
            try? await AppleScriptHelper.executeVoid("tell application \"Music\" to play")
        } else if bundleID == "com.spotify.client" || bundleID.contains("Spotify") {
            try? await AppleScriptHelper.executeVoid("tell application \"Spotify\" to play")
        } else {
            postMediaKeyEvent(for: 0)
        }
    }

    func pause() async {
        MRMediaRemoteSendCommandFunction(1, nil)
        let bundleID = getEffectiveBundleID()
        if bundleID == "com.apple.Music" || bundleID.contains("Music") {
            try? await AppleScriptHelper.executeVoid("tell application \"Music\" to pause")
        } else if bundleID == "com.spotify.client" || bundleID.contains("Spotify") {
            try? await AppleScriptHelper.executeVoid("tell application \"Spotify\" to pause")
        } else {
            postMediaKeyEvent(for: 1)
        }
    }

    func togglePlay() async {
        MRMediaRemoteSendCommandFunction(2, nil)
        let bundleID = getEffectiveBundleID()
        if bundleID == "com.apple.Music" || bundleID.contains("Music") {
            try? await AppleScriptHelper.executeVoid("tell application \"Music\" to playpause")
        } else if bundleID == "com.spotify.client" || bundleID.contains("Spotify") {
            try? await AppleScriptHelper.executeVoid("tell application \"Spotify\" to playpause")
        } else {
            postMediaKeyEvent(for: 2)
        }
    }

    func nextTrack() async {
        MRMediaRemoteSendCommandFunction(4, nil)
        let bundleID = getEffectiveBundleID()
        if bundleID == "com.apple.Music" || bundleID.contains("Music") {
            try? await AppleScriptHelper.executeVoid("tell application \"Music\" to next track")
        } else if bundleID == "com.spotify.client" || bundleID.contains("Spotify") {
            try? await AppleScriptHelper.executeVoid("tell application \"Spotify\" to next track")
        } else {
            postMediaKeyEvent(for: 4)
        }
    }

    func previousTrack() async {
        MRMediaRemoteSendCommandFunction(5, nil)
        let bundleID = getEffectiveBundleID()
        if bundleID == "com.apple.Music" || bundleID.contains("Music") {
            try? await AppleScriptHelper.executeVoid("tell application \"Music\" to previous track")
        } else if bundleID == "com.spotify.client" || bundleID.contains("Spotify") {
            try? await AppleScriptHelper.executeVoid("tell application \"Spotify\" to previous track")
        } else {
            postMediaKeyEvent(for: 5)
        }
    }

    func seek(to time: Double) async {
        MRMediaRemoteSetElapsedTimeFunction(time)
        let bundleID = getEffectiveBundleID()
        if bundleID == "com.apple.Music" || bundleID.contains("Music") {
            Task {
                let script = "tell application \"Music\" to set player position to \(time)"
                try? await AppleScriptHelper.executeVoid(script)
            }
        } else if bundleID == "com.spotify.client" || bundleID.contains("Spotify") {
            Task {
                let script = "tell application \"Spotify\" to set player position to \(time)"
                try? await AppleScriptHelper.executeVoid(script)
            }
        }
    }

    func isActive() -> Bool {
        return true
    }
    
    func toggleShuffle() async {
        MRMediaRemoteSendCommandFunction(6, nil)
        let isShuffled = playbackState.isShuffled
        MRMediaRemoteSetShuffleModeFunction(isShuffled ? 1 : 3)
        let bundleID = getEffectiveBundleID()
        if bundleID == "com.apple.Music" || bundleID.contains("Music") {
            let script = "tell application \"Music\" to set shuffle enabled to (not shuffle enabled)"
            try? await AppleScriptHelper.executeVoid(script)
        } else if bundleID == "com.spotify.client" || bundleID.contains("Spotify") {
            let script = "tell application \"Spotify\" to set shuffling to (not shuffling)"
            try? await AppleScriptHelper.executeVoid(script)
        }
        playbackState.isShuffled.toggle()
    }
    
    func toggleRepeat() async {
        MRMediaRemoteSendCommandFunction(7, nil)
        let newRepeatMode = (playbackState.repeatMode == .off) ? 3 : (playbackState.repeatMode.rawValue - 1)
        playbackState.repeatMode = RepeatMode(rawValue: newRepeatMode) ?? .off
        MRMediaRemoteSetRepeatModeFunction(newRepeatMode)
        let bundleID = getEffectiveBundleID()
        if bundleID == "com.apple.Music" || bundleID.contains("Music") {
            let script = """
            tell application "Music"
                if song repeat is off then
                    set song repeat to all
                else if song repeat is all then
                    set song repeat to one
                else
                    set song repeat to off
                end if
            end tell
            """
            try? await AppleScriptHelper.executeVoid(script)
        } else if bundleID == "com.spotify.client" || bundleID.contains("Spotify") {
            let script = "tell application \"Spotify\" to set repeating to (not repeating)"
            try? await AppleScriptHelper.executeVoid(script)
        }
    }
    
    func setVolume(_ level: Double) async {
        let clampedLevel = max(0.0, min(1.0, level))
        let volumePercentage = Int(clampedLevel * 100)
        
        let bundleID = getEffectiveBundleID()
        if bundleID == "com.apple.Music" || bundleID.contains("Music") {
            let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music")
            if !runningApps.isEmpty {
                let script = "tell application \"Music\" to set sound volume to \(volumePercentage)"
                try? await AppleScriptHelper.executeVoid(script)
            }
        } else if bundleID == "com.spotify.client" || bundleID.contains("Spotify") {
            let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client")
            if !runningApps.isEmpty {
                let script = "tell application \"Spotify\" to set sound volume to \(volumePercentage)"
                try? await AppleScriptHelper.executeVoid(script)
            }
        } else {
            await MainActor.run {
                VolumeManager.shared.setAbsolute(Float32(clampedLevel))
            }
        }
        
        playbackState.volume = clampedLevel
    }
    
    // MARK: - Setup Methods
    private func setupNowPlayingObserver() async {
        if let oldPipe = self.pipeHandler {
            await oldPipe.close()
            self.pipeHandler = nil
        }
        if let oldProc = self.process, oldProc.isRunning {
            oldProc.interrupt()
            oldProc.terminate()
            self.process = nil
        }

        let process = Process()
        let scriptPath = Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl")?.path ??
            Bundle.main.resourcePath.map({ $0 + "/mediaremote-adapter.pl" })
        let frameworkPath = Bundle.main.privateFrameworksPath?.appending("/MediaRemoteAdapter.framework") ??
            Bundle.main.resourcePath.map({ $0 + "/../Frameworks/MediaRemoteAdapter.framework" })
        
        guard let script = scriptPath, let framework = frameworkPath,
              FileManager.default.fileExists(atPath: script),
              FileManager.default.fileExists(atPath: framework)
        else {
            NSLog("NowPlayingController: Could not find mediaremote-adapter.pl script or framework path")
            return
        }
        
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [script, framework, "stream"]
        
        let pipeHandler = JSONLinesPipeHandler()
        process.standardOutput = await pipeHandler.getPipe()
        
        self.process = process
        self.pipeHandler = pipeHandler

        do {
            try process.run()
            streamTask = Task { [weak self] in
                await self?.processJSONStream()
            }
        } catch {
            NSLog("NowPlayingController: Failed to launch mediaremote-adapter.pl: \(error)")
        }
    }

    // MARK: - Async Stream Processing
    private func processJSONStream() async {
        guard let pipeHandler = self.pipeHandler else { return }
        
        await pipeHandler.readJSONLines(as: NowPlayingUpdate.self) { [weak self] update in
            await self?.handleAdapterUpdate(update)
        }
        
        // Auto-reconnect if process exited unexpectedly
        if !Task.isCancelled && self.process != nil {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled && self.process != nil else { return }
            await self.setupNowPlayingObserver()
        }
    }

    // MARK: - Update Methods
    private func handleAdapterUpdate(_ update: NowPlayingUpdate) async {
        let payload = update.payload
        let diff = update.diff ?? false

        var newPlaybackState = PlaybackState(bundleIdentifier: playbackState.bundleIdentifier)
        
        newPlaybackState.title = payload.title ?? (diff ? self.playbackState.title : "")
        newPlaybackState.artist = payload.artist ?? (diff ? self.playbackState.artist : "")
        newPlaybackState.album = payload.album ?? (diff ? self.playbackState.album : "")
        newPlaybackState.duration = payload.duration ?? (diff ? self.playbackState.duration : 0)
        
        if let elapsedTime = payload.elapsedTime {
            newPlaybackState.currentTime = elapsedTime
        } else if diff {
            if payload.playing == false {
                let timeSinceLastUpdate = Date().timeIntervalSince(self.playbackState.lastUpdated)
                newPlaybackState.currentTime = self.playbackState.currentTime + (self.playbackState.playbackRate * timeSinceLastUpdate)
            } else {
                newPlaybackState.currentTime = self.playbackState.currentTime
            }
        } else {
            newPlaybackState.currentTime = 0
        }

        
        if let shuffleMode = payload.shuffleMode {
            newPlaybackState.isShuffled = shuffleMode != 1
        } else if !diff {
            newPlaybackState.isShuffled = false
        } else {
            newPlaybackState.isShuffled = self.playbackState.isShuffled
        }
        if let repeatModeValue = payload.repeatMode {
            newPlaybackState.repeatMode = RepeatMode(rawValue: repeatModeValue) ?? .off
        } else if !diff {
            newPlaybackState.repeatMode = .off
        } else {
            newPlaybackState.repeatMode = self.playbackState.repeatMode
        }

        if let artworkDataString = payload.artworkData, !artworkDataString.isEmpty {
            let trackChanged = (newPlaybackState.title != self.playbackState.title) || (newPlaybackState.artist != self.playbackState.artist)
            if trackChanged || self.playbackState.artwork == nil {
                newPlaybackState.artwork = Data(
                    base64Encoded: artworkDataString.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            } else {
                newPlaybackState.artwork = self.playbackState.artwork
            }
        } else if !diff {
            newPlaybackState.artwork = nil
        } else {
            newPlaybackState.artwork = self.playbackState.artwork
        }

        if let dateString = payload.timestamp,
           let date = ISO8601DateFormatter().date(from: dateString) {
            newPlaybackState.lastUpdated = date
        } else if !diff {
            newPlaybackState.lastUpdated = Date()
        } else {
            newPlaybackState.lastUpdated = self.playbackState.lastUpdated
        }

        newPlaybackState.playbackRate = payload.playbackRate ?? (diff ? self.playbackState.playbackRate : 1.0)
        newPlaybackState.isPlaying = payload.playing ?? (diff ? self.playbackState.isPlaying : false)
        newPlaybackState.bundleIdentifier = (
            payload.parentApplicationBundleIdentifier ??
            payload.bundleIdentifier ??
            (diff ? self.playbackState.bundleIdentifier : "")
        )
        
        newPlaybackState.volume = payload.volume ?? self.playbackState.volume
        
        self.playbackState = newPlaybackState
        
        // Fetch favorite state for supported apps asynchronously
        // await fetchFavoriteStateIfSupported()
    }
    
     private func fetchFavoriteStateIfSupported() async {
         let bundleID = playbackState.bundleIdentifier
        
         if bundleID == "com.apple.Music" {
             let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music")
             guard !runningApps.isEmpty else { return }
             
             let script = """
             tell application "Music"
                 try
                     return favorited of current track
                 on error
                     return false
                 end try
             end tell
             """
             if let result = try? await AppleScriptHelper.execute(script) {
                 var updated = self.playbackState
                 updated.isFavorite = result.booleanValue
                 self.playbackState = updated
             }
         }
     }
    
}

struct NowPlayingUpdate: Codable {
    let payload: NowPlayingPayload
    let diff: Bool?
}

struct NowPlayingPayload: Codable {
    let title: String?
    let artist: String?
    let album: String?
    let duration: Double?
    let elapsedTime: Double?
    let shuffleMode: Int?
    let repeatMode: Int?
    let artworkData: String?
    let timestamp: String?
    let playbackRate: Double?
    let playing: Bool?
    let parentApplicationBundleIdentifier: String?
    let bundleIdentifier: String?
    let volume: Double?
}

actor JSONLinesPipeHandler {
    private let pipe: Pipe
    private let fileHandle: FileHandle
    private var buffer = ""
    
    init() {
        self.pipe = Pipe()
        self.fileHandle = pipe.fileHandleForReading
    }
    
    func getPipe() -> Pipe {
        return pipe
    }
    
    func readJSONLines<T: Decodable>(as type: T.Type, onLine: @escaping (T) async -> Void) async {
        do {
            try await self.processLines(as: type) { decodedObject in
                await onLine(decodedObject)
            }
        } catch {
            print("Error processing JSON stream: \(error)")
        }
    }
    
    private func processLines<T: Decodable>(as type: T.Type, onLine: @escaping (T) async -> Void) async throws {
        while true {
            let data = try await readData()
            guard !data.isEmpty else { break }
            
            if let chunk = String(data: data, encoding: .utf8) {
                buffer.append(chunk)
                
                while let range = buffer.range(of: "\n") {
                    let line = String(buffer[..<range.lowerBound])
                    buffer = String(buffer[range.upperBound...])
                    
                    if !line.isEmpty {
                        await processJSONLine(line, as: type, onLine: onLine)
                    }
                }
                
                if buffer.count > 5_000_000 {
                    buffer = ""
                }
            }
        }
    }
    
    private func processJSONLine<T: Decodable>(_ line: String, as type: T.Type, onLine: @escaping (T) async -> Void) async {
        guard let data = line.data(using: .utf8) else {
            return
        }
        do {
            let decodedObject = try JSONDecoder().decode(T.self, from: data)
            await onLine(decodedObject)
        } catch {
            // Ignore lines that can't be decoded
        }
    }
    
    private func readData() async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            
            fileHandle.readabilityHandler = { handle in
                let data = handle.availableData
                handle.readabilityHandler = nil
                continuation.resume(returning: data)
            }
        }
    }
    
    func close() async {
        do {
            fileHandle.readabilityHandler = nil
            try fileHandle.close()
            try pipe.fileHandleForWriting.close()
        } catch {
            print("Error closing pipe handler: \(error)")
        }
    }
}
