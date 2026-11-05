import AppKit
import Combine
import CoreGraphics
import Defaults
import ImageIO
import SwiftUI

let defaultImage: NSImage = .init(
    systemSymbolName: "music.note",
    accessibilityDescription: "Album Art"
) ?? NSImage()

class MusicManager: ObservableObject {
    // MARK: - Properties
    static let shared = MusicManager()
    private var cancellables = Set<AnyCancellable>()
    private var controllerCancellables = Set<AnyCancellable>()
    private var debounceIdleTask: Task<Void, Never>?
    private var lastTogglePlayTime: Date = .distantPast
    private var lastTrackChangeTime: Date = .distantPast

    // Helper to check if macOS has removed support for NowPlayingController
    public private(set) var isNowPlayingDeprecated: Bool = false
    private let mediaChecker = MediaChecker()

    // Active controller
    private var activeController: (any MediaControllerProtocol)?

    // Published properties for UI
    @Published var songTitle: String = ""
    @Published var artistName: String = ""
    @Published var albumArt: NSImage = defaultImage
    @Published var isPlaying = false
    @Published var album: String = ""
    @Published var isPlayerIdle: Bool = true
    @Published var animations: NotchPulseAnimations = .init()
    @Published var avgColor: NSColor = .white
    @Published var bundleIdentifier: String? = nil
    @Published var songDuration: TimeInterval = 0
    @Published var elapsedTime: TimeInterval = 0
    @Published var timestampDate: Date = .init()
    @Published var playbackRate: Double = 1
    @Published var isShuffled: Bool = false
    @Published var repeatMode: RepeatMode = .off
    @Published var volume: Double = 0.5
    @Published var volumeControlSupported: Bool = true
    @ObservedObject var coordinator = NotchPulseViewCoordinator.shared
    @Published var usingAppIconForArtwork: Bool = false
    @Published var currentLyrics: String = ""
    @Published var isFetchingLyrics: Bool = false
    @Published var syncedLyrics: [(time: Double, text: String)] = []
    private var checkedTracksWithNoLyrics = Set<String>()
    private var lyricsFetchTask: Task<Void, Never>? = nil
    private var lyricsRequestId: UInt64 = 0
    private var artworkRepollTask: Task<Void, Never>? = nil
    private var emptyTitleVerificationTask: Task<Void, Never>? = nil
    @Published var canFavoriteTrack: Bool = false
    @Published var isFavoriteTrack: Bool = false
    @Published var isUIActive: Bool = false {
        didSet {
            guard oldValue != isUIActive else { return }
            activeController?.setUIActive(isUIActive)
            if isUIActive {
                if Defaults[.enableLyrics] || Defaults[.lockScreenPlayerShowLyrics] {
                    ensureLyricsLoaded()
                }
                ensureArtworkLoaded()
            }
        }
    }

    public private(set) var artworkData: Data? = nil
    public var hasArtwork: Bool {
        return artworkData != nil
    }
    public var hasRealArtwork: Bool {
        return artworkData != nil
    }
    /// Track last isPlaying to detect resume after a long idle period.
    private var lastIsPlaying: Bool = false

    // Store last values at the time artwork was changed
    private var lastArtworkTitle: String = ""
    private var lastArtworkArtist: String = ""
    private var lastArtworkAlbum: String = ""
    private var lastArtworkBundleIdentifier: String? = nil

    @Published var isFlipping: Bool = false
    private var flipWorkItem: DispatchWorkItem?

    @Published var isTransitioning: Bool = false
    private var transitionWorkItem: DispatchWorkItem?
    private var currentControllerType: MediaControllerType?

    // MARK: - Initialization
    init() {
        // Listen for changes to the default controller preference
        NotificationCenter.default.publisher(for: Notification.Name.mediaControllerChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.setActiveControllerBasedOnPreference()
            }
            .store(in: &cancellables)

        // Keep music volume synchronized with active system output volume
        VolumeManager.shared.$rawVolume
            .receive(on: DispatchQueue.main)
            .sink { [weak self] vol in
                self?.volume = Double(vol)
            }
            .store(in: &cancellables)

        // Listen for application termination to auto-fallback media sessions
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self = self,
                      let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      let bundleID = app.bundleIdentifier else { return }
                self.handleApplicationTerminated(bundleIdentifier: bundleID)
            }
            .store(in: &cancellables)

