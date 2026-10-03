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
        return bundleID == "com.apple.Music" || bundleID == "com.spotify.client" || isBrowser(bundleID)
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

        Task { await setupNowPlayingObserver() }
    }

    deinit {
        streamTask?.cancel()
        
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

    // MARK: - Adapter Execution & Control Helpers
    private var adapterPaths: (scriptPath: String, frameworkPath: String, helperPath: String)? {
        let script = Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl")?.path ??
            (Bundle.main.resourcePath.map { $0 + "/mediaremote-adapter.pl" })
        let helper = Bundle.main.url(forResource: "MediaRemoteAdapterTestClient", withExtension: nil)?.path ??
            (Bundle.main.resourcePath.map { $0 + "/MediaRemoteAdapterTestClient" })
        let framework = Bundle.main.privateFrameworksPath?.appending("/MediaRemoteAdapter.framework") ??
            (Bundle.main.resourcePath.map { $0 + "/../Frameworks/MediaRemoteAdapter.framework" })
        
        if let script = script, let framework = framework, let helper = helper,
           FileManager.default.fileExists(atPath: script),
           FileManager.default.fileExists(atPath: framework),
           FileManager.default.fileExists(atPath: helper) {
            return (script, framework, helper)
        }
        return nil
    }

    private func executeAdapter(action: String, args: [String]) {
        guard let paths = adapterPaths else { return }
        DispatchQueue.global(qos: .userInteractive).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
            process.arguments = [paths.scriptPath, paths.frameworkPath, paths.helperPath, action] + args
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                print("NowPlayingController: executeAdapter failed: \(error)")
            }
        }
    }

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

    private func sendMediaRemoteCommand(_ command: Int) {
        if adapterPaths != nil {
            executeAdapter(action: "send", args: ["\(command)"])
        } else {
            MRMediaRemoteSendCommandFunction(command, nil)
        }
    }

    // MARK: - Browser Media Automation
    private enum BrowserMediaAction {
        case next
        case previous
        case togglePlay
        case toggleRepeat
        case seek(Double)
        case setVolume(Double)
    }

    private func isBrowser(_ bundleID: String) -> Bool {
        return getBrowserAppName(for: bundleID) != nil
    }

    private func getBrowserAppName(for bundleID: String) -> String? {
        switch bundleID {
        case "company.thebrowser.Browser": return "Arc"
        case "com.google.Chrome": return "Google Chrome"
        case "com.google.Chrome.canary": return "Google Chrome Canary"
        case "com.brave.Browser": return "Brave Browser"
        case "com.microsoft.edgemac": return "Microsoft Edge"
        case "com.operasoftware.Opera": return "Opera"
        case "com.vivaldi.Vivaldi": return "Vivaldi"
        default: return nil
        }
    }

    private func executeBrowserScript(for action: BrowserMediaAction) async {
        let bundleID = playbackState.bundleIdentifier
        guard let appName = getBrowserAppName(for: bundleID) else { return }

        let js: String
        switch action {
        case .next:
            js = """
            (function() {
                var btn = document.querySelector('.ytp-next-button, a.ytp-next-button, .skipControl__next, [aria-label*=\"Next\" i], [title*=\"Next\" i]');
                if (btn) { btn.click(); return 'clicked'; }
                var v = document.querySelector('video, audio');
                if (v) { v.currentTime = v.duration || (v.currentTime + 30); return 'seeked_end'; }
                return 'not_found';
            })()
            """
        case .previous:
            js = """
            (function() {
                var btn = document.querySelector('.ytp-prev-button, a.ytp-prev-button, .skipControl__previous, [aria-label*=\"Previous\" i], [title*=\"Previous\" i]');
                if (btn && btn.getAttribute('aria-disabled') !== 'true') { btn.click(); return 'clicked'; }
                var v = document.querySelector('video, audio');
                if (v) {
                    if (v.currentTime > 3) { v.currentTime = 0; }
                    else if (window.history.length > 1) { window.history.back(); }
                    return 'rewound';
                }
                return 'not_found';
            })()
            """
        case .togglePlay:
            js = """
            (function() {
                var btn = document.querySelector('.ytp-play-button, .playControl, [aria-label*=\"Play\" i], [aria-label*=\"Pause\" i]');
                if (btn) { btn.click(); return 'clicked'; }
                var v = document.querySelector('video, audio');
                if (v) { if (v.paused) { v.play(); } else { v.pause(); } return 'toggled'; }
                return 'not_found';
            })()
            """
        case .toggleRepeat:
            js = """
            (function() {
                var ytmBtn = document.querySelector('tp-yt-paper-icon-button.repeat, button[aria-label*=\"Repeat\" i], .repeat[role=\"button\"]');
                if (ytmBtn) { ytmBtn.click(); return 'clicked_ytm_repeat'; }
                var spotBtn = document.querySelector('[data-testid=\"control-button-repeat\"]');
                if (spotBtn) { spotBtn.click(); return 'clicked_spotify_repeat'; }
                var ytPlaylistBtn = document.querySelector('.ytp-repeat-button, button[aria-label*=\"Repeat playlist\" i]');
                if (ytPlaylistBtn) { ytPlaylistBtn.click(); return 'clicked_yt_playlist_repeat'; }
                var v = document.querySelector('video, audio');
                if (v) { v.loop = !v.loop; return v.loop ? 'loop_on' : 'loop_off'; }
                return 'not_found';
            })()
            """
        case .seek(let time):
            js = """
            (function() {
                var v = document.querySelector('video, audio');
                if (v) { v.currentTime = \(time); return 'seeked'; }
                return 'not_found';
            })()
            """
        case .setVolume(let level):
            js = """
            (function() {
                var v = document.querySelector('video, audio');
                if (v) { v.volume = \(level); return 'volumed'; }
                return 'not_found';
            })()
            """
        }

        let escapedJS = js.replacingOccurrences(of: "\\", with: "\\\\")
                          .replacingOccurrences(of: "\"", with: "\\\"")
                          .replacingOccurrences(of: "\n", with: " ")

        let appleScript = """
        tell application "\(appName)"
            repeat with w in windows
                repeat with t in tabs of w
                    set tabURL to URL of t
                    if tabURL contains "youtube.com" or tabURL contains "soundcloud.com" or tabURL contains "bilibili.com" or tabURL contains "netflix.com" or tabURL contains "spotify.com" then
                        tell t to execute javascript "\(escapedJS)"
                        return
                    end if
                end repeat
            end repeat
            try
                tell active tab of front window to execute javascript "\(escapedJS)"
            end try
        end tell
        """

        try? await AppleScriptHelper.executeVoid(appleScript)
    }

    // MARK: - Protocol Implementation
    func play() async {
        sendMediaRemoteCommand(0)
        let bundleID = playbackState.bundleIdentifier
        if bundleID == "com.apple.Music" {
            try? await AppleScriptHelper.executeVoid("tell application \"Music\" to play")
        } else if bundleID == "com.spotify.client" {
            try? await AppleScriptHelper.executeVoid("tell application \"Spotify\" to play")
        }
    }

    func pause() async {
        sendMediaRemoteCommand(1)
        let bundleID = playbackState.bundleIdentifier
        if bundleID == "com.apple.Music" {
            try? await AppleScriptHelper.executeVoid("tell application \"Music\" to pause")
        } else if bundleID == "com.spotify.client" {
            try? await AppleScriptHelper.executeVoid("tell application \"Spotify\" to pause")
        }
    }

    func togglePlay() async {
        sendMediaRemoteCommand(2)
        let bundleID = playbackState.bundleIdentifier
        if bundleID == "com.apple.Music" {
            try? await AppleScriptHelper.executeVoid("tell application \"Music\" to playpause")
        } else if bundleID == "com.spotify.client" {
            try? await AppleScriptHelper.executeVoid("tell application \"Spotify\" to playpause")
        }
    }

    func nextTrack() async {
        sendMediaRemoteCommand(4)
        let bundleID = playbackState.bundleIdentifier
        if bundleID == "com.apple.Music" {
            try? await AppleScriptHelper.executeVoid("tell application \"Music\" to next track")
        } else if bundleID == "com.spotify.client" {
            try? await AppleScriptHelper.executeVoid("tell application \"Spotify\" to next track")
        } else if isBrowser(bundleID) {
            await executeBrowserScript(for: .next)
        } else {
            postMediaKeyEvent(for: 4)
        }
    }

    func previousTrack() async {
        sendMediaRemoteCommand(5)
        let bundleID = playbackState.bundleIdentifier
        if bundleID == "com.apple.Music" {
            try? await AppleScriptHelper.executeVoid("tell application \"Music\" to previous track")
        } else if bundleID == "com.spotify.client" {
            try? await AppleScriptHelper.executeVoid("tell application \"Spotify\" to previous track")
        } else if isBrowser(bundleID) {
            await executeBrowserScript(for: .previous)
        } else {
            postMediaKeyEvent(for: 5)
        }
    }

    func seek(to time: Double) async {
        MRMediaRemoteSetElapsedTimeFunction(time)
        executeAdapter(action: "seek", args: ["\(Int(time * 1_000_000))"])
        
        let bundleID = playbackState.bundleIdentifier
        if bundleID == "com.apple.Music" {
            Task {
                let script = "tell application \"Music\" to set player position to \(time)"
                try? await AppleScriptHelper.executeVoid(script)
            }
        } else if bundleID == "com.spotify.client" {
            Task {
                let script = "tell application \"Spotify\" to set player position to \(time)"
                try? await AppleScriptHelper.executeVoid(script)
            }
        } else if isBrowser(bundleID) {
            await executeBrowserScript(for: .seek(time))
        }
    }

    func isActive() -> Bool {
        return true
    }
    
    func toggleShuffle() async {
        let isShuffled = playbackState.isShuffled
        let targetShuffleMode = isShuffled ? 1 : 3
        MRMediaRemoteSendCommandFunction(6, nil)
        MRMediaRemoteSetShuffleModeFunction(targetShuffleMode)
        executeAdapter(action: "shuffle", args: ["\(targetShuffleMode)"])
        
        let bundleID = playbackState.bundleIdentifier
        if bundleID == "com.apple.Music" {
            let script = "tell application \"Music\" to set shuffle enabled to (not shuffle enabled)"
            try? await AppleScriptHelper.executeVoid(script)
        } else if bundleID == "com.spotify.client" {
            let script = "tell application \"Spotify\" to set shuffling to (not shuffling)"
            try? await AppleScriptHelper.executeVoid(script)
        }
        playbackState.isShuffled.toggle()
    }
    
    func toggleRepeat() async {
        let nextMode: RepeatMode
        switch playbackState.repeatMode {
        case .off:
            nextMode = .all
        case .all:
            nextMode = .one
        case .one:
            nextMode = .off
        }
        playbackState.repeatMode = nextMode
        
        let targetValue = nextMode.rawValue
        MRMediaRemoteSendCommandFunction(7, nil)
        MRMediaRemoteSetRepeatModeFunction(targetValue)
        executeAdapter(action: "repeat", args: ["\(targetValue)"])
        
        let bundleID = playbackState.bundleIdentifier
        if bundleID == "com.apple.Music" {
            let script: String
            switch nextMode {
            case .off:
                script = "tell application \"Music\" to set song repeat to off"
            case .one:
                script = "tell application \"Music\" to set song repeat to one"
            case .all:
                script = "tell application \"Music\" to set song repeat to all"
            }
            try? await AppleScriptHelper.executeVoid(script)
        } else if bundleID == "com.spotify.client" {
            let script = "tell application \"Spotify\" to set repeating to (not repeating)"
            try? await AppleScriptHelper.executeVoid(script)
        } else if isBrowser(bundleID) {
            await executeBrowserScript(for: .toggleRepeat)
        }
    }
    
    func setVolume(_ level: Double) async {
        let clampedLevel = max(0.0, min(1.0, level))
        let volumePercentage = Int(clampedLevel * 100)
        
        let bundleID = playbackState.bundleIdentifier
        if bundleID == "com.apple.Music" {
            let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music")
            if !runningApps.isEmpty {
                let script = "tell application \"Music\" to set sound volume to \(volumePercentage)"
                try? await AppleScriptHelper.executeVoid(script)
            }
        } else if bundleID == "com.spotify.client" {
            let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client")
            if !runningApps.isEmpty {
                let script = "tell application \"Spotify\" to set sound volume to \(volumePercentage)"
                try? await AppleScriptHelper.executeVoid(script)
            }
        } else if isBrowser(bundleID) {
            await executeBrowserScript(for: .setVolume(clampedLevel))
        } else {
            await MainActor.run {
                VolumeManager.shared.setAbsolute(Float32(clampedLevel))
            }
        }
        
        playbackState.volume = clampedLevel
    }
    
    // MARK: - Setup Methods
    private func setupNowPlayingObserver() async {
        let process = Process()
        guard let paths = adapterPaths else {
            assertionFailure("Could not find mediaremote-adapter.pl script or framework path")
            return
        }
        
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [paths.scriptPath, paths.frameworkPath, paths.helperPath, "stream", "--debounce=100"]
        
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
            assertionFailure("Failed to launch mediaremote-adapter.pl: \(error)")
        }
    }

    // MARK: - Async Stream Processing
    private func processJSONStream() async {
        guard let pipeHandler = self.pipeHandler else { return }
        
        await pipeHandler.readJSONLines(as: NowPlayingUpdate.self) { [weak self] update in
            await self?.handleAdapterUpdate(update)
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
        if let repeatModeValue = payload.repeatMode, repeatModeValue > 0 {
            newPlaybackState.repeatMode = RepeatMode(rawValue: repeatModeValue) ?? .off
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
        
        newPlaybackState.volume = payload.volume ?? (diff ? self.playbackState.volume : 0.5)
        
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
