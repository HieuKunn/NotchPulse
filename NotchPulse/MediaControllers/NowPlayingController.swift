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
        let browserBundleIDs = [
            "company.thebrowser.Browser",
            "com.google.Chrome",
            "com.google.Chrome.canary",
            "com.brave.Browser",
            "com.microsoft.edgemac",
            "com.apple.Safari",
            "com.operasoftware.Opera",
            "com.vivaldi.Vivaldi"
        ]
        for id in browserBundleIDs {
            if !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty {
                return id
            }
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

    // MARK: - Browser Media Automation
    private enum BrowserMediaAction {
        case next
        case previous
        case toggleRepeat
        case toggleShuffle
        case seek(Double)
        case setVolume(Double)
    }

    private func isBrowser(_ bundleID: String) -> Bool {
        return getBrowserAppName(for: bundleID) != nil
    }

    private func getBrowserAppName(for bundleID: String) -> (name: String, isSafari: Bool)? {
        switch bundleID {
        case "company.thebrowser.Browser":
            return ("Arc", false)
        case "com.google.Chrome":
            return ("Google Chrome", false)
        case "com.google.Chrome.canary":
            return ("Google Chrome Canary", false)
        case "com.google.Chrome.beta":
            return ("Google Chrome Beta", false)
        case "com.google.Chrome.dev":
            return ("Google Chrome Dev", false)
        case "com.brave.Browser":
            return ("Brave Browser", false)
        case "com.brave.Browser.nightly":
            return ("Brave Browser Nightly", false)
        case "com.microsoft.edgemac":
            return ("Microsoft Edge", false)
        case "com.microsoft.edgemac.Canary":
            return ("Microsoft Edge Canary", false)
        case "com.microsoft.edgemac.Dev":
            return ("Microsoft Edge Dev", false)
        case "com.microsoft.edgemac.Beta":
            return ("Microsoft Edge Beta", false)
        case "com.operasoftware.Opera":
            return ("Opera", false)
        case "com.operasoftware.OperaGX":
            return ("Opera GX", false)
        case "com.vivaldi.Vivaldi":
            return ("Vivaldi", false)
        case "org.chromium.Chromium":
            return ("Chromium", false)
        case "com.apple.Safari":
            return ("Safari", true)
        case "com.apple.SafariTechnologyPreview":
            return ("Safari Technology Preview", true)
        case "com.kagi.kagisafari":
            return ("Orion", true)
        default:
            let lower = bundleID.lowercased()
            if lower.contains("arc") || lower.contains("thebrowser") {
                return ("Arc", false)
            } else if lower.contains("chrome") {
                return ("Google Chrome", false)
            } else if lower.contains("brave") {
                return ("Brave Browser", false)
            } else if lower.contains("edge") {
                return ("Microsoft Edge", false)
            } else if lower.contains("safari") {
                return ("Safari", true)
            } else if lower.contains("opera") {
                return ("Opera", false)
            } else if lower.contains("vivaldi") {
                return ("Vivaldi", false)
            } else if lower.contains("chromium") {
                return ("Chromium", false)
            } else if lower.contains("orion") {
                return ("Orion", true)
            }
            return nil
        }
    }

    @discardableResult
    private func executeBrowserScript(for action: BrowserMediaAction) async -> Bool {
        let bundleID = getEffectiveBundleID()
        guard let (appName, isSafari) = getBrowserAppName(for: bundleID) else {
            return false
        }

        let js: String
        switch action {
        case .next:
            js = """
            (function() {
                var nextBtn = document.querySelector('.ytp-next-button, a.ytp-next-button, tp-yt-paper-icon-button.next-button, button.next-button, [data-testid="control-button-skip-forward"], .skipControl__next, [aria-label*="Next" i], [aria-label*="Tiếp" i], [title*="Next" i], [title*="Tiếp" i]');
                if (nextBtn && nextBtn.getAttribute('aria-disabled') !== 'true') {
                    nextBtn.click();
                    return 'clicked_next_btn';
                }
                var evt = new KeyboardEvent('keydown', { key: 'N', code: 'KeyN', keyCode: 78, which: 78, shiftKey: true, bubbles: true });
                document.dispatchEvent(evt);
                return 'dispatched_key';
            })()
            """
        case .previous:
            js = """
            (function() {
                var prevBtn = document.querySelector('.ytp-prev-button, a.ytp-prev-button, tp-yt-paper-icon-button.previous-button, button.previous-button, [data-testid="control-button-skip-back"], .skipControl__previous, [aria-label*="Previous" i], [aria-label*="Trước" i], [title*="Previous" i], [title*="Trước" i]');
                if (prevBtn && prevBtn.getAttribute('aria-disabled') !== 'true') {
                    prevBtn.click();
                    return 'clicked_prev_btn';
                }
                var v = document.querySelector('video, audio');
                if (v && v.currentTime > 3) {
                    v.currentTime = 0;
                    return 'rewound_start';
                }
                var evt = new KeyboardEvent('keydown', { key: 'P', code: 'KeyP', keyCode: 80, which: 80, shiftKey: true, bubbles: true });
                document.dispatchEvent(evt);
                if (window.history.length > 1) {
                    window.history.back();
                    return 'history_back';
                }
                if (v) {
                    v.currentTime = 0;
                    return 'rewound';
                }
                return 'not_found';
            })()
            """
        case .toggleRepeat:
            js = """
            (function() {
                var ytmBtn = document.querySelector('tp-yt-paper-icon-button.repeat, button[aria-label*="Repeat" i], .repeat[role="button"]');
                if (ytmBtn) { ytmBtn.click(); return 'clicked_ytm_repeat'; }
                var spotBtn = document.querySelector('[data-testid="control-button-repeat"]');
                if (spotBtn) { spotBtn.click(); return 'clicked_spotify_repeat'; }
                var ytPlaylistBtn = document.querySelector('.ytp-repeat-button, button[aria-label*="Repeat playlist" i]');
                if (ytPlaylistBtn) { ytPlaylistBtn.click(); return 'clicked_yt_playlist_repeat'; }
                var v = document.querySelector('video, audio');
                if (v) { v.loop = !v.loop; return v.loop ? 'loop_on' : 'loop_off'; }
                return 'not_found';
            })()
            """
        case .toggleShuffle:
            js = """
            (function() {
                var ytmShuffle = document.querySelector('tp-yt-paper-icon-button.shuffle, button[aria-label*="Shuffle" i], .shuffle[role="button"]');
                if (ytmShuffle) { ytmShuffle.click(); return 'clicked_ytm_shuffle'; }
                var spotShuffle = document.querySelector('[data-testid="control-button-shuffle"], button[aria-label*="Shuffle" i]');
                if (spotShuffle) { spotShuffle.click(); return 'clicked_spotify_shuffle'; }
                return 'not_found';
            })()
            """
        case .seek(let time):
            js = """
            (function() {
                var v = document.querySelector('video, audio');
                if (v) {
                    v.currentTime = \(time);
                    return 'seeked';
                }
                return 'not_found';
            })()
            """
        case .setVolume(let level):
            let clamped = max(0.0, min(1.0, level))
            js = """
            (function() {
                var v = document.querySelector('video, audio');
                if (v) {
                    v.volume = \(clamped);
                    return 'volumed';
                }
                return 'not_found';
            })()
            """
        }

        let escapedJS = js
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")

        let appleScript: String
        if isSafari {
            appleScript = """
            tell application "\(appName)"
                set targetTab to missing value
                set fallbackTab to missing value
                repeat with w in windows
                    repeat with t in tabs of w
                        set u to (URL of t as text)
                        if u contains "youtube.com" or u contains "soundcloud.com" or u contains "spotify.com" or u contains "bilibili.com" or u contains "netflix.com" or u contains "music.youtube.com" or u contains "vimeo.com" or u contains "twitch.tv" or u contains "tiktok.com" or u contains "facebook.com" then
                            try
                                set ms to (do JavaScript "(function(){ var v = document.querySelector('video, audio'); if (!v) return 'none'; return (!v.paused ? 'playing' : (v.currentTime > 0 ? 'paused_progress' : 'idle')); })()" in t)
                                if ms contains "playing" then
                                    set targetTab to t
                                    exit repeat
                                else if ms contains "paused_progress" and fallbackTab is missing value then
                                    set fallbackTab to t
                                else if fallbackTab is missing value then
                                    set fallbackTab to t
                                end if
                            end try
                        end if
                    end repeat
                    if targetTab is not missing value then exit repeat
                end repeat
                if targetTab is missing value and fallbackTab is not missing value then
                    set targetTab to fallbackTab
                end if
                if targetTab is missing value then
                    try
                        set targetTab to current tab of front window
                    end try
                end if
                if targetTab is not missing value then
                    return (do JavaScript "\(escapedJS)" in targetTab)
                end if
                return "no_tab"
            end tell
            """
        } else {
            appleScript = """
            tell application "\(appName)"
                set targetTab to missing value
                set fallbackTab to missing value
                repeat with w in windows
                    repeat with t in tabs of w
                        set u to (URL of t as text)
                        if u contains "youtube.com" or u contains "soundcloud.com" or u contains "spotify.com" or u contains "bilibili.com" or u contains "netflix.com" or u contains "music.youtube.com" or u contains "vimeo.com" or u contains "twitch.tv" or u contains "tiktok.com" or u contains "facebook.com" then
                            try
                                tell t
                                    set ms to execute javascript "(function(){ var v = document.querySelector('video, audio'); if (!v) return 'none'; return (!v.paused ? 'playing' : (v.currentTime > 0 ? 'paused_progress' : 'idle')); })()"
                                end tell
                                if ms contains "playing" then
                                    set targetTab to t
                                    exit repeat
                                else if ms contains "paused_progress" and fallbackTab is missing value then
                                    set fallbackTab to t
                                else if fallbackTab is missing value then
                                    set fallbackTab to t
                                end if
                            end try
                        end if
                    end repeat
                    if targetTab is not missing value then exit repeat
                end repeat
                if targetTab is missing value and fallbackTab is not missing value then
                    set targetTab to fallbackTab
                end if
                if targetTab is missing value then
                    try
                        set targetTab to active tab of front window
                    end try
                end if
                if targetTab is not missing value then
                    tell targetTab
                        return execute javascript "\(escapedJS)"
                    end tell
                end if
                return "no_tab"
            end tell
            """
        }

        do {
            let result = try await AppleScriptHelper.execute(appleScript)
            let resStr = result?.stringValue ?? ""
            return !resStr.isEmpty && resStr != "no_tab" && resStr != "not_found"
        } catch {
            return false
        }
    }

    // MARK: - Protocol Implementation
    func play() async {
        MRMediaRemoteSendCommandFunction(0, nil)
    }

    func pause() async {
        MRMediaRemoteSendCommandFunction(1, nil)
    }

    func togglePlay() async {
        MRMediaRemoteSendCommandFunction(2, nil)
    }

    func nextTrack() async {
        let bundleID = getEffectiveBundleID()
        if isBrowser(bundleID) {
            let handled = await executeBrowserScript(for: .next)
            if !handled {
                MRMediaRemoteSendCommandFunction(4, nil)
            }
        } else {
            MRMediaRemoteSendCommandFunction(4, nil)
        }
    }

    func previousTrack() async {
        let bundleID = getEffectiveBundleID()
        if isBrowser(bundleID) {
            let handled = await executeBrowserScript(for: .previous)
            if !handled {
                MRMediaRemoteSendCommandFunction(5, nil)
            }
        } else {
            MRMediaRemoteSendCommandFunction(5, nil)
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
        } else if isBrowser(bundleID) {
            Task {
                await executeBrowserScript(for: .seek(time))
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
        } else if isBrowser(bundleID) {
            await executeBrowserScript(for: .toggleShuffle)
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
        } else if isBrowser(bundleID) {
            await executeBrowserScript(for: .toggleRepeat)
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