        // Handle wake from sleep to refresh media state and recover artwork
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleSystemWake()
            }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.screensDidWakeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleSystemWake()
            }
            .store(in: &cancellables)

        // Initialize deprecation check and active controller synchronously
        self.isNowPlayingDeprecated = self.mediaChecker.checkDeprecationStatus()
        print("Deprecation check completed: \(self.isNowPlayingDeprecated)")
        self.setActiveControllerBasedOnPreference()
    }

    deinit {
        destroy()
    }
    
    public func destroy() {
        lyricsRequestId &+= 1
        lyricsFetchTask?.cancel()
        lyricsFetchTask = nil
        artworkRepollTask?.cancel()
        artworkRepollTask = nil
        debounceIdleTask?.cancel()
        emptyTitleVerificationTask?.cancel()
        emptyTitleVerificationTask = nil
        cancellables.removeAll()
        controllerCancellables.removeAll()
        flipWorkItem?.cancel()
        transitionWorkItem?.cancel()

        // Release active controller
        activeController = nil
    }

    // MARK: - Sleep & Wake Recovery
    private func handleSystemWake() {
        UniversalArtworkResolver.shared.clearInFlight()

        Task { @MainActor [weak self] in
            // Settle delay after wake
            try? await Task.sleep(for: .milliseconds(500))
            guard let self else { return }
            self.forceUpdate()

            if (self.artworkData == nil || self.usingAppIconForArtwork) && !self.songTitle.isEmpty {
                self.resolveMissingArtwork()
            }

            // Second pass once Wi-Fi / system services have reconnected (1.8s)
            try? await Task.sleep(for: .milliseconds(1300))
            self.forceUpdate()
            if (self.artworkData == nil || self.usingAppIconForArtwork) && !self.songTitle.isEmpty {
                self.resolveMissingArtwork()
            }
        }
    }

    @MainActor
    func resolveMissingArtwork() {
        guard !self.songTitle.isEmpty else { return }
        let currentTitle = self.songTitle
        let currentArtist = self.artistName
        let currentAlbum = self.album
        let currentBundle = self.bundleIdentifier

        if let cached = UniversalArtworkResolver.shared.cachedArtwork(title: currentTitle, artist: currentArtist) {
            self.usingAppIconForArtwork = false
            self.artworkData = cached
            self.updateArtwork(cached)
            return
        }

        if let controller = self.activeController, controller.isActive() {
            Task { @MainActor [weak self] in
                guard let self = self, self.songTitle == currentTitle else { return }
                if let yt = controller as? YouTubeMusicController {
                    await yt.pollPlaybackState()
                } else {
                    await controller.updatePlaybackInfo()
                }
            }
        }

        UniversalArtworkResolver.shared.resolveArtwork(
            title: currentTitle,
            artist: currentArtist,
            album: currentAlbum,
            bundleIdentifier: currentBundle
        ) { [weak self] resolvedData in
            guard let self = self, let data = resolvedData else { return }
            DispatchQueue.main.async {
                guard self.songTitle == currentTitle, self.bundleIdentifier == currentBundle else { return }
                self.usingAppIconForArtwork = false
                self.artworkData = data
                self.updateArtwork(data)
                self.triggerFlipAnimation()
            }
        }
    }

    private func scheduleArtworkRepoll(for title: String, artist: String) {
        artworkRepollTask?.cancel()
        guard !title.isEmpty else { return }
        let targetTitle = title
        let targetArtist = artist

        artworkRepollTask = Task { @MainActor [weak self] in
            for delayMs in [350, 450, 600] {
                try? await Task.sleep(for: .milliseconds(delayMs))
                guard !Task.isCancelled, let self = self else { return }
                guard self.songTitle == targetTitle && self.artistName == targetArtist else { return }
                guard self.artworkData == nil || self.usingAppIconForArtwork else { return }

                if let controller = self.activeController, controller.isActive() {
                    if let yt = controller as? YouTubeMusicController {
                        await yt.pollPlaybackState()
                    } else {
                        await controller.updatePlaybackInfo()
                    }
                }
                if self.artworkData == nil || self.usingAppIconForArtwork {
                    self.resolveMissingArtwork()
                }
            }
        }
    }

    // MARK: - Setup Methods
    private func createController(for type: MediaControllerType) -> (any MediaControllerProtocol)? {
        // Cleanup previous controller
        if activeController != nil {
            controllerCancellables.removeAll()
            activeController = nil
        }

        let newController: (any MediaControllerProtocol)?

        switch type {
        case .nowPlaying:
            // Only create NowPlayingController if not deprecated on this macOS version
            if !self.isNowPlayingDeprecated {
                newController = NowPlayingController()
            } else {
                return nil
            }
        case .appleMusic:
            MediaAutomationPermissionHelper.requestPermission(for: "com.apple.Music")
            newController = AppleMusicController()
        case .spotify:
            MediaAutomationPermissionHelper.requestPermission(for: "com.spotify.client")
            newController = SpotifyController()
        case .youtubeMusic:
            newController = YouTubeMusicController()
        }

        return newController
    }

    private func setActiveControllerBasedOnPreference() {
        let preferredType = Defaults[.mediaController]
        print("Preferred Media Controller: \(preferredType)")

        // If NowPlaying is deprecated but that's the preference, use Apple Music instead
        let controllerType = (self.isNowPlayingDeprecated && preferredType == .nowPlaying)
            ? .appleMusic
            : preferredType

        guard controllerType != currentControllerType || activeController == nil else { return }
        currentControllerType = controllerType

        if let controller = createController(for: controllerType) {
            setActiveController(controller)
        } else if controllerType != .appleMusic, let fallbackController = createController(for: .appleMusic) {
            // Fallback to Apple Music if preferred controller couldn't be created
            setActiveController(fallbackController)
        }
    }

    private func setActiveController(_ controller: any MediaControllerProtocol) {
        // Cancel any existing flip animation
        flipWorkItem?.cancel()

        // Set new active controller first so activeController === controller check succeeds on initial emission
        activeController = controller
        
        self.canFavoriteTrack = controller.supportsFavorite

        // Set up state observation for the active controller
        controllerCancellables.removeAll()
        controller.playbackStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self = self,
                      self.activeController === controller else { return }
                self.updateFromPlaybackState(state)
            }
            .store(in: &controllerCancellables)

        // Get current state from active controller
        forceUpdate()
    }

    // MARK: - Update Methods
    @MainActor
    private func updateFromPlaybackState(_ state: PlaybackState) {
        let wasPlaying = self.isPlaying
        let trimmedTitle = state.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTitle.isEmpty {
            // MediaRemote can briefly return an empty payload while WindowServer
            // transitions into the lock screen. Do not interpret that transient
            // snapshot as the player having stopped; otherwise the active session
            // is removed and the lock-screen player disappears after unlock.
            if (NotchPulseLockMonitor.isScreenActuallyLocked()
                || LockScreenWakeObserver.shared.isScreenLocked), !self.songTitle.isEmpty {
                NSLog("Ignoring transient empty playback state while screen is locked")
                return
            }

            // A transient empty payload can also occur when the notch opens on hover
            // and the media controller is queried during window focus changes.
            // If we are currently playing a song, debounce before tearing down the session.
            if !self.songTitle.isEmpty && self.isPlaying {
                if emptyTitleVerificationTask == nil {
                    emptyTitleVerificationTask = Task { @MainActor [weak self] in
                        try? await Task.sleep(for: .milliseconds(600))
                        guard !Task.isCancelled, let self = self else { return }
                        self.emptyTitleVerificationTask = nil
                        self.isPlaying = false
                        self.playbackRate = 0
                        let closedId = "\(self.bundleIdentifier ?? "")---\(self.songTitle)---\(self.artistName)"
                        self.handleActiveMediaStopped(closedSessionId: closedId)
                    }
                }
                return
            }

            // Immediately stop playback and reset rate to avoid ghost playback
            self.isPlaying = false
            self.playbackRate = 0

            let closedId = "\(self.bundleIdentifier ?? "")---\(self.songTitle)---\(self.artistName)"
            self.handleActiveMediaStopped(closedSessionId: closedId)
            return
        }

        emptyTitleVerificationTask?.cancel()
        emptyTitleVerificationTask = nil

        // Track playback state changes (playing/paused)
        self.lastIsPlaying = state.isPlaying

        if state.isPlaying != self.isPlaying {
            NSLog("Playback state changed: \(state.isPlaying ? "Playing" : "Paused")")
            withAnimation(.smooth) {
                self.isPlaying = state.isPlaying
                self.updateIdleState(state: state.isPlaying)
            }

            if state.isPlaying && !state.title.isEmpty && !state.artist.isEmpty {
                self.updateSneakPeek()
            }
        } else if self.isPlayerIdle && state.isPlaying {
            withAnimation(.smooth) {
                self.isPlayerIdle = false
            }
        } else if self.isPlayerIdle && !trimmedTitle.isEmpty && debounceIdleTask == nil {
            // When track is present on startup/update, activate debounce rather than snapping to idle
            self.updateIdleState(state: false)
        }

        // Check for changes in track metadata using last artwork change values
        let titleChanged = state.title != self.lastArtworkTitle
        let artistChanged = state.artist != self.lastArtworkArtist
        let albumChanged = state.album != self.lastArtworkAlbum
        let bundleChanged = state.bundleIdentifier != self.lastArtworkBundleIdentifier

        // Check for artwork changes: only treat as artwork change if embedded artwork differs, or if title/artist/bundle switched, or if artwork is currently missing
        let needsArtwork = (self.artworkData == nil || self.usingAppIconForArtwork) && !state.title.isEmpty
        let artworkChanged = (state.artwork != nil && state.artwork != self.artworkData) || (titleChanged || artistChanged || bundleChanged) || needsArtwork
        let hasContentChange = titleChanged || artistChanged || albumChanged || artworkChanged || bundleChanged

        // Immediately synchronize track metadata with active playback state
        if state.title != self.songTitle {
            self.songTitle = state.title
        }
        if state.artist != self.artistName {
            self.artistName = state.artist
        }
        if state.album != self.album {
            self.album = state.album
        }
        if state.bundleIdentifier != self.bundleIdentifier {
            self.bundleIdentifier = state.bundleIdentifier
            self.volumeControlSupported = activeController?.supportsVolumeControl ?? false
        }

        // Handle artwork and visual transitions for changed content
        if hasContentChange {
            if titleChanged || artistChanged || bundleChanged {
                self.lyricsRequestId &+= 1
                self.lyricsFetchTask?.cancel()
                self.lyricsFetchTask = nil
                self.syncedLyrics = []
                self.currentLyrics = ""
                self.isFetchingLyrics = false

                // Immediately clear previous track's artwork so it never leaks to the new track
                self.artworkRepollTask?.cancel()
                self.artworkRepollTask = nil
                self.artworkData = nil
                self.usingAppIconForArtwork = false
                self.updateAlbumArt(newAlbumArt: defaultImage)
            }
            self.triggerFlipAnimation()

            if let artwork = state.artwork {
                self.artworkRepollTask?.cancel()
                self.artworkRepollTask = nil
                self.usingAppIconForArtwork = false
                let optimized = UniversalArtworkResolver.shared.optimizeArtwork(artwork, maxDimension: 640)
                self.artworkData = optimized
                self.updateArtwork(optimized)
                UniversalArtworkResolver.shared.cacheArtworkData(optimized, title: state.title, artist: state.artist)
            } else if let cached = UniversalArtworkResolver.shared.cachedArtwork(title: state.title, artist: state.artist) {
                self.artworkRepollTask?.cancel()
                self.artworkRepollTask = nil
                self.usingAppIconForArtwork = false
                self.artworkData = cached
                self.updateArtwork(cached)
            } else if !titleChanged && !artistChanged && self.artworkData != nil {
                // If the track hasn't changed and artwork is already loaded, retain it
                self.usingAppIconForArtwork = false
            } else {
                // Never display host app or browser logo in the media card. Show clean placeholder.
                self.usingAppIconForArtwork = false
                self.artworkData = nil
                self.updateAlbumArt(newAlbumArt: defaultImage)

                // Asynchronously resolve true high-resolution media cover art (YouTube thumbnail / iTunes / Deezer)
                let currentTitle = state.title
                let currentArtist = state.artist
                let currentAlbum = state.album
                let currentBundle = state.bundleIdentifier
                UniversalArtworkResolver.shared.resolveArtwork(
                    title: currentTitle,
                    artist: currentArtist,
                    album: currentAlbum,
                    bundleIdentifier: currentBundle
                ) { [weak self] resolvedData in
                    guard let self = self else { return }
                    if let data = resolvedData {
                        DispatchQueue.main.async {
                            // Verify track hasn't changed while resolving
                            guard self.songTitle == currentTitle else { return }
                            self.artworkRepollTask?.cancel()
                            self.artworkRepollTask = nil
                            self.usingAppIconForArtwork = false
                            self.artworkData = data
                            self.updateArtwork(data)
                            self.triggerFlipAnimation()
                        }
                    } else {
                        // If resolution failed (e.g. Wi-Fi still reconnecting right on wake), retry once after 2.5s
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                            guard let self = self, self.songTitle == currentTitle, self.artworkData == nil else { return }
                            UniversalArtworkResolver.shared.resolveArtwork(
                                title: currentTitle,
                                artist: currentArtist,
                                album: currentAlbum,
                                bundleIdentifier: currentBundle
                            ) { [weak self] retryData in
                                guard let self = self, let retryData = retryData, self.songTitle == currentTitle else { return }
                                DispatchQueue.main.async {
                                    self.artworkRepollTask?.cancel()
                                    self.artworkRepollTask = nil
                                    self.usingAppIconForArtwork = false
                                    self.artworkData = retryData
                                    self.updateArtwork(retryData)
                                    self.triggerFlipAnimation()
                                }
                            }
                        }
                    }
                }

                // Automatic staggered re-poll of active controller (at 350ms and 850ms)
                // captures embedded/decoded artwork from MediaRemote/Spotify/Music without needing Notch open
                self.scheduleArtworkRepoll(for: state.title, artist: state.artist)
            }

            // Update last artwork change values
            self.lastArtworkTitle = state.title
            self.lastArtworkArtist = state.artist
            self.lastArtworkAlbum = state.album
            self.lastArtworkBundleIdentifier = state.bundleIdentifier

            // Only update sneak peek if there's actual content and something changed
            if !state.title.isEmpty && !state.artist.isEmpty && state.isPlaying {
                self.updateSneakPeek()
            }
        }

        let durationChanged = state.duration != self.songDuration
        let shuffleChanged = state.isShuffled != self.isShuffled
        let repeatModeChanged = state.repeatMode != self.repeatMode
        let volumeChanged = state.volume != self.volume

        if repeatModeChanged {
            self.repeatMode = state.repeatMode
        }
        if state.isFavorite != self.isFavoriteTrack {
            self.isFavoriteTrack = state.isFavorite
        }
        
        if volumeChanged && !(activeController is NowPlayingController) {
            self.volume = state.volume
        }

        if durationChanged {
            self.songDuration = state.duration
        }

        // Position and timestamp are one time base and must be replaced together.
        // Thresholding small corrections while still replacing the timestamp made
        // the UI jump backwards on pause and drift after repeated notifications.
        self.elapsedTime = state.duration > 0
            ? min(max(0, state.currentTime), state.duration)
            : max(0, state.currentTime)
        self.timestampDate = state.lastUpdated == .distantPast ? Date() : state.lastUpdated
        self.playbackRate = state.isPlaying
            ? (state.playbackRate > 0 ? state.playbackRate : (wasPlaying && self.playbackRate > 0 ? self.playbackRate : 1))
            : 0
        
        if shuffleChanged {
            self.isShuffled = state.isShuffled
        }
        
        // Fetch lyrics on content change only if UI is visible (Lazy loading)
        // Checked after songTitle, artistName and bundleIdentifier are synchronized
        if hasContentChange {
            if self.isUIActive && (Defaults[.enableLyrics] || Defaults[.lockScreenPlayerShowLyrics]) {
                self.fetchLyricsIfAvailable(bundleIdentifier: state.bundleIdentifier, title: state.title, artist: state.artist)
            } else {
                self.lyricsRequestId &+= 1
                self.lyricsFetchTask?.cancel()
                self.lyricsFetchTask = nil
                self.currentLyrics = ""
                self.syncedLyrics = []
                self.isFetchingLyrics = false
            }
        }
    }

    func toggleFavoriteTrack() {
        guard canFavoriteTrack else { return }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
            self.isFavoriteTrack.toggle()
        }
        setFavorite(isFavoriteTrack)
    }

    @MainActor
    private func toggleAppleMusicFavorite() async {
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music")
        guard !runningApps.isEmpty else { return }

        let script = """
        tell application \"Music\"
            if it is running then
                try
                    set loved of current track to (not loved of current track)
                    return loved of current track
                on error
                    return false
                end try
            else
                return false
            end if
        end tell
        """

        if let result = try? await AppleScriptHelper.execute(script) {
            let loved = result.booleanValue
            self.isFavoriteTrack = loved
            self.forceUpdate()
        }
    }

    func setFavorite(_ favorite: Bool) {
        guard canFavoriteTrack else { return }
        guard let controller = activeController else { return }

        Task { @MainActor in
            await controller.setFavorite(favorite)
            try? await Task.sleep(for: .milliseconds(150))
            await controller.updatePlaybackInfo()
        }
    }

    /// Placeholder dislike function
    func dislikeCurrentTrack() {
        setFavorite(false)
    }

    // MARK: - Lyrics
    func ensureLyricsLoaded() {
        guard !songTitle.isEmpty else { return }
        let trackKey = "\(songTitle.lowercased())---\(artistName.lowercased())"
        if checkedTracksWithNoLyrics.contains(trackKey) { return }
        if currentLyrics.isEmpty && syncedLyrics.isEmpty && !isFetchingLyrics {
            fetchLyricsIfAvailable(bundleIdentifier: bundleIdentifier, title: songTitle, artist: artistName)
        }
    }

    // MARK: - Artwork Verification
    func ensureArtworkLoaded() {
        guard !songTitle.isEmpty else { return }
        if artworkData == nil || usingAppIconForArtwork {
            forceUpdate()
            resolveMissingArtwork()
        }
    }

    func fetchLyricsIfAvailable(bundleIdentifier: String?, title: String, artist: String) {
        // The lock-screen player has its own lyrics toggle. It must be allowed
        // to fetch while the card is visible even when lyrics are disabled for
        // the regular notch UI.
        guard isUIActive && (Defaults[.enableLyrics] || Defaults[.lockScreenPlayerShowLyrics]) else { return }

        self.lyricsRequestId &+= 1
        let currentRequestId = self.lyricsRequestId

        lyricsFetchTask?.cancel()
        lyricsFetchTask = nil

        guard !title.isEmpty else {
            self.isFetchingLyrics = false
            self.currentLyrics = ""
            self.syncedLyrics = []
            return
        }

        self.isFetchingLyrics = true
        self.currentLyrics = ""
        self.syncedLyrics = []

        let targetTitle = title
        let targetArtist = artist
        let targetBundle = bundleIdentifier ?? ""

        let isTargetActive = { [weak self] () -> Bool in
            guard let self = self else { return false }
            return !Task.isCancelled &&
                self.lyricsRequestId == currentRequestId &&
                self.songTitle == targetTitle &&
                self.artistName == targetArtist &&
                (self.bundleIdentifier ?? "") == targetBundle
        }

        // Prefer native Apple Music lyrics when available
        if let bundleIdentifier = bundleIdentifier, bundleIdentifier.contains("com.apple.Music") {
            lyricsFetchTask = Task { @MainActor in
                let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music")
                guard !runningApps.isEmpty else {
                    await self.fetchLyricsFromWeb(title: targetTitle, artist: targetArtist, requestId: currentRequestId, targetBundle: targetBundle)
                    return
                }

                do {
                    let script = """
                    tell application \"Music\"
                        if it is running then
                            if player state is playing or player state is paused then
                                try
                                    set l to lyrics of current track
                                    if l is missing value then
                                        return \"\"
                                    else
                                        return l
                                    end if
                                on error
                                    return \"\"
                                end try
                            else
                                return \"\"
                            end if
                        else
                            return \"\"
                        end if
                    end tell
                    """
                    if let result = try await AppleScriptHelper.execute(script),
                       let lyricsString = result.stringValue,
                       !lyricsString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        guard isTargetActive() else { return }
                        self.currentLyrics = lyricsString.trimmingCharacters(in: .whitespacesAndNewlines)
                        self.isFetchingLyrics = false
                        self.syncedLyrics = []
                        return
                    }
                } catch {
                    // fall through to web lookup
                }
                guard isTargetActive() else { return }
                await self.fetchLyricsFromWeb(title: targetTitle, artist: targetArtist, requestId: currentRequestId, targetBundle: targetBundle)
            }
        } else {
            lyricsFetchTask = Task { @MainActor in
                await self.fetchLyricsFromWeb(title: targetTitle, artist: targetArtist, requestId: currentRequestId, targetBundle: targetBundle)
            }
        }
    }

    private func normalizedQuery(_ string: String) -> String {
        string
            .folding(options: .diacriticInsensitive, locale: .current)
            .replacingOccurrences(of: "\u{FFFD}", with: "")
    }

    private func cleanSongTitle(_ title: String) -> String {
        var clean = title
        let patterns = [
            #"\((?i)(feat\.|ft\.|with).*?\)"#,
            #"\[(?i)(feat\.|ft\.|with).*?\]"#,
            #"\((?i).*?(video|mv|visualizer|audio|lyrics|lyric video|slowed|reverb|remix|remaster|live|acoustic|cover).*?\)"#,
            #"\[(?i).*?(video|mv|visualizer|audio|lyrics|lyric video|slowed|reverb|remix|remaster|live|acoustic|cover).*?\]"#,
            #"\-(?i).*?remaster.*"#
        ]
        for p in patterns {
            if let regex = try? NSRegularExpression(pattern: p, options: [.caseInsensitive]) {
                clean = regex.stringByReplacingMatches(in: clean, options: [], range: NSRange(location: 0, length: (clean as NSString).length), withTemplate: "")
            }
        }
        return clean.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @MainActor
    private func fetchLyricsFromWeb(title: String, artist: String, requestId: UInt64, targetBundle: String) async {
        let isTargetActive = { [weak self] () -> Bool in
            guard let self = self else { return false }
            return !Task.isCancelled &&
                self.lyricsRequestId == requestId &&
                self.songTitle == title &&
                self.artistName == artist &&
                (self.bundleIdentifier ?? "") == targetBundle
        }

        guard isTargetActive() else { return }

        let cleanTitle = normalizedQuery(cleanSongTitle(title))
        let cleanArtist = normalizedQuery(artist)

        var searchUrls: [String] = []

        // If title contains " - " (common for YouTube: "Song - Artist" or "Artist - Song")
        if cleanTitle.contains(" - ") {
            let parts = cleanTitle.components(separatedBy: " - ")
            if parts.count >= 2 {
                let part1 = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let part2 = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                if !part1.isEmpty && !part2.isEmpty {
                    if let enc1 = part1.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                       let enc2 = part2.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                        searchUrls.append("https://lrclib.net/api/search?track_name=\(enc1)&artist_name=\(enc2)")
                        searchUrls.append("https://lrclib.net/api/search?track_name=\(enc2)&artist_name=\(enc1)")
                        if let encQ = "\(part1) \(part2)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                            searchUrls.append("https://lrclib.net/api/search?q=\(encQ)")
                        }
                    }
                }
            }
        }

        // Standard exact & loose query searches
        if let encTitle = cleanTitle.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let encArtist = cleanArtist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            searchUrls.append("https://lrclib.net/api/search?track_name=\(encTitle)&artist_name=\(encArtist)")
            if let encQ = "\(cleanTitle) \(cleanArtist)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                searchUrls.append("https://lrclib.net/api/search?q=\(encQ)")
            }
            searchUrls.append("https://lrclib.net/api/search?q=\(encTitle)")
        }

        var hadSuccessfulResponse = false

        for urlString in searchUrls {
            guard isTargetActive() else { return }
            guard let url = URL(string: urlString) else { continue }
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard isTargetActive() else { return }
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { continue }

                hadSuccessfulResponse = true
                if let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                    // Search through candidates rather than blindly taking first
                    for candidate in jsonArray {
                        let plain = (candidate["plainLyrics"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        let synced = (candidate["syncedLyrics"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        let resolved = plain.isEmpty ? Self.stripLRCTimestamps(from: synced) : plain
                        if !resolved.isEmpty {
                            guard isTargetActive() else { return }
                            self.currentLyrics = resolved
                            self.isFetchingLyrics = false
                            if !synced.isEmpty {
                                self.syncedLyrics = self.parseLRC(synced)
                            } else {
                                self.syncedLyrics = []
                            }
                            return
                        }
                    }
                }
            } catch {
                if Task.isCancelled || !isTargetActive() { return }
                continue
            }
        }

        guard isTargetActive() else { return }

        // Only mark permanently as no-lyrics if we successfully contacted the server and received no matching lyrics
        if hadSuccessfulResponse {
            let trackKey = "\(title.lowercased())---\(artist.lowercased())"
            self.checkedTracksWithNoLyrics.insert(trackKey)
        }

        self.currentLyrics = ""
        self.isFetchingLyrics = false
        self.syncedLyrics = []
    }

    // MARK: - Synced lyrics helpers
    static func stripLRCTimestamps(from string: String) -> String {
        let lineTagPattern = #"\[\d{1,2}:\d{2}(?:\.\d{1,3})?\]"#
        let wordTagPattern = #"<\d{1,2}:\d{2}(?:\.\d{1,3})?>"#
        var clean = string.replacingOccurrences(of: lineTagPattern, with: "", options: .regularExpression)
        clean = clean.replacingOccurrences(of: wordTagPattern, with: "", options: .regularExpression)
        return clean.trimmingCharacters(in: .whitespaces)
    }

    private func parseLRC(_ lrc: String) -> [(time: Double, text: String)] {
        var result: [(Double, String)] = []
        // Regex matches [mm:ss.xx] or [mm:ss.xxx] or [m:ss]
        let pattern = #"\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        lrc.split(separator: "\n").forEach { lineSub in
            let line = String(lineSub).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { return }
            
            // Skip metadata lines like [ti:...], [ar:...], etc.
            if line.hasPrefix("[ti:") || line.hasPrefix("[ar:") || line.hasPrefix("[al:") || line.hasPrefix("[by:") || line.hasPrefix("[offset:") {
                return
            }

            let nsLine = line as NSString
            let matches = regex.matches(in: line, range: NSRange(location: 0, length: nsLine.length))
            guard !matches.isEmpty else { return }

            // Extract the lyric text after stripping all line and word-by-word timestamp tags
            let cleanWithoutLine = regex.stringByReplacingMatches(in: line, options: [], range: NSRange(location: 0, length: nsLine.length), withTemplate: "")
            let cleanText = Self.stripLRCTimestamps(from: cleanWithoutLine)

            guard !cleanText.isEmpty else { return }

            for match in matches {
                let minStr = nsLine.substring(with: match.range(at: 1))
                let secStr = nsLine.substring(with: match.range(at: 2))
                let csRange = match.range(at: 3)
                
                let minutes = Double(minStr) ?? 0
                let seconds = Double(secStr) ?? 0
                var fraction: Double = 0
                
                if csRange.location != NSNotFound {
                    let fracStr = nsLine.substring(with: csRange)
                    if fracStr.count == 3 {
                        fraction = (Double(fracStr) ?? 0) / 1000.0
                    } else if fracStr.count == 2 {
                        fraction = (Double(fracStr) ?? 0) / 100.0
                    } else if fracStr.count == 1 {
                        fraction = (Double(fracStr) ?? 0) / 10.0
                    }
                }
                
                let time = minutes * 60.0 + seconds + fraction
                result.append((time, cleanText))
            }
        }
        return result.sorted { $0.0 < $1.0 }
    }

    /// Returns the currently active lyric line index based on elapsed seconds.
    /// Returns nil if currently in the intro before the first line or in a long instrumental break.
    func currentLyricIndex(at elapsed: Double) -> Int? {
        guard !syncedLyrics.isEmpty else { return nil }
        
        // Calibrated lyric transition advance: 0.15s faster display for upcoming line
        let calibratedElapsed = elapsed + 0.15
        
        // If before the first lyric line:
        if calibratedElapsed < syncedLyrics[0].time {
            return nil
        }
        
        // Binary search for last line with time <= calibratedElapsed
        var low = 0
        var high = syncedLyrics.count - 1
        var idx = 0
        while low <= high {
            let mid = (low + high) / 2
            if syncedLyrics[mid].time <= calibratedElapsed {
                idx = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        
        // Check for long instrumental break (> 7s between lines)
        if idx + 1 < syncedLyrics.count {
            let currentLineTime = syncedLyrics[idx].time
            let nextLineTime = syncedLyrics[idx + 1].time
            let gap = nextLineTime - currentLineTime
            if gap > 7.0 && calibratedElapsed > (currentLineTime + 5.5) && calibratedElapsed < (nextLineTime - 1.5) {
                return nil // Instrumental solo
            }
        }
        
        return idx
    }

    func lyricLine(at elapsed: Double) -> String {
        guard !syncedLyrics.isEmpty else { return currentLyrics }
        
        if let idx = currentLyricIndex(at: elapsed) {
            return syncedLyrics[idx].text
        } else {
            if elapsed < syncedLyrics[0].time {
                return "♪  ♫  ♪"
            }
            if let last = syncedLyrics.last, elapsed > last.time + 6.0 {
                return "♪  ♫  ♪"
            }
            return "♪  ♫  ♪"
        }
    }

    private func triggerFlipAnimation() {
        // Cancel any existing animation
        flipWorkItem?.cancel()

        // Create a new animation
        let workItem = DispatchWorkItem { [weak self] in
            self?.isFlipping = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self?.isFlipping = false
            }
        }

        flipWorkItem = workItem
        DispatchQueue.main.async(execute: workItem)
    }

    private func updateArtwork(_ artworkData: Data) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            if let source = CGImageSourceCreateWithData(artworkData as CFData, nil),
               let cgImage = CGImageSourceCreateImageAtIndex(source, 0, [
                   kCGImageSourceCreateThumbnailFromImageAlways: true,
                   kCGImageSourceThumbnailMaxPixelSize: 640,
                   kCGImageSourceCreateThumbnailWithTransform: true
               ] as CFDictionary) {
                // Display at 2x Retina backing scale
                let pointWidth = CGFloat(cgImage.width) / 2.0
                let pointHeight = CGFloat(cgImage.height) / 2.0
                let artworkImage = NSImage(cgImage: cgImage, size: NSSize(width: pointWidth, height: pointHeight))
                DispatchQueue.main.async { [weak self] in
                    self?.usingAppIconForArtwork = false
                    self?.updateAlbumArt(newAlbumArt: artworkImage)
                }
            } else if let artworkImage = NSImage(data: artworkData) {
                DispatchQueue.main.async { [weak self] in
                    self?.usingAppIconForArtwork = false
                    self?.updateAlbumArt(newAlbumArt: artworkImage)
                }
            }
        }
    }

    private func updateIdleState(state: Bool) {
        debounceIdleTask?.cancel()
        if state {
            withAnimation(.smooth) {
                self.isPlayerIdle = false
            }
        } else {
            debounceIdleTask = Task { @MainActor [weak self] in
                guard let self = self else { return }
                try? await Task.sleep(for: .seconds(Defaults[.waitInterval]))
                guard !Task.isCancelled else { return }
                guard !self.isPlaying else { return }

                withAnimation {
                    self.isPlayerIdle = !self.isPlaying
                }
            }
        }
    }

    private var workItem: DispatchWorkItem?

    func updateAlbumArt(newAlbumArt: NSImage) {
        workItem?.cancel()
        withAnimation(.smooth) {
            self.albumArt = newAlbumArt
            self.calculateAverageColor()
        }
    }

    // MARK: - Playback Stop & Idle

    @MainActor
    private func handleActiveMediaStopped(closedSessionId: String? = nil) {
        if closedSessionId == nil, !self.songTitle.isEmpty {
            self.isPlaying = false
            self.playbackRate = 0
            withAnimation {
                self.isPlayerIdle = true
            }
            return
        }

        resetToIdle()
        updateIdleState(state: false)
    }

    @MainActor
    private func handleApplicationTerminated(bundleIdentifier: String) {
        if self.bundleIdentifier == bundleIdentifier {
            self.isPlaying = false
            self.playbackRate = 0
            handleActiveMediaStopped()
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                await self.activeController?.updatePlaybackInfo()
            }
        }
    }

    @MainActor
    public func fallbackToPreviousMedia() {
        handleActiveMediaStopped()
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            await self.activeController?.updatePlaybackInfo()
        }
    }

    @MainActor
    public func dismissCurrentMedia() {
        self.pause()
        handleActiveMediaStopped()
    }

    @MainActor
    private func resetToIdle() {
        self.songTitle = ""
        self.artistName = ""
        self.album = ""
        self.bundleIdentifier = nil
        self.albumArt = defaultImage
        self.artworkData = nil
        self.isPlaying = false
        self.playbackRate = 0
        self.isPlayerIdle = true
        self.elapsedTime = 0
        self.songDuration = 0
        self.artworkRepollTask?.cancel()
        self.artworkRepollTask = nil
        // Reset and invalidate in-flight lyrics requests when clearing to idle
        self.lyricsRequestId &+= 1
        self.lyricsFetchTask?.cancel()
        self.lyricsFetchTask = nil
        self.isFetchingLyrics = false
        self.syncedLyrics = []
        self.currentLyrics = ""
    }

    // MARK: - Playback Position Estimation
    public func estimatedPlaybackPosition(at date: Date = Date()) -> TimeInterval {
        guard isPlaying, playbackRate > 0 else {
            return songDuration > 0 ? min(elapsedTime, songDuration) : elapsedTime
        }

        let timeDifference = date.timeIntervalSince(timestampDate)
        let estimated = elapsedTime + (timeDifference * playbackRate)
        return songDuration > 0 ? min(max(0, estimated), songDuration) : max(0, estimated)
    }

    public var currentEstimatedTime: TimeInterval {
        estimatedPlaybackPosition()
    }

    func calculateAverageColor() {
        albumArt.averageColor { [weak self] color in
            DispatchQueue.main.async {
                withAnimation(.smooth) {
                    self?.avgColor = color ?? .white
                }
            }
        }
    }

    private func updateSneakPeek() {
        guard !isUIActive else { return }
        if isPlaying && Defaults[.enableSneakPeek] {
            if Defaults[.sneakPeekStyles] == .standard {
                coordinator.toggleSneakPeek(status: true, type: .music)
            } else {
                coordinator.toggleExpandingView(status: true, type: .music)
            }
        }
    }

    // MARK: - Public Methods for controlling playback
    func playPause() {
        togglePlay()
    }

    func play() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
            self.isPlaying = true
            self.updateIdleState(state: true)
        }
        Task {
            if let activeController = activeController {
                await activeController.play()
            } else {
                let ok = await NowPlayingController.sendUniversalCommand("send", arg: "0")
                if !ok {
                    if NotchPulseLockMonitor.isScreenActuallyLocked() {
                        NowPlayingController.postMediaKeyEvent(for: 0)
                    } else {
                        let bundleID = bundleIdentifier ?? ""
                        if bundleID == "com.apple.Music" {
                            try? await AppleScriptHelper.executeVoid("tell application \"Music\" to play")
                        } else if bundleID == "com.spotify.client" {
                            try? await AppleScriptHelper.executeVoid("tell application \"Spotify\" to play")
                        } else {
                            NowPlayingController.postMediaKeyEvent(for: 0)
                        }
                    }
                }
            }
        }
    }

    func pause() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
            self.isPlaying = false
            self.updateIdleState(state: false)
        }
        Task {
            if let activeController = activeController {
                await activeController.pause()
            } else {
                let ok = await NowPlayingController.sendUniversalCommand("send", arg: "1")
                if !ok {
                    if NotchPulseLockMonitor.isScreenActuallyLocked() {
                        NowPlayingController.postMediaKeyEvent(for: 1)
                    } else {
                        let bundleID = bundleIdentifier ?? ""
                        if bundleID == "com.apple.Music" {
                            try? await AppleScriptHelper.executeVoid("tell application \"Music\" to pause")
                        } else if bundleID == "com.spotify.client" {
                            try? await AppleScriptHelper.executeVoid("tell application \"Spotify\" to pause")
                        } else {
                            NowPlayingController.postMediaKeyEvent(for: 1)
                        }
                    }
                }
            }
        }
    }

    func toggleShuffle() {
        withAnimation(.easeInOut(duration: 0.15)) {
            self.isShuffled.toggle()
        }
        Task {
            if let activeController = activeController {
                await activeController.toggleShuffle()
            } else {
                await NowPlayingController.sendUniversalCommand("shuffle", arg: self.isShuffled ? "3" : "1")
            }
        }
    }

    func toggleRepeat() {
        let nextMode: RepeatMode
        switch repeatMode {
        case .off:
            nextMode = .all
        case .all:
            nextMode = .one
        case .one:
            nextMode = .off
        }
        withAnimation(.easeInOut(duration: 0.15)) {
            self.repeatMode = nextMode
        }
        Task {
            if let activeController = activeController {
                await activeController.toggleRepeat()
            } else {
                let adapterRepeatMode: String
                switch nextMode {
                case .off: adapterRepeatMode = "1"
                case .one: adapterRepeatMode = "2"
                case .all: adapterRepeatMode = "3"
                }
                await NowPlayingController.sendUniversalCommand("repeat", arg: adapterRepeatMode)
            }
        }
    }
    
    func togglePlay() {
        let now = Date()
        guard now.timeIntervalSince(lastTogglePlayTime) > 0.20 else { return }
        lastTogglePlayTime = now
        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
            self.isPlaying.toggle()
            self.updateIdleState(state: self.isPlaying)
        }
        Task {
            if let activeController = activeController {
                await activeController.togglePlay()
            } else {
                let ok = await NowPlayingController.sendUniversalCommand("send", arg: "2")
                if !ok {
                    if NotchPulseLockMonitor.isScreenActuallyLocked() {
                        NowPlayingController.postMediaKeyEvent(for: 2)
                    } else {
                        let bundleID = bundleIdentifier ?? ""
                        if bundleID == "com.apple.Music" {
                            try? await AppleScriptHelper.executeVoid("tell application \"Music\" to playpause")
                        } else if bundleID == "com.spotify.client" {
                            try? await AppleScriptHelper.executeVoid("tell application \"Spotify\" to playpause")
                        } else {
                            NowPlayingController.postMediaKeyEvent(for: 2)
                        }
                    }
                }
            }
        }
    }

    func nextTrack() {
        let now = Date()
        guard now.timeIntervalSince(lastTrackChangeTime) > 0.25 else { return }
        lastTrackChangeTime = now
        Task {
            if let activeController = activeController {
                await activeController.nextTrack()
            } else if NotchPulseLockMonitor.isScreenActuallyLocked() {
                await NowPlayingController.sendUniversalCommand("send", arg: "4")
                NowPlayingController.postMediaKeyEvent(for: 4)
            } else {
                let bundleID = bundleIdentifier ?? ""
                if bundleID == "com.apple.Music" {
                    try? await AppleScriptHelper.executeVoid("tell application \"Music\" to next track")
                } else if bundleID == "com.spotify.client" {
                    try? await AppleScriptHelper.executeVoid("tell application \"Spotify\" to next track")
                } else {
                    await NowPlayingController.sendUniversalCommand("send", arg: "4")
                    NowPlayingController.postMediaKeyEvent(for: 4)
                }
            }
            try? await Task.sleep(for: .milliseconds(350))
            self.forceUpdate()
        }
    }

    func previousTrack() {
        let now = Date()
        guard now.timeIntervalSince(lastTrackChangeTime) > 0.25 else { return }
        lastTrackChangeTime = now
        Task {
            if let activeController = activeController {
                await activeController.previousTrack()
            } else if NotchPulseLockMonitor.isScreenActuallyLocked() {
                await NowPlayingController.sendUniversalCommand("send", arg: "5")
                NowPlayingController.postMediaKeyEvent(for: 5)
            } else {
                let bundleID = bundleIdentifier ?? ""
                if bundleID == "com.apple.Music" {
                    try? await AppleScriptHelper.executeVoid("tell application \"Music\" to previous track")
                } else if bundleID == "com.spotify.client" {
                    let script = """
                    tell application "Spotify"
                        set player position to 0
                        previous track
                    end tell
                    """
                    try? await AppleScriptHelper.executeVoid(script)
                } else {
                    await NowPlayingController.sendUniversalCommand("send", arg: "5")
                    NowPlayingController.postMediaKeyEvent(for: 5)
                }
            }
            try? await Task.sleep(for: .milliseconds(350))
            self.forceUpdate()
        }
    }

    func seek(to position: TimeInterval) {
        let clamped = songDuration > 0 ? min(max(0, position), songDuration) : max(0, position)
        self.elapsedTime = clamped
        self.timestampDate = Date()
        Task {
            if let activeController = activeController {
                await activeController.seek(to: clamped)
            } else {
                await NowPlayingController.sendUniversalCommand("seek", arg: "\(Int64(clamped * 1_000_000))")
            }
        }
    }

    func skip(seconds: TimeInterval) {
        let currentPos = currentEstimatedTime
        let maxDuration = songDuration > 0 ? songDuration : Double.greatestFiniteMagnitude
        let newPos = min(max(0, currentPos + seconds), maxDuration)
        self.elapsedTime = newPos
        self.timestampDate = Date()
        seek(to: newPos)
    }

    func seekRelative(seconds: TimeInterval) {
        skip(seconds: seconds)
    }
    
    func setVolume(to level: Double) {
        let clamped = max(0.0, min(1.0, level))
        self.volume = clamped
        VolumeManager.shared.setAbsolute(Float32(clamped))
        if let controller = activeController {
            Task {
                await controller.setVolume(clamped)
            }
        }
    }
    func openMusicApp() {
        guard let bundleID = bundleIdentifier else {
            print("Error: appBundleIdentifier is nil")
            return
        }

        let workspace = NSWorkspace.shared
        if let appURL = workspace.urlForApplication(withBundleIdentifier: bundleID) {
            let configuration = NSWorkspace.OpenConfiguration()
            workspace.openApplication(at: appURL, configuration: configuration) { (app, error) in
                if let error = error {
                    print("Failed to launch app with bundle ID: \(bundleID), error: \(error)")
                } else {
                    print("Launched app with bundle ID: \(bundleID)")
                }
            }
        } else {
            print("Failed to find app with bundle ID: \(bundleID)")
        }
    }

    func forceUpdate() {
        // Request immediate update from the active controller
        Task { [weak self] in
            if self?.activeController?.isActive() == true {
                if let youtubeController = self?.activeController as? YouTubeMusicController {
                    await youtubeController.pollPlaybackState()
                } else {
                    await self?.activeController?.updatePlaybackInfo()
                }
            }
        }
    }
    
    
    func syncVolumeFromActiveApp() async {
        // Check if bundle identifier is valid and if the app is actually running
        guard let bundleID = bundleIdentifier, !bundleID.isEmpty,
              NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == bundleID }) else { return }
        
        var script: String?
        if bundleID == "com.apple.Music" {
            script = """
            tell application "Music"
                if it is running then
                    get sound volume
                else
                    return 50
                end if
            end tell
            """
        } else if bundleID == "com.spotify.client" {
            script = """
            tell application "Spotify"
                if it is running then
                    get sound volume
                else
                    return 50
                end if
            end tell
            """
        } else {
            // For unsupported apps, don't sync volume
            return
        }
        
        if let volumeScript = script,
           let result = try? await AppleScriptHelper.execute(volumeScript) {
            let volumeValue = result.int32Value
            let currentVolume = Double(volumeValue) / 100.0
            
            await MainActor.run {
                if abs(currentVolume - self.volume) > 0.01 {
                    self.volume = currentVolume
                }
            }
        }
    }
}

