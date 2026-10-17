import AppKit
import Combine
import Foundation

final class NowPlayingController: ObservableObject, MediaControllerProtocol {
    func updatePlaybackInfo() async {
        if let paths = Self.getAdapterPaths() {
            await fetchInitialNowPlayingInfo(paths: paths)
        }
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
        let bundleID = getEffectiveBundleID()
        return bundleID == "com.apple.Music" || bundleID.contains("Music") || isBrowser(bundleID)
    }

    func setFavorite(_ favorite: Bool) async {
        let bundleID = getEffectiveBundleID()
        
        if isBrowser(bundleID) {
            await executeBrowserScript(for: .toggleFavorite)
            playbackState.isFavorite.toggle()
        } else if bundleID == "com.apple.Music" || bundleID.contains("Music") {
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
    private var setupObserverTask: Task<Void, Never>?
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

        // Auto-reconnect adapter whenever Mac wakes from sleep if the process terminated
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(600))
                guard let self = self else { return }
                if self.process == nil || self.process?.isRunning == false {
                    await self.setupNowPlayingObserver()
                }
            }
        }

        setupObserverTask = Task { [weak self] in
            await self?.setupNowPlayingObserver()
        }
    }

    deinit {
        setupObserverTask?.cancel()
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
        if let mgrBid = MusicManager.shared.bundleIdentifier, !mgrBid.isEmpty {
            return mgrBid
        }
        let browserBundleIDs = [
            "app.zen-browser.zen",
            "company.thebrowser.Browser",
            "com.google.Chrome",
            "com.brave.Browser",
            "com.apple.Safari",
            "com.microsoft.edgemac",
            "org.mozilla.firefox"
        ]
        for id in browserBundleIDs {
            if !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty {
                return id
            }
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
    public static func postMediaKeyEvent(for command: Int) {
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
        case togglePlay
        case play
        case pause
        case next
        case previous
        case toggleRepeat(RepeatMode)
        case toggleShuffle
        case toggleFavorite
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
            } else if lower.contains("zen") || lower.contains("firefox") || lower.contains("mozilla") {
                // Zen Browser and Firefox do not support Chromium/Safari AppleScript tab scripting.
                // Returning nil allows MediaRemote / system media fallback to handle them cleanly.
                return nil
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
        case .togglePlay:
            js = """
            (function() {
                var ytBtn = document.querySelector('.html5-video-player .ytp-play-button, .ytp-play-button');
                if (ytBtn) { ytBtn.click(); return 'clicked_yt_playpause'; }
                var ytmBtn = document.querySelector('tp-yt-paper-icon-button#play-pause-button, #play-pause-button');
                if (ytmBtn) { ytmBtn.click(); return 'clicked_ytm_playpause'; }
                var spotBtn = document.querySelector('[data-testid="control-button-playpause"]');
                if (spotBtn) { spotBtn.click(); return 'clicked_spotify_playpause'; }
                var scBtn = document.querySelector('.playControl');
                if (scBtn) { scBtn.click(); return 'clicked_sc_playpause'; }
                var v = document.querySelector('video, audio');
                if (v) {
                    if (v.paused) { v.play(); } else { v.pause(); }
                    return 'toggled_video';
                }
                return 'not_found';
            })()
            """
        case .play:
            js = """
            (function() {
                var v = document.querySelector('video, audio');
                if (v && v.paused) {
                    v.play();
                    return 'played_video';
                }
                var ytBtn = document.querySelector('.html5-video-player .ytp-play-button[aria-label*="Play" i], .html5-video-player .ytp-play-button[aria-label*="Phát" i], .ytp-play-button');
                if (ytBtn) { ytBtn.click(); return 'clicked_play_btn'; }
                var spotBtn = document.querySelector('[data-testid="control-button-play"]');
                if (spotBtn) { spotBtn.click(); return 'clicked_play_btn'; }
                return 'noop';
            })()
            """
        case .pause:
            js = """
            (function() {
                var v = document.querySelector('video, audio');
                if (v && !v.paused) {
                    v.pause();
                    return 'paused_video';
                }
                var ytBtn = document.querySelector('.html5-video-player .ytp-play-button[aria-label*="Pause" i], .html5-video-player .ytp-play-button[aria-label*="Tạm dừng" i], .ytp-play-button');
                if (ytBtn) { ytBtn.click(); return 'clicked_pause_btn'; }
                var spotBtn = document.querySelector('[data-testid="control-button-pause"]');
                if (spotBtn) { spotBtn.click(); return 'clicked_pause_btn'; }
                return 'noop';
            })()
            """
        case .next:
            js = """
            (function() {
                var ytNext = document.querySelector('.html5-video-player a.ytp-next-button, .html5-video-player .ytp-next-button, a.ytp-next-button');
                if (ytNext && ytNext.getAttribute('aria-disabled') !== 'true') {
                    ytNext.click();
                    return 'clicked_yt_next';
                }
                var ytmNext = document.querySelector('tp-yt-paper-icon-button.next-button, #left-controls .next-button');
                if (ytmNext && ytmNext.getAttribute('aria-disabled') !== 'true') {
                    ytmNext.click();
                    return 'clicked_ytm_next';
                }
                var spotNext = document.querySelector('[data-testid="control-button-skip-forward"]');
                if (spotNext && spotNext.getAttribute('aria-disabled') !== 'true') {
                    spotNext.click();
                    return 'clicked_spotify_next';
                }
                var scNext = document.querySelector('.skipControl__next, [title="Skip to next"]');
                if (scNext && scNext.getAttribute('aria-disabled') !== 'true') {
                    scNext.click();
                    return 'clicked_sc_next';
                }
                var playerNext = document.querySelector('.player-controls button.next, .controls button.next, [data-testid*="next" i]');
                if (playerNext && playerNext.getAttribute('aria-disabled') !== 'true') {
                    playerNext.click();
                    return 'clicked_player_next';
                }
                if (ytNext && ytNext.href && ytNext.href !== window.location.href) {
                    window.location.href = ytNext.href;
                    return 'navigated_yt_next';
                }
                var v = document.querySelector('video, audio');
                if (v && v.duration && !isNaN(v.duration) && v.duration > 1) {
                    v.currentTime = v.duration - 0.2;
                    v.play();
                    return 'jumped_to_end';
                }
                return 'not_found';
            })()
            """
        case .previous:
            js = """
            (function() {
                var ytPrev = document.querySelector('.html5-video-player a.ytp-prev-button, .html5-video-player .ytp-prev-button, a.ytp-prev-button');
                if (ytPrev && ytPrev.getAttribute('aria-disabled') !== 'true') {
                    ytPrev.click();
                    return 'clicked_yt_prev';
                }
                var ytmPrev = document.querySelector('tp-yt-paper-icon-button.previous-button, #left-controls .previous-button');
                if (ytmPrev && ytmPrev.getAttribute('aria-disabled') !== 'true') {
                    ytmPrev.click();
                    return 'clicked_ytm_prev';
                }
                var spotPrev = document.querySelector('[data-testid="control-button-skip-back"]');
                if (spotPrev && spotPrev.getAttribute('aria-disabled') !== 'true') {
                    spotPrev.click();
                    return 'clicked_spotify_prev';
                }
                var scPrev = document.querySelector('.skipControl__previous, [title="Skip to previous"]');
                if (scPrev && scPrev.getAttribute('aria-disabled') !== 'true') {
                    scPrev.click();
                    return 'clicked_sc_prev';
                }
                var playerPrev = document.querySelector('.player-controls button.prev, .controls button.prev, [data-testid*="prev" i]');
                if (playerPrev && playerPrev.getAttribute('aria-disabled') !== 'true') {
                    playerPrev.click();
                    return 'clicked_player_prev';
                }
                if (ytPrev && ytPrev.href && ytPrev.href !== window.location.href) {
                    window.location.href = ytPrev.href;
                    return 'navigated_yt_prev';
                }
                if (window.history.length > 1) {
                    window.history.back();
                    return 'navigated_history_back';
                }
                var v = document.querySelector('video, audio');
                if (v) {
                    v.currentTime = 0;
                    v.play();
                    return 'rewound_to_start';
                }
                return 'not_found';
            })()
            """
        case .toggleRepeat(let targetMode):
            let isLoop = (targetMode != .off)
            js = """
            (function() {
                var ytmBtn = document.querySelector('tp-yt-paper-icon-button.repeat, #left-controls .repeat');
                if (ytmBtn) {
                    ytmBtn.click();
                    return 'clicked_ytm_repeat';
                }
                var spotBtn = document.querySelector('[data-testid="control-button-repeat"]');
                if (spotBtn) {
                    spotBtn.click();
                    return 'clicked_spotify_repeat';
                }
                var ytPlaylistBtn = document.querySelector('.ytp-playlist-repeat-button, .ytp-repeat-button');
                if (ytPlaylistBtn) {
                    ytPlaylistBtn.click();
                    return 'clicked_yt_playlist_repeat';
                }
                var scRepeat = document.querySelector('.repeatControl');
                if (scRepeat) {
                    scRepeat.click();
                    return 'clicked_sc_repeat';
                }
                var v = document.querySelector('video, audio');
                if (v) {
                    v.loop = \(isLoop);
                    return v.loop ? 'loop_on' : 'loop_off';
                }
                return 'not_found';
            })()
            """
        case .toggleShuffle:
            js = """
            (function() {
                var ytmShuffle = document.querySelector('tp-yt-paper-icon-button.shuffle, #left-controls .shuffle');
                if (ytmShuffle) { ytmShuffle.click(); return 'clicked_ytm_shuffle'; }
                var spotShuffle = document.querySelector('[data-testid="control-button-shuffle"]');
                if (spotShuffle) { spotShuffle.click(); return 'clicked_spotify_shuffle'; }
                var scShuffle = document.querySelector('.shuffleControl');
                if (scShuffle) { scShuffle.click(); return 'clicked_sc_shuffle'; }
                return 'not_found';
            })()
            """
        case .toggleFavorite:
            js = """
            (function() {
                var ytLike = document.querySelector('like-button-view-model button, #segmented-like-button button, ytm-like-button-renderer button');
                if (ytLike) { ytLike.click(); return 'clicked_yt_like'; }
                var ytmLike = document.querySelector('tp-yt-paper-icon-button.like, #like-button-renderer tp-yt-paper-icon-button');
                if (ytmLike) { ytmLike.click(); return 'clicked_ytm_like'; }
                var spotLike = document.querySelector('[data-testid="add-button"]');
                if (spotLike) { spotLike.click(); return 'clicked_spotify_like'; }
                var scLike = document.querySelector('.playbackSoundBadge__like, button[title*="Like" i]');
                if (scLike) { scLike.click(); return 'clicked_sc_like'; }
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
                    if (v.volume > 0 && v.muted) { v.muted = false; }
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
                try
                    set actTab to current tab of front window
                    set actRes to (do JavaScript "\(escapedJS)" in actTab)
                    if actRes is not missing value and actRes is not "" and actRes is not "not_found" and actRes is not "noop" then
                        return actRes
                    end if
                end try
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
                try
                    set actTab to active tab of front window
                    tell actTab
                        set actRes to execute javascript "\(escapedJS)"
                    end tell
                    if actRes is not missing value and actRes is not "" and actRes is not "not_found" and actRes is not "noop" then
                        return actRes
                    end if
                end try
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

    // MARK: - Adapter Command Execution
    
    /// Resolve path to bundled or local mediaremote-adapter.pl and MediaRemoteAdapter.framework
    public static func getAdapterPaths() -> (script: String, framework: String)? {
        var scriptPath = Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl")?.path
            ?? Bundle.main.resourcePath.map({ $0 + "/mediaremote-adapter.pl" })
        var frameworkPath = Bundle.main.privateFrameworksPath?.appending("/MediaRemoteAdapter.framework")
            ?? Bundle.main.resourcePath.map({ $0 + "/../Frameworks/MediaRemoteAdapter.framework" })
        
        let fm = FileManager.default
        
        if scriptPath == nil || !fm.fileExists(atPath: scriptPath!) {
            let candidates = [
                Bundle.main.bundleURL.appendingPathComponent("mediaremote-adapter/mediaremote-adapter.pl").path,
                Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("mediaremote-adapter/mediaremote-adapter.pl").path,
                Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("mediaremote-adapter/mediaremote-adapter.pl").path,
                Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("mediaremote-adapter/mediaremote-adapter.pl").path,
                "/Users/hieukunn/Learning ITM/My project/NotchPulse/mediaremote-adapter/mediaremote-adapter.pl"
            ]
            for c in candidates where fm.fileExists(atPath: c) {
                scriptPath = c
                break
            }
        }
        
        if frameworkPath == nil || !fm.fileExists(atPath: frameworkPath!) {
            let candidates = [
                Bundle.main.bundleURL.appendingPathComponent("mediaremote-adapter/MediaRemoteAdapter.framework").path,
                Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("mediaremote-adapter/MediaRemoteAdapter.framework").path,
                Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("mediaremote-adapter/MediaRemoteAdapter.framework").path,
                Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("mediaremote-adapter/MediaRemoteAdapter.framework").path,
                "/Users/hieukunn/Learning ITM/My project/NotchPulse/mediaremote-adapter/MediaRemoteAdapter.framework"
            ]
            for c in candidates where fm.fileExists(atPath: c) {
                frameworkPath = c
                break
            }
        }
        
        guard let s = scriptPath, let f = frameworkPath,
              fm.fileExists(atPath: s),
              fm.fileExists(atPath: f) else {
            return nil
        }
        return (s, f)
    }

    /// Dispatches a command to the mediaremote adapter perl process (running with necessary Mach connection)
    @discardableResult
    public static func sendUniversalCommand(_ command: String, arg: String? = nil) async -> Bool {
        guard let paths = getAdapterPaths() else {
            NSLog("NowPlayingController: Cannot send command \(command), adapter paths not found")
            return false
        }
        return await Task.detached(priority: .userInitiated) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
            var args = [paths.script, paths.framework, command]
            if let arg = arg {
                args.append(arg)
            }
            proc.arguments = args
            proc.standardOutput = Pipe()
            proc.standardError = Pipe()
            do {
                try proc.run()
                proc.waitUntilExit()
                return proc.terminationStatus == 0
            } catch {
                NSLog("NowPlayingController: Failed to run adapter command \(command): \(error)")
                return false
            }
        }.value
    }

    // MARK: - Protocol Implementation
    func play() async {
        if await Self.sendUniversalCommand("send", arg: "0") {
            return
        }
        let bundleID = getEffectiveBundleID()
        if bundleID == "com.apple.Music" {
            try? await AppleScriptHelper.executeVoid("tell application \"Music\" to play")
            return
        } else if bundleID == "com.spotify.client" {
            try? await AppleScriptHelper.executeVoid("tell application \"Spotify\" to play")
            return
        } else if isBrowser(bundleID) {
            let success = await executeBrowserScript(for: .play)
            if success {
                return
            }
        }
        Self.postMediaKeyEvent(for: 0)
    }

    func pause() async {
        if await Self.sendUniversalCommand("send", arg: "1") {
            return
        }
        let bundleID = getEffectiveBundleID()
        if bundleID == "com.apple.Music" {
            try? await AppleScriptHelper.executeVoid("tell application \"Music\" to pause")
            return
        } else if bundleID == "com.spotify.client" {
            try? await AppleScriptHelper.executeVoid("tell application \"Spotify\" to pause")
            return
        } else if isBrowser(bundleID) {
            let success = await executeBrowserScript(for: .pause)
            if success {
                return
            }
        }
        Self.postMediaKeyEvent(for: 1)
    }

    func togglePlay() async {
        // Universal MediaRemote toggle play/pause (command 2) via Mach adapter
        if await Self.sendUniversalCommand("send", arg: "2") {
            return
        }
        let bundleID = getEffectiveBundleID()
        if bundleID == "com.apple.Music" {
            try? await AppleScriptHelper.executeVoid("tell application \"Music\" to playpause")
            return
        } else if bundleID == "com.spotify.client" {
            try? await AppleScriptHelper.executeVoid("tell application \"Spotify\" to playpause")
            return
        } else if isBrowser(bundleID) {
            let success = await executeBrowserScript(for: .togglePlay)
            if success {
                return
            }
        }
        Self.postMediaKeyEvent(for: 2)
    }

    func nextTrack() async {
        let bundleID = getEffectiveBundleID()
        if bundleID == "com.apple.Music" {
            try? await AppleScriptHelper.executeVoid("tell application \"Music\" to next track")
            return
        } else if bundleID == "com.spotify.client" {
            try? await AppleScriptHelper.executeVoid("tell application \"Spotify\" to next track")
            return
        } else if isBrowser(bundleID) {
            let success = await executeBrowserScript(for: .next)
            if success {
                return
            }
        }
        // Universal MediaRemote next track (command 4) and hardware media key
        await Self.sendUniversalCommand("send", arg: "4")
        Self.postMediaKeyEvent(for: 4)
    }

    func previousTrack() async {
        let bundleID = getEffectiveBundleID()
        if bundleID == "com.apple.Music" {
            try? await AppleScriptHelper.executeVoid("tell application \"Music\" to previous track")
            return
        } else if bundleID == "com.spotify.client" {
            let script = """
            tell application "Spotify"
                set player position to 0
                previous track
            end tell
            """
            try? await AppleScriptHelper.executeVoid(script)
            return
        } else if isBrowser(bundleID) {
            let success = await executeBrowserScript(for: .previous)
            if success {
                return
            }
        }
        // Universal MediaRemote previous track (command 5) and hardware media key
        await Self.sendUniversalCommand("send", arg: "5")
        Self.postMediaKeyEvent(for: 5)
    }

    func seek(to time: Double) async {
        let micros = Int64(time * 1_000_000)
        if await Self.sendUniversalCommand("seek", arg: "\(micros)") {
            return
        }
        let bundleID = getEffectiveBundleID()
        if bundleID == "com.apple.Music" || bundleID.contains("Music") {
            let script = "tell application \"Music\" to set player position to \(time)"
            try? await AppleScriptHelper.executeVoid(script)
        } else if bundleID == "com.spotify.client" || bundleID.contains("Spotify") {
            let script = "tell application \"Spotify\" to set player position to \(time)"
            try? await AppleScriptHelper.executeVoid(script)
        }
    }

    func isActive() -> Bool {
        return true
    }
    
    func toggleShuffle() async {
        let isShuffled = playbackState.isShuffled
        let targetShuffleMode = isShuffled ? "1" : "3"
        if await Self.sendUniversalCommand("shuffle", arg: targetShuffleMode) {
            playbackState.isShuffled.toggle()
            return
        }
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
        let nextMode: RepeatMode
        let adapterRepeatMode: String
        switch playbackState.repeatMode {
        case .off:
            nextMode = .all
            adapterRepeatMode = "3"
        case .all:
            nextMode = .one
            adapterRepeatMode = "2"
        case .one:
            nextMode = .off
            adapterRepeatMode = "1"
        }
        if await Self.sendUniversalCommand("repeat", arg: adapterRepeatMode) {
            playbackState.repeatMode = nextMode
            return
        }
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
        playbackState.repeatMode = nextMode
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
        }
        await MainActor.run {
            VolumeManager.shared.setAbsolute(Float32(clampedLevel))
        }
        
        playbackState.volume = clampedLevel
    }
    
    // MARK: - Setup Methods
    private func setupNowPlayingObserver() async {
        guard !Task.isCancelled else { return }
        if let oldPipe = self.pipeHandler {
            await oldPipe.close()
            self.pipeHandler = nil
        }
        if let oldProc = self.process, oldProc.isRunning {
            oldProc.interrupt()
            oldProc.terminate()
            self.process = nil
        }
        guard !Task.isCancelled else { return }

        let process = Process()
        guard let paths = Self.getAdapterPaths() else {
            NSLog("NowPlayingController: Could not find mediaremote-adapter.pl script or framework path")
            return
        }

        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [paths.script, paths.framework, "stream"]
        
        let pipeHandler = JSONLinesPipeHandler()
        process.standardOutput = await pipeHandler.getPipe()
        
        self.process = process
        self.pipeHandler = pipeHandler

        // Immediately fetch the current active playback state on startup/update without waiting for a track change event
        await fetchInitialNowPlayingInfo(paths: paths)

        do {
            try process.run()
            streamTask = Task { [weak self] in
                await self?.processJSONStream()
            }
        } catch {
            NSLog("NowPlayingController: Failed to launch mediaremote-adapter.pl: \(error)")
        }
    }

    private func fetchInitialNowPlayingInfo(paths: (script: String, framework: String)) async {
        let update = await Task.detached(priority: .userInitiated) { () -> NowPlayingUpdate? in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
            proc.arguments = [paths.script, paths.framework, "get"]
            let outPipe = Pipe()
            proc.standardOutput = outPipe
            proc.standardError = Pipe()
            do {
                try proc.run()
                let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                proc.waitUntilExit()
                guard proc.terminationStatus == 0, !data.isEmpty else { return nil }
                let payload = try JSONDecoder().decode(NowPlayingPayload.self, from: data)
                return NowPlayingUpdate(payload: payload, diff: false)
            } catch {
                NSLog("NowPlayingController: Failed to fetch initial now playing info: \(error)")
                return nil
            }
        }.value

        if let update = update {
            await handleAdapterUpdate(update)
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

        // Guard against initial empty payload handshake from mediaremote-adapter stream:
        // {"type":"data","diff":false,"payload":{}}
        let isEmptyPayload = (payload.title == nil || payload.title?.isEmpty == true) &&
            (payload.artist == nil || payload.artist?.isEmpty == true) &&
            (payload.album == nil || payload.album?.isEmpty == true) &&
            payload.playing == nil &&
            payload.bundleIdentifier == nil &&
            payload.parentApplicationBundleIdentifier == nil &&
            payload.elapsedTime == nil
        if isEmptyPayload {
            return
        }

        var newPlaybackState = PlaybackState(bundleIdentifier: playbackState.bundleIdentifier)
        
        let titleCandidate = payload.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let titleCandidate = titleCandidate, !titleCandidate.isEmpty {
            newPlaybackState.title = titleCandidate
        } else if diff || (!self.playbackState.title.isEmpty && (payload.bundleIdentifier == nil || payload.bundleIdentifier == self.playbackState.bundleIdentifier)) {
            newPlaybackState.title = self.playbackState.title
        } else {
            newPlaybackState.title = ""
        }
        
        let artistCandidate = payload.artist?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let artistCandidate = artistCandidate, !artistCandidate.isEmpty {
            newPlaybackState.artist = artistCandidate
        } else if diff || (!self.playbackState.artist.isEmpty && (payload.bundleIdentifier == nil || payload.bundleIdentifier == self.playbackState.bundleIdentifier)) {
            newPlaybackState.artist = self.playbackState.artist
        } else {
            newPlaybackState.artist = ""
        }
        
        let albumCandidate = payload.album?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let albumCandidate = albumCandidate, !albumCandidate.isEmpty {
            newPlaybackState.album = albumCandidate
        } else if diff || (!self.playbackState.album.isEmpty && (payload.bundleIdentifier == nil || payload.bundleIdentifier == self.playbackState.bundleIdentifier)) {
            newPlaybackState.album = self.playbackState.album
        } else {
            newPlaybackState.album = ""
        }
        
        if let dur = payload.duration, dur > 0 {
            newPlaybackState.duration = dur
        } else if diff || self.playbackState.duration > 0 {
            newPlaybackState.duration = self.playbackState.duration
        } else {
            newPlaybackState.duration = 0
        }
        
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
        } else {
            newPlaybackState.isShuffled = self.playbackState.isShuffled
        }
        if let repeatModeValue = payload.repeatMode {
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
        let newBundle = payload.parentApplicationBundleIdentifier ?? payload.bundleIdentifier
        if let newBundle = newBundle, !newBundle.isEmpty {
            newPlaybackState.bundleIdentifier = newBundle
        } else {
            newPlaybackState.bundleIdentifier = self.playbackState.bundleIdentifier
        }
        
        newPlaybackState.volume = payload.volume ?? self.playbackState.volume
        
        await MainActor.run {
            self.playbackState = newPlaybackState
        }
        
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
                 await MainActor.run {
                     var updated = self.playbackState
                     updated.isFavorite = result.booleanValue
                     self.playbackState = updated
                 }
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