// MARK: - Universal Artwork Resolver & Memory Optimizer

/// Universal media artwork resolver for all media players, web browsers, and streaming platforms.
/// Automatically resolves official high-resolution album covers or video thumbnails when the host app does not embed artwork data.
public final class UniversalArtworkResolver {
    public static let shared = UniversalArtworkResolver()

    private let memoryCache = NSCache<NSString, NSData>()
    private let fileManager = FileManager.default
    private let diskCacheURL: URL?
    private let urlSession: URLSession

    private var inFlightTasks = [String: Task<Data?, Never>]()
    private let lock = NSLock()

    private init() {
        memoryCache.countLimit = 35
        memoryCache.totalCostLimit = 8 * 1024 * 1024 // 8 MB (downsampled covers are ~50-80 KB)

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 4.0
        config.timeoutIntervalForResource = 6.0
        config.requestCachePolicy = .returnCacheDataElseLoad
        self.urlSession = URLSession(configuration: config)

        if let cacheBase = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let dir = cacheBase.appendingPathComponent("NotchPulseMediaArtwork", isDirectory: true)
            let marker = dir.appendingPathComponent(".cache_purged_v553")
            if !fileManager.fileExists(atPath: marker.path) {
                try? fileManager.removeItem(at: dir)
                try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
                try? "v5.5.3".write(to: marker, atomically: true, encoding: .utf8)
            } else {
                try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            self.diskCacheURL = dir
        } else {
            self.diskCacheURL = nil
        }
    }

    // MARK: - Public API

    /// Downsamples raw image data to a max dimension (default 320px) with sub-sampling decode.
    /// This keeps artwork razor-sharp on Retina displays while cutting memory usage from 20-36 MB to ~50-80 KB.
    public func optimizeArtwork(_ data: Data, maxDimension: CGFloat = 320) -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return data
        }

        // If already within budget and compressed, return original
        if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
           let height = properties[kCGImagePropertyPixelHeight] as? CGFloat,
           width <= maxDimension && height <= maxDimension && data.count <= 100_000 {
            return data
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]

        guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary) else {
            return data
        }

        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        if let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.80]) {
            return jpeg
        }
        return data
    }

    /// Attempts to retrieve cached artwork data synchronously.
    public func cachedArtwork(title: String, artist: String) -> Data? {
        guard !isAdTitle(title: title, artist: artist) else { return nil }
        let key = cacheKey(title: title, artist: artist)
        guard !key.isEmpty else { return nil }

        lock.lock()
        if let mem = memoryCache.object(forKey: key as NSString) {
            lock.unlock()
            return mem as Data
        }
        lock.unlock()

        if let diskURL = diskFileURL(for: key),
           fileManager.fileExists(atPath: diskURL.path),
           let data = try? Data(contentsOf: diskURL) {
            lock.lock()
            memoryCache.setObject(data as NSData, forKey: key as NSString, cost: data.count)
            lock.unlock()
            return data
        }
        return nil
    }

    /// Stores artwork data in cache for a given title/artist pair.
    public func cacheArtworkData(_ data: Data, title: String, artist: String) {
        guard !isAdTitle(title: title, artist: artist) else { return }
        let key = cacheKey(title: title, artist: artist)
        guard !key.isEmpty else { return }

        let optimized = optimizeArtwork(data, maxDimension: 400)
        lock.lock()
        memoryCache.setObject(optimized as NSData, forKey: key as NSString, cost: optimized.count)
        lock.unlock()

        if let diskURL = diskFileURL(for: key) {
            DispatchQueue.global(qos: .background).async {
                try? optimized.write(to: diskURL, options: .atomic)
            }
        }
    }

    /// Asynchronously resolves high-resolution artwork for any media source.
    public func resolveArtwork(
        title: String,
        artist: String,
        album: String? = nil,
        bundleIdentifier: String? = nil,
        completion: @escaping (Data?) -> Void
    ) {
        guard !isAdTitle(title: title, artist: artist) else {
            completion(nil)
            return
        }

        let cleanTitle = sanitizeTitle(title)
        let cleanArtist = sanitizeArtist(artist)
        guard !cleanTitle.isEmpty else {
            completion(nil)
            return
        }

        let key = cacheKey(title: title, artist: artist)

        if let cached = cachedArtwork(title: title, artist: artist) {
            completion(cached)
            return
        }

        lock.lock()
        if let existingTask = inFlightTasks[key] {
            lock.unlock()
            Task {
                let data = await existingTask.value
                completion(data)
            }
            return
        }

        let lowerBundle = (bundleIdentifier ?? "").lowercased()
        let isBrowserSource = lowerBundle.contains("browser") || lowerBundle.contains("chrome")
            || lowerBundle.contains("safari") || lowerBundle.contains("arc") || lowerBundle.contains("edge")
            || lowerBundle.contains("brave") || lowerBundle.contains("opera") || lowerBundle.contains("vivaldi")
            || lowerBundle.contains("chromium") || lowerBundle.contains("zen") || lowerBundle.contains("firefox")
            || lowerBundle.contains("orion")

        let task = Task<Data?, Never> { [weak self] () -> Data? in
            guard let self = self else { return nil }

            if isBrowserSource {
                // 1. Direct browser extraction from active media tab (100% exact thumbnail)
                if let bundle = bundleIdentifier,
                   let directThumb = await self.fetchDirectBrowserYouTubeThumbnail(bundleIdentifier: bundle, targetTitle: cleanTitle) {
                    self.cacheArtworkData(directThumb, title: title, artist: artist)
                    return directThumb
                }

                // 2. High-precision YouTube search by video title
                if let ytData = await self.fetchFromYouTube(title: title, artist: artist) {
                    self.cacheArtworkData(ytData, title: title, artist: artist)
                    return ytData
                }

                // 3. Fallback to iTunes Store ONLY if artist is known to avoid mismatch
                if !cleanArtist.isEmpty, let itunesData = await self.fetchFromiTunes(title: cleanTitle, artist: cleanArtist) {
                    self.cacheArtworkData(itunesData, title: title, artist: artist)
                    return itunesData
                }
            } else {
                // Native media applications (Apple Music, Spotify, etc.)
                // 1. Official high-resolution album cover from iTunes Store or Deezer
                if let itunesData = await self.fetchFromiTunes(title: cleanTitle, artist: cleanArtist) {
                    self.cacheArtworkData(itunesData, title: title, artist: artist)
                    return itunesData
                }
                if let deezerData = await self.fetchFromDeezer(title: cleanTitle, artist: cleanArtist) {
                    self.cacheArtworkData(deezerData, title: title, artist: artist)
                    return deezerData
                }

                // 2. Fallback to YouTube video search
                if let ytData = await self.fetchFromYouTube(title: title, artist: artist) {
                    self.cacheArtworkData(ytData, title: title, artist: artist)
                    return ytData
                }
            }

            return nil
        }

        inFlightTasks[key] = task
        lock.unlock()

        Task {
            let result = await task.value
            self.lock.lock()
            self.inFlightTasks.removeValue(forKey: key)
            self.lock.unlock()
            completion(result)
        }
    }

    /// Purges in-flight tasks without dropping already cached artwork
    public func clearInFlight() {
        lock.lock()
        inFlightTasks.removeAll()
        lock.unlock()
    }

    /// Purges in-flight tasks and memory cache.
    public func clear() {
        lock.lock()
        inFlightTasks.removeAll()
        memoryCache.removeAllObjects()
        lock.unlock()
    }

    // MARK: - Direct Browser Integration

    /// Queries the browser window via AppleScript to extract the active YouTube watch URL and its thumbnail
    private func fetchDirectBrowserYouTubeThumbnail(bundleIdentifier: String, targetTitle: String) async -> Data? {
        // Browser scripting may be unavailable on the lock screen, but do not
        // block this path here: cached artwork or the resolver's iTunes/Deezer/
        // YouTube fallbacks can still provide the correct thumbnail.
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty else {
            return nil
        }

        let cleanTarget = targetTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTarget.isEmpty else { return nil }

        let escapedTarget = cleanTarget
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let lower = bundleIdentifier.lowercased()
        let isSafari = lower.contains("safari")
        let appName: String
        if isSafari {
            appName = "Safari"
        } else if lower.contains("chrome") {
            appName = "Google Chrome"
        } else if lower.contains("brave") {
            appName = "Brave Browser"
        } else if lower.contains("edge") {
            appName = "Microsoft Edge"
        } else if lower.contains("arc") || lower.contains("thebrowser") {
            appName = "Arc"
        } else {
            return nil
        }

        let isArc = (appName == "Arc")
        let script: String
        if isArc {
            script = """
            tell application "Arc"
                -- 1. Fast path: active tab of front window
                try
                    if (count of windows) > 0 then
                        tell front window to tell active tab
                            set u to (get URL)
                            if u contains "youtube.com/watch" or u contains "music.youtube.com" or u contains "youtu.be/" or u contains "youtube.com/shorts/" then
                                return u
                            end if
                        end tell
                    end if
                end try
                -- 2. Search windows and tabs by index
                repeat with winIdx from 1 to (count of windows)
                    repeat with tabIdx from 1 to (count of tabs of window winIdx)
                        set u to (get URL of tab tabIdx of window winIdx)
                        if u contains "youtube.com/watch" or u contains "music.youtube.com" or u contains "youtu.be/" or u contains "youtube.com/shorts/" then
                            tell window winIdx to tell tab tabIdx
                                set docTitle to execute javascript "document.title"
                                if "\(escapedTarget)" is "" or docTitle contains "\(escapedTarget)" or "\(escapedTarget)" contains docTitle then
                                    return u
                                end if
                            end tell
                        end if
                    end repeat
                end repeat
                -- 3. Fallback: first tab with youtube url
                repeat with winIdx from 1 to (count of windows)
                    repeat with tabIdx from 1 to (count of tabs of window winIdx)
                        set u to (get URL of tab tabIdx of window winIdx)
                        if u contains "youtube.com/watch" or u contains "music.youtube.com" or u contains "youtu.be/" or u contains "youtube.com/shorts/" then
                            return u
                        end if
                    end repeat
                end repeat
                return ""
            end tell
            """
        } else if isSafari {
            script = """
            tell application "\(appName)"
                -- 1. Fast path: current tab of front window
                try
                    if (count of windows) > 0 then
                        set curTab to current tab of front window
                        set u to (URL of curTab as text)
                        if u contains "youtube.com/watch" or u contains "music.youtube.com" or u contains "youtu.be/" or u contains "youtube.com/shorts/" then
                            return u
                        end if
                    end if
                end try
                -- 2. Search all tabs
                repeat with w in windows
                    repeat with t in tabs of w
                        set u to (URL of t as text)
                        if u contains "youtube.com/watch" or u contains "music.youtube.com" or u contains "youtu.be/" or u contains "youtube.com/shorts/" then
                            set docTitle to (do JavaScript "document.title" in t)
                            if "\(escapedTarget)" is "" or docTitle contains "\(escapedTarget)" or "\(escapedTarget)" contains docTitle then
                                return u
                            end if
                        end if
                    end repeat
                end repeat
                -- 3. Fallback: first tab with youtube url
                repeat with w in windows
                    repeat with t in tabs of w
                        set u to (URL of t as text)
                        if u contains "youtube.com/watch" or u contains "music.youtube.com" or u contains "youtu.be/" or u contains "youtube.com/shorts/" then
                            return u
                        end if
                    end repeat
                end repeat
                return ""
            end tell
            """
        } else {
            script = """
            tell application "\(appName)"
                -- 1. Fast path: active tab of front window
                try
                    if (count of windows) > 0 then
                        set curTab to active tab of front window
                        set u to (URL of curTab as text)
                        if u contains "youtube.com/watch" or u contains "music.youtube.com" or u contains "youtu.be/" or u contains "youtube.com/shorts/" then
                            return u
                        end if
                    end if
                end try
                -- 2. Search all tabs
                repeat with w in windows
                    repeat with t in tabs of w
                        set u to (URL of t as text)
                        if u contains "youtube.com/watch" or u contains "music.youtube.com" or u contains "youtu.be/" or u contains "youtube.com/shorts/" then
                            tell t
                                set docTitle to execute javascript "document.title"
                                if "\(escapedTarget)" is "" or docTitle contains "\(escapedTarget)" or "\(escapedTarget)" contains docTitle then
                                    return u
                                end if
                            end tell
                        end if
                    end repeat
                end repeat
                -- 3. Fallback: first tab with youtube url
                repeat with w in windows
                    repeat with t in tabs of w
                        set u to (URL of t as text)
                        if u contains "youtube.com/watch" or u contains "music.youtube.com" or u contains "youtu.be/" or u contains "youtube.com/shorts/" then
                            return u
                        end if
                    end repeat
                end repeat
                return ""
            end tell
            """
        }

        do {
            guard let res = try await AppleScriptHelper.execute(script),
                  let urlStr = res.stringValue, !urlStr.isEmpty else {
                return nil
            }

            var foundVideoID: String?
            let ytPatterns = [
                #"[?&]v=([a-zA-Z0-9_-]{11})"#,
                #"youtu\.be\/([a-zA-Z0-9_-]{11})"#,
                #"\/shorts\/([a-zA-Z0-9_-]{11})"#,
                #"\/embed\/([a-zA-Z0-9_-]{11})"#
            ]
            for pat in ytPatterns {
                if let regex = try? NSRegularExpression(pattern: pat, options: []),
                   let match = regex.firstMatch(in: urlStr, options: [], range: NSRange(location: 0, length: (urlStr as NSString).length)),
                   match.numberOfRanges >= 2 {
                    foundVideoID = (urlStr as NSString).substring(with: match.range(at: 1))
                    break
                }
            }

            guard let vId = foundVideoID, vId.count == 11 else {
                return nil
            }

            let candidateURLs = [
                "https://i.ytimg.com/vi/\(vId)/maxresdefault.jpg",
                "https://i.ytimg.com/vi/\(vId)/hq720.jpg",
                "https://i.ytimg.com/vi/\(vId)/hqdefault.jpg",
                "https://i.ytimg.com/vi/\(vId)/mqdefault.jpg"
            ]

            for thumbUrlStr in candidateURLs {
                if let thumbURL = URL(string: thumbUrlStr),
                   let imgData = await downloadImage(from: thumbURL) {
                    return imgData
                }
            }
        } catch {
            return nil
        }
        return nil
    }

    // MARK: - Resolvers

    /// Queries Apple's public iTunes Search API for official high-resolution album cover art
    private func fetchFromiTunes(title: String, artist: String) async -> Data? {
        var queryTerms: [String] = []
        if !artist.isEmpty {
            queryTerms.append("\(artist) \(title)")
        }
        queryTerms.append(title)

        for term in queryTerms {
            guard var components = URLComponents(string: "https://itunes.apple.com/search") else { continue }
            components.queryItems = [
                URLQueryItem(name: "term", value: term),
                URLQueryItem(name: "entity", value: "song"),
                URLQueryItem(name: "limit", value: "3")
            ]
            guard let url = components.url else { continue }

            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")

            do {
                let (data, response) = try await urlSession.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { continue }

                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let results = json["results"] as? [[String: Any]] {
                    for item in results {
                        let resultArtist = (item["artistName"] as? String ?? "").lowercased()
                        let resultTrack = (item["trackName"] as? String ?? "").lowercased()
                        let reqArt = artist.lowercased()
                        let reqTit = title.lowercased()

                        let artistMatches = reqArt.isEmpty || resultArtist.contains(reqArt) || reqArt.contains(resultArtist)
                        let titleMatches = reqTit.contains(resultTrack) || resultTrack.contains(reqTit)

                        // Discard irrelevant matches
                        if !reqArt.isEmpty && !artistMatches {
                            continue
                        }
                        if !titleMatches {
                            continue
                        }

                        if let artUrlStr = item["artworkUrl100"] as? String {
                            let highResStr = artUrlStr.replacingOccurrences(of: "100x100bb", with: "600x600bb")
                            if let imgUrl = URL(string: highResStr),
                                let imgData = await downloadImage(from: imgUrl) {
                                return imgData
                            }
                        }
                    }
                }
            } catch {
                continue
            }
        }
        return nil
    }

    /// Queries YouTube search to extract the official high-resolution video thumbnail
    /// Parses ytInitialData JSON to target videoRenderer only, strictly avoiding all ads (promotedVideoRenderer / adSlotRenderer)
    private func fetchFromYouTube(title: String, artist: String) async -> Data? {
        var query = sanitizeTitle(title)
        let cleanArt = sanitizeArtist(artist)
        if !cleanArt.isEmpty && cleanArt.lowercased() != "youtube" && !query.lowercased().contains(cleanArt.lowercased()) {
            query = "\(query) \(cleanArt)"
        }

        guard var components = URLComponents(string: "https://www.youtube.com/results") else {
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: "search_query", value: query)
        ]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("vi-VN,vi;q=0.9,en-US;q=0.8,en;q=0.7", forHTTPHeaderField: "Accept-Language")

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let html = String(data: data, encoding: .utf8) else { return nil }

            var candidateVideoIds: [String] = []

            // 1. Structured JSON parsing via ytInitialData
            if let ytData = extractInitialData(from: html) {
                let parsed = extractVideosFromInitialData(ytData, targetTitle: title, targetArtist: cleanArt)
                if !parsed.isEmpty {
                    candidateVideoIds = parsed
                }
            }

            // 2. Targeted regex matching "videoRenderer" (never matches promotedVideoRenderer or adSlotRenderer)
            if candidateVideoIds.isEmpty {
                let pattern = #""videoRenderer":\{.*?"videoId":"([a-zA-Z0-9_-]{11})""#
                if let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) {
                    let nsString = html as NSString
                    let matches = regex.matches(in: html, options: [], range: NSRange(location: 0, length: nsString.length))
                    for m in matches {
                        if m.numberOfRanges >= 2 {
                            let vid = nsString.substring(with: m.range(at: 1))
                            if !candidateVideoIds.contains(vid) {
                                candidateVideoIds.append(vid)
                            }
                        }
                    }
                }
            }

            // 3. Fallback: direct videoId capture from results
            if candidateVideoIds.isEmpty {
                let broadPattern = #""videoId":"([a-zA-Z0-9_-]{11})""#
                if let regex = try? NSRegularExpression(pattern: broadPattern, options: []) {
                    let nsString = html as NSString
                    let matches = regex.matches(in: html, options: [], range: NSRange(location: 0, length: nsString.length))
                    for m in matches {
                        if m.numberOfRanges >= 2 {
                            let vid = nsString.substring(with: m.range(at: 1))
                            if !candidateVideoIds.contains(vid) {
                                candidateVideoIds.append(vid)
                            }
                        }
                    }
                }
            }

            for vId in candidateVideoIds.prefix(4) {
                let candidateURLs = [
                    "https://i.ytimg.com/vi/\(vId)/maxresdefault.jpg",
                    "https://i.ytimg.com/vi/\(vId)/hq720.jpg",
                    "https://i.ytimg.com/vi/\(vId)/hqdefault.jpg",
                    "https://i.ytimg.com/vi/\(vId)/mqdefault.jpg"
                ]

                for thumbUrlStr in candidateURLs {
                    if let thumbURL = URL(string: thumbUrlStr),
                       let imgData = await downloadImage(from: thumbURL) {
                        return imgData
                    }
                }
            }
        } catch {
            return nil
        }
        return nil
    }

    private func extractInitialData(from html: String) -> [String: Any]? {
        let patterns = [
            #"var ytInitialData\s*=\s*(\{.*?\});</script>"#,
            #"window\["ytInitialData"\]\s*=\s*(\{.*?\});</script>"#,
            #"(?:var\s+|window\["ytInitialData"\]\s*=\s*|ytInitialData\s*=\s*)(\{.*?\});"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
                  let match = regex.firstMatch(in: html, options: [], range: NSRange(location: 0, length: (html as NSString).length)),
                  match.numberOfRanges >= 2 else { continue }

            let jsonString = (html as NSString).substring(with: match.range(at: 1))
            if let jsonData = jsonString.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                return json
            }
        }
        return nil
    }

    private func extractVideosFromInitialData(_ data: [String: Any], targetTitle: String, targetArtist: String) -> [String] {
        guard let contents = data["contents"] as? [String: Any],
              let twoCol = contents["twoColumnSearchResultsRenderer"] as? [String: Any],
              let primary = twoCol["primaryContents"] as? [String: Any],
              let secList = primary["sectionListRenderer"] as? [String: Any],
              let sections = secList["contents"] as? [[String: Any]] else {
            return []
        }

        var scoredVideos: [(videoId: String, score: Int)] = []
        let lowerTargetTitle = targetTitle.lowercased()
        let lowerTargetArtist = targetArtist.lowercased()
        let words = Set(lowerTargetTitle.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count > 1 })

        for sec in sections {
            guard let itemSection = sec["itemSectionRenderer"] as? [String: Any],
                  let items = itemSection["contents"] as? [[String: Any]] else { continue }

            for item in items {
                guard let vr = item["videoRenderer"] as? [String: Any],
                      let videoId = vr["videoId"] as? String, !videoId.isEmpty else {
                    continue
                }

                var titleText = ""
                if let titleDict = vr["title"] as? [String: Any] {
                    if let runs = titleDict["runs"] as? [[String: Any]] {
                        titleText = runs.compactMap { $0["text"] as? String }.joined()
                    } else if let simple = titleDict["simpleText"] as? String {
                        titleText = simple
                    }
                }

                var channelText = ""
                if let ownerDict = vr["ownerText"] as? [String: Any],
                   let runs = ownerDict["runs"] as? [[String: Any]] {
                    channelText = runs.compactMap { $0["text"] as? String }.joined()
                }

                let lowerTitle = titleText.lowercased()
                let lowerChannel = channelText.lowercased()

                var score = 0
                if !lowerTargetArtist.isEmpty && (lowerChannel.contains(lowerTargetArtist) || lowerTargetArtist.contains(lowerChannel)) {
                    score += 50
                }

                for word in words {
                    if lowerTitle.contains(word) {
                        score += 10
                    }
                }

                scoredVideos.append((videoId: videoId, score: score))
            }
        }

        scoredVideos.sort { $0.score > $1.score }
        return scoredVideos.map { $0.videoId }
    }

    /// Queries Deezer public API for cover art
    private func fetchFromDeezer(title: String, artist: String) async -> Data? {
        let query = !artist.isEmpty ? "\(artist) \(title)" : title
        guard var components = URLComponents(string: "https://api.deezer.com/search") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: "3")
        ]
        guard let url = components.url else { return nil }

        do {
            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let results = json["data"] as? [[String: Any]] {
                for item in results {
                    let resultArtist = ((item["artist"] as? [String: Any])?["name"] as? String ?? "").lowercased()
                    let resultTrack = (item["title"] as? String ?? "").lowercased()
                    let reqArt = artist.lowercased()
                    let reqTit = title.lowercased()

                    let artistMatches = reqArt.isEmpty || resultArtist.contains(reqArt) || reqArt.contains(resultArtist)
                    let titleMatches = reqTit.contains(resultTrack) || resultTrack.contains(reqTit)

                    if !reqArt.isEmpty && !artistMatches {
                        continue
                    }
                    if !titleMatches {
                        continue
                    }

                    if let album = item["album"] as? [String: Any],
                       let coverUrlStr = (album["cover_xl"] as? String) ?? (album["cover_big"] as? String) ?? (album["cover_medium"] as? String),
                       let coverURL = URL(string: coverUrlStr),
                       let imgData = await downloadImage(from: coverURL) {
                        return imgData
                    }
                }
            }
        } catch {
            return nil
        }
        return nil
    }

    /// Downloads and validates an image from a URL, automatically optimized to max 500px
    private func downloadImage(from url: URL) async -> Data? {
        do {
            var req = URLRequest(url: url)
            req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await urlSession.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, data.count > 2048 else {
                return nil
            }
            guard NSImage(data: data) != nil else { return nil }
            return optimizeArtwork(data, maxDimension: 500)
        } catch {
            return nil
        }
    }

    // MARK: - Sanitization & Helpers

    private func isAdTitle(title: String, artist: String) -> Bool {
        let lowerT = title.lowercased()
        let lowerA = artist.lowercased()
        let adKeywords = ["advertisement", "quảng cáo", "sponsor", "skip ad", "ad ·"]
        for kw in adKeywords {
            if lowerT.contains(kw) || lowerA.contains(kw) {
                return true
            }
        }
        if lowerT == "ad" || lowerA == "ad" {
            return true
        }
        return false
    }

    private func sanitizeTitle(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "\"“”'"))

        // First strip trailing platform/service noise from browser window titles
        s = s.replacingOccurrences(of: #"(?i)\s*-\s*(youtube\s*music|youtube|soundcloud|spotify|topic)$"#, with: "", options: .regularExpression)

        let parts = s.components(separatedBy: " - ")
        if parts.count == 2 {
            let left = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let right = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            s = "\(left) \(right)"
        }

        // Only remove trailing media descriptor labels after | (e.g. | Official MV, | Lyrics, | Audio, | 4K)
        // Never remove track names or playlist contents separated by |
        let noisePatterns = [
            #"(?i)\|\s*(official\s*(music\s*video|mv|video|audio)?|mv|lyrics?|visualizer|remix|hd|4k|live).*$"#,
            #"(?i)\[.*?official.*?\]"#,
            #"(?i)\(.*?(official|music video|mv|audio|video|lyric|lyrics|visualizer|remix).*?\)"#,
            #"(?i)\[.*?(mv|official|lyrics|hd|4k|audio|remix).*?\]"#,
            #"(?i)\b(official music video|official mv|official video|official audio|lyric video|lyrics video|audio visualizer)\b"#,
            #"(?i)\b(4k|hd|full hd|1080p|60fps)\b"#
        ]

        for pat in noisePatterns {
            s = s.replacingOccurrences(of: pat, with: "", options: .regularExpression)
        }

        // Replace any remaining | with space so words aren't glued together
        s = s.replacingOccurrences(of: "|", with: " ")
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)

        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sanitizeArtist(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.lowercased() == "unknown artist" || s.lowercased() == "youtube" {
            return ""
        }
        s = s.replacingOccurrences(of: #"(?i)\s*-\s*topic$"#, with: "", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func cacheKey(title: String, artist: String) -> String {
        let cleanTitle = sanitizeTitle(title)
        let cleanArtist = sanitizeArtist(artist)
        let raw = "\(cleanTitle.lowercased())_\(cleanArtist.lowercased())"
        let allowed = CharacterSet.alphanumerics
        return raw.unicodeScalars
            .map { allowed.contains($0) ? Character($0) : "_" }
            .reduce(into: "") { $0.append($1) }
    }

    private func diskFileURL(for key: String) -> URL? {
        return diskCacheURL?.appendingPathComponent("\(key).jpg")
    }
}
