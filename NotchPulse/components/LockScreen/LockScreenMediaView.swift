import AppKit
import Combine
import Defaults
import SwiftUI

struct LockScreenMediaView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject var volumeManager = VolumeManager.shared
    @ObservedObject var windowController: LockScreenMediaWindow
    
    @Default(.musicControlSlots) private var slotConfig
    @Default(.musicControlSlotLimit) private var slotLimit
    @Default(.lockScreenPlayerShowLyrics) private var lockScreenPlayerShowLyrics
    @Default(.sliderColor) private var sliderColor
    @Default(.playerColorTinting) private var playerColorTinting
    
    @State private var activeLyricIndex: Int = 0
    @State private var compactSliderValue: Double = 0
    @State private var compactDragging: Bool = false
    @State private var compactLastDragged: Date = .distantPast
    
    @State private var fullSliderValue: Double = 0
    @State private var fullDragging: Bool = false
    @State private var fullLastDragged: Date = .distantPast
    
    @State private var showCompactVolumeSlider: Bool = false
    @State private var showFullScreenVolumeSlider: Bool = false
    
    private let lyricsTimer = Timer.publish(every: 0.35, tolerance: 0.1, on: .main, in: .common).autoconnect()
    
    private var isLightMode: Bool {
        windowController.isLightMode
    }
    
    private var compactArtistColor: Color {
        if playerColorTinting {
            return isLightMode
                ? Color(nsColor: musicManager.avgColor).ensureMaximumBrightness(factor: 0.35)
                : Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.75)
        }
        return .secondary
    }
    
    var body: some View {
        ZStack(alignment: .center) {
            if windowController.isFullScreen {
                fullScreenPlayerView
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                compactPlayerView
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .onReceive(DistributedNotificationCenter.default().publisher(for: NSNotification.Name("AppleInterfaceThemeChangedNotification"))) { _ in
            windowController.syncTheme()
        }
        .onChange(of: colorScheme) { _, _ in
            windowController.syncTheme()
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85, blendDuration: 0), value: windowController.isFullScreen)
        .onAppear {
            windowController.syncTheme()
            musicManager.ensureLyricsLoaded()
        }
        .onChange(of: musicManager.songTitle) { _, _ in
            activeLyricIndex = 0
            musicManager.ensureLyricsLoaded()
        }
        .onChange(of: windowController.isFullScreen) { _, isFull in
            if isFull {
                let elapsed = musicManager.estimatedPlaybackPosition(at: Date())
                activeLyricIndex = musicManager.currentLyricIndex(at: elapsed) ?? 0
            }
        }
        .onReceive(lyricsTimer) { date in
            guard windowController.isWindowVisible && windowController.isFullScreen && musicManager.isPlaying && !musicManager.syncedLyrics.isEmpty else { return }
            let elapsed = musicManager.estimatedPlaybackPosition(at: date)
            if let idx = musicManager.currentLyricIndex(at: elapsed) {
                if activeLyricIndex != idx {
                    activeLyricIndex = idx
                }
            }
        }
    }
    
    // =========================================================================
    // MARK: - 1. Compact Player View (Apple HIG Native Lock Screen Widget)
    // =========================================================================
    
    private var compactAlbumArtView: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(nsImage: musicManager.albumArt)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 54, height: 54)
                .overlay {
                    if !musicManager.isPlaying {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.black.opacity(0.30))
                            .allowsHitTesting(false)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                )
            
            if !musicManager.usingAppIconForArtwork && !musicManager.songTitle.isEmpty {
                AppIcon(for: musicManager.bundleIdentifier ?? "com.apple.Music")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
                    )
                    .offset(x: 3, y: 3)
            }
        }
        .scaleEffect(musicManager.isPlaying ? 1.0 : 0.94)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: musicManager.isPlaying)
    }

    private var compactHeaderRow: some View {
        HStack(alignment: .center, spacing: 12) {
            compactAlbumArtView
            
            VStack(alignment: .leading, spacing: 3) {
                Text(musicManager.songTitle.isEmpty ? (musicManager.isPlayerIdle ? loc("Not Playing") : "") : musicManager.songTitle)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 270, alignment: .leading)
                
                Text(musicManager.artistName)
                    .font(.subheadline)
                    .foregroundStyle(compactArtistColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 290, alignment: .leading)
            }
            
            Spacer(minLength: 4)
        }
    }

    private func resolveCompactLyricText(elapsed: Double) -> (text: String, isPersian: Bool) {
        let line: String
        if musicManager.isFetchingLyrics {
            line = loc("Loading lyrics…")
        } else if !musicManager.syncedLyrics.isEmpty {
            line = musicManager.lyricLine(at: elapsed)
        } else {
            let trimmed = musicManager.currentLyrics.trimmingCharacters(in: .whitespacesAndNewlines)
            line = trimmed.isEmpty ? "♪  ♫  ♪" : trimmed.replacingOccurrences(of: "\n", with: " ")
        }
        let cleanText = MusicManager.stripLRCTimestamps(from: line)
        let displayText = cleanText.isEmpty ? "♪  ♫  ♪" : cleanText
        let isPersian = displayText.unicodeScalars.contains { $0.value >= 0x0600 && $0.value <= 0x06FF }
        return (displayText, isPersian)
    }

    @ViewBuilder
    private var compactLyricsRow: some View {
        TimelineView(.animation(minimumInterval: 0.25, paused: musicManager.playbackRate <= 0 || musicManager.syncedLyrics.isEmpty)) { timeline in
            let effectiveElapsed = compactDragging
                ? compactSliderValue
                : musicManager.estimatedPlaybackPosition(at: timeline.date)
            let activeIndex = musicManager.currentLyricIndex(at: effectiveElapsed)
            let lyric = resolveCompactLyricText(elapsed: effectiveElapsed)
            
            HStack(spacing: 6) {
                Image(systemName: "quote.bubble.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tint)
                
                Text(lyric.text)
                    .id(activeIndex != nil ? "compact-lyric-\(activeIndex!)" : "compact-lyric-\(lyric.text)")
                    .font(lyric.isPersian ? .custom("Vazirmatn-Regular", size: 12) : .caption.weight(.medium))
                    .foregroundStyle(activeIndex != nil ? .primary : .secondary)
                    .lineLimit(1)
                    .transition(.opacity.combined(with: .offset(y: 2)))
                    .animation(.easeInOut(duration: 0.25), value: activeIndex)
                
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.quaternary.opacity(0.45), in: Capsule())
        }
    }

    private var compactScrubberRow: some View {
        TimelineView(.animation(minimumInterval: 0.5, paused: musicManager.playbackRate <= 0)) { timeline in
            let currentEstimated = musicManager.estimatedPlaybackPosition(at: timeline.date)
            
            LockScreenScrubberView(
                sliderValue: $compactSliderValue,
                dragging: $compactDragging,
                lastDragged: $compactLastDragged,
                duration: max(1.0, musicManager.songDuration),
                color: musicManager.avgColor,
                estimatedPlaybackTime: currentEstimated,
                isCompact: true,
                isLight: isLightMode,
                onValueChange: { newValue in
                    musicManager.seek(to: newValue)
                }
            )
        }
    }

    private var compactControlsRow: some View {
        HStack(spacing: 0) {
            Spacer()
            
            let slots = activeSlots
            HStack(spacing: slots.count > 3 ? 18 : 26) {
                ForEach(Array(slots.enumerated()), id: \.offset) { _, slot in
                    compactSlotButton(for: slot)
                }
                if !slots.contains(.volume) {
                    compactVolumeButton
                }
            }
            
            Spacer()
        }
    }

    private var compactPlayerView: some View {
        let hasLyrics = lockScreenPlayerShowLyrics && (
            !musicManager.syncedLyrics.isEmpty ||
            !musicManager.currentLyrics.isEmpty
        )
        
        return VStack(spacing: 10) {
            compactHeaderRow
            
            if hasLyrics {
                compactLyricsRow
            }
            
            compactScrubberRow
            
            compactControlsRow
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(width: LockScreenMediaWindow.compactCardWidth, height: hasLyrics ? 228 : 190)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.separator.opacity(0.35), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
    
    // =========================================================================
    // MARK: - 2. Full-Screen Immersive Player View (Apple Music Style Karaoke)
    // =========================================================================
    
    private var fullScreenPlayerView: some View {
        ZStack {
            ambientDynamicBackground
            
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let albumSize = min(max(h * 0.44, 280), 520)
                let contentWidth = w * 0.85
                let hasLyrics = !musicManager.syncedLyrics.isEmpty || !musicManager.currentLyrics.isEmpty
                
                VStack(spacing: 0) {
                    Spacer()
                    
                    HStack(alignment: .center, spacing: w * 0.06) {
                        if hasLyrics {
                            fullScreenLeftColumn(albumSize: albumSize)
                                .frame(width: contentWidth * 0.44)
                            
                            fullScreenLyricsColumn(columnWidth: contentWidth * 0.52, viewHeight: h * 0.72)
                                .frame(width: contentWidth * 0.52)
                        } else {
                            fullScreenLeftColumn(albumSize: albumSize)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                    .padding(.horizontal, w * 0.075)
                    
                    Spacer()
                }
                .frame(width: w, height: h)
            }
        }
        .ignoresSafeArea()
    }
    
    private var ambientDynamicBackground: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                
                Image(nsImage: musicManager.albumArt)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .scaleEffect(1.3)
                    .blur(radius: 70, opaque: true)
                
                Rectangle()
                    .fill(.ultraThinMaterial)
                
                Color.black.opacity(0.30)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .onTapGesture {
                windowController.setFullScreen(false)
            }
            .clipped()
            .animation(.easeInOut(duration: 0.5), value: musicManager.albumArt)
        }
        .ignoresSafeArea()
    }
    
    private func fullScreenLeftColumn(albumSize: CGFloat) -> some View {
        VStack(spacing: albumSize * 0.07) {
            Button {
                windowController.setFullScreen(false)
            } label: {
                ZStack(alignment: .bottomTrailing) {
                    Image(nsImage: musicManager.albumArt)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: albumSize, height: albumSize)
                        .overlay {
                            if !musicManager.isPlaying {
                                RoundedRectangle(cornerRadius: albumSize * 0.08, style: .continuous)
                                    .fill(Color.black.opacity(0.30))
                                    .allowsHitTesting(false)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: albumSize * 0.08, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: albumSize * 0.08, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
                        )
                        .shadow(color: .black.opacity(0.35), radius: 24, x: 0, y: 12)
                    
                    if !musicManager.usingAppIconForArtwork && !musicManager.songTitle.isEmpty {
                        AppIcon(for: musicManager.bundleIdentifier ?? "com.apple.Music")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: albumSize * 0.11, height: albumSize * 0.11)
                            .clipShape(RoundedRectangle(cornerRadius: albumSize * 0.025, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: albumSize * 0.025, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
                            )
                            .offset(x: albumSize * 0.02, y: albumSize * 0.02)
                    }
                }
                .scaleEffect(musicManager.isPlaying ? 1.0 : 0.94)
                .animation(.spring(response: 0.35, dampingFraction: 0.75), value: musicManager.isPlaying)
            }
            .buttonStyle(.plain)
            .help(loc("Click artwork to collapse"))
            
            VStack(spacing: albumSize * 0.02) {
                Text(musicManager.songTitle.isEmpty ? (musicManager.isPlayerIdle ? loc("Not Playing") : "") : musicManager.songTitle)
                    .font(.system(size: max(albumSize * 0.075, 20), weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.center)
                
                Text(musicManager.artistName)
                    .font(.system(size: max(albumSize * 0.052, 15), weight: .medium, design: .rounded))
                    .foregroundStyle(Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.82))
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                if !musicManager.album.isEmpty {
                    Text(musicManager.album)
                        .font(.system(size: max(albumSize * 0.04, 12), weight: .regular))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            
            TimelineView(.animation(minimumInterval: 0.5, paused: musicManager.playbackRate <= 0)) { timeline in
                let currentEstimated = musicManager.estimatedPlaybackPosition(at: timeline.date)
                
                LockScreenScrubberView(
                    sliderValue: $fullSliderValue,
                    dragging: $fullDragging,
                    lastDragged: $fullLastDragged,
                    duration: max(1.0, musicManager.songDuration),
                    color: musicManager.avgColor,
                    estimatedPlaybackTime: currentEstimated,
                    isCompact: false,
                    onValueChange: { newValue in
                        musicManager.seek(to: newValue)
                    }
                )
                .frame(width: albumSize * 1.3)
            }
            
            let slots = activeSlots
            HStack(spacing: slots.count > 3 ? 20 : 28) {
                ForEach(Array(slots.enumerated()), id: \.offset) { _, slot in
                    fullScreenSlotButton(for: slot)
                }
                if !slots.contains(.volume) {
                    fullScreenVolumeButton
                }
            }
        }
    }
    
    @ViewBuilder
    private func fullScreenLyricsColumn(columnWidth: CGFloat, viewHeight: CGFloat) -> some View {
        let baseFontSize = min(max(columnWidth * 0.065, 24), 48)
        let activeFontSize = baseFontSize + 2
        let inactiveFontSize = baseFontSize
        
        VStack(alignment: .leading, spacing: 14) {
            if musicManager.isFetchingLyrics {
                HStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.7)
                }
                .padding(.bottom, 8)
            }
            
            if !musicManager.syncedLyrics.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 22) {
                            ForEach(Array(musicManager.syncedLyrics.enumerated()), id: \.offset) { index, item in
                                let isCurrent = (index == activeLyricIndex)
                                let isPast = (index < activeLyricIndex)
                                
                                Button {
                                    musicManager.seek(to: item.time)
                                } label: {
                                    Text(MusicManager.stripLRCTimestamps(from: item.text))
                                        .font(.system(size: isCurrent ? activeFontSize : inactiveFontSize, weight: isCurrent ? .bold : .medium, design: .rounded))
                                        .foregroundStyle(
                                            isCurrent
                                            ? Color.white
                                            : isPast
                                            ? Color.white.opacity(0.35)
                                            : Color.white.opacity(0.65)
                                        )
                                        .multilineTextAlignment(.leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .padding(.vertical, 4)
                                        .animation(.easeInOut(duration: 0.25), value: isCurrent)
                                }
                                .buttonStyle(.plain)
                                .id(index)
                            }
                        }
                        .padding(.vertical, viewHeight * 0.4)
                    }
                    .onChange(of: activeLyricIndex) { _, newIdx in
                        withAnimation(.smooth(duration: 0.45)) {
                            proxy.scrollTo(newIdx, anchor: .center)
                        }
                    }
                    .onAppear {
                        scheduleMultiPassScroll(proxy: proxy, forceTop: false)
                    }
                    .onChange(of: musicManager.songTitle) { _, _ in
                        scheduleMultiPassScroll(proxy: proxy, forceTop: true)
                    }
                    .onChange(of: windowController.isFullScreen) { _, isFull in
                        if isFull {
                            scheduleMultiPassScroll(proxy: proxy, forceTop: false)
                        }
                    }
                }
            } else if !musicManager.currentLyrics.isEmpty {
                ScrollView(.vertical, showsIndicators: false) {
                    Text(MusicManager.stripLRCTimestamps(from: musicManager.currentLyrics))
                        .font(.system(size: max(columnWidth * 0.04, 18), weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.8))
                        .lineSpacing(10)
                        .padding(.vertical, viewHeight * 0.4)
                }
            } else {
                VStack(spacing: 14) {
                    Spacer()
                    Image(systemName: "music.note.list")
                        .font(.system(size: 44))
                        .foregroundStyle(.white.opacity(0.3))
                    Text(musicManager.isPlaying ? loc("Playing Music") : loc("Paused"))
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(height: viewHeight)
    }

    // =========================================================================
    // MARK: - Control Buttons
    // =========================================================================
    
    private var activeSlots: [MusicControlButton] {
        let sanitizedLimit = min(
            max(slotLimit, MusicControlButton.minSlotCount),
            MusicControlButton.maxSlotCount
        )
        let padded = slotConfig.padded(to: sanitizedLimit, filler: .none)
        return Array(padded.prefix(sanitizedLimit)).filter { $0 != .none }
    }
    
    @ViewBuilder
    private func compactSlotButton(for slot: MusicControlButton) -> some View {
        switch slot {
        case .shuffle:
            LockScreenButton(
                icon: "shuffle",
                iconColor: musicManager.isShuffled ? .tint : .secondary,
                size: 28,
                action: { musicManager.toggleShuffle() }
            )
        case .previous:
            LockScreenButton(
                icon: "backward.fill",
                iconColor: .primary,
                size: 30,
                action: { musicManager.previousTrack() }
            )
        case .playPause:
            LockScreenButton(
                icon: musicManager.isPlaying ? "pause.fill" : "play.fill",
                iconColor: .primary,
                size: 38,
                isPrimary: true,
                action: {
                    musicManager.togglePlay()
                }
            )
        case .next:
            LockScreenButton(
                icon: "forward.fill",
                iconColor: .primary,
                size: 30,
                action: { musicManager.nextTrack() }
            )
        case .repeatMode:
            LockScreenButton(
                icon: repeatIcon,
                iconColor: musicManager.repeatMode == .off ? .secondary : .tint,
                size: 28,
                action: { musicManager.toggleRepeat() }
            )
        case .volume:
            compactVolumeButton
        case .favorite:
            LockScreenButton(
                icon: musicManager.isFavoriteTrack ? "heart.fill" : "heart",
                iconColor: musicManager.isFavoriteTrack ? .red : .secondary,
                size: 28,
                disabled: !musicManager.canFavoriteTrack,
                action: { musicManager.toggleFavoriteTrack() }
            )
        case .goBackward:
            LockScreenButton(
                icon: "gobackward.15",
                iconColor: .secondary,
                size: 28,
                action: { musicManager.skip(seconds: -15) }
            )
        case .goForward:
            LockScreenButton(
                icon: "goforward.15",
                iconColor: .secondary,
                size: 28,
                action: { musicManager.skip(seconds: 15) }
            )
        case .none:
            EmptyView()
        }
    }
    
    @ViewBuilder
    private func fullScreenSlotButton(for slot: MusicControlButton) -> some View {
        switch slot {
        case .shuffle:
            LockScreenButton(
                icon: "shuffle",
                iconColor: musicManager.isShuffled ? .tint : .white.opacity(0.85),
                size: 32,
                action: { musicManager.toggleShuffle() }
            )
        case .previous:
            LockScreenButton(
                icon: "backward.fill",
                iconColor: .white,
                size: 36,
                action: { musicManager.previousTrack() }
            )
        case .playPause:
            Button {
                musicManager.togglePlay()
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.22))
                        .frame(width: 58, height: 58)
                    Image(systemName: musicManager.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(.white)
                        .offset(x: musicManager.isPlaying ? 0 : 1)
                }
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
        case .next:
            LockScreenButton(
                icon: "forward.fill",
                iconColor: .white,
                size: 36,
                action: { musicManager.nextTrack() }
            )
        case .repeatMode:
            LockScreenButton(
                icon: repeatIcon,
                iconColor: musicManager.repeatMode == .off ? .white.opacity(0.85) : .red,
                size: 32,
                action: { musicManager.toggleRepeat() }
            )
        case .favorite:
            LockScreenButton(
                icon: musicManager.isFavoriteTrack ? "heart.fill" : "heart",
                iconColor: musicManager.isFavoriteTrack ? .red : .white.opacity(0.85),
                size: 32,
                disabled: !musicManager.canFavoriteTrack,
                action: { musicManager.toggleFavoriteTrack() }
            )
        case .goBackward:
            LockScreenButton(
                icon: "gobackward.15",
                iconColor: .white.opacity(0.85),
                size: 32,
                action: { musicManager.skip(seconds: -15) }
            )
        case .goForward:
            LockScreenButton(
                icon: "goforward.15",
                iconColor: .white.opacity(0.85),
                size: 32,
                action: { musicManager.skip(seconds: 15) }
            )
        case .volume:
            fullScreenVolumeButton
        case .none:
            EmptyView()
        }
    }
    
    private var compactVolumeButton: some View {
        HStack(spacing: 4) {
            LockScreenButton(
                icon: volumeIcon,
                iconColor: isCurrentlyMuted ? .tertiary : .secondary,
                size: 28,
                action: {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        showCompactVolumeSlider.toggle()
                    }
                }
            )
            .background(
                SliderScrollWheelRepresentable { deltaStep in
                    let step = Float32(deltaStep) * 0.02
                    VolumeManager.shared.adjustRelative(delta: step)
                }
            )
            
            if showCompactVolumeSlider {
                LockScreenVolumeSlider(
                    volume: Binding(
                        get: { Double(volumeManager.rawVolume) },
                        set: { newValue in
                            musicManager.setVolume(to: newValue)
                        }
                    ),
                    isLight: isLightMode,
                    isCompact: true
                )
                .frame(width: 58, height: 14)
                .background(
                    SliderScrollWheelRepresentable { deltaStep in
                        let step = Float32(deltaStep) * 0.02
                        VolumeManager.shared.adjustRelative(delta: step)
                    }
                )
                .transition(.scale.combined(with: .opacity))
            }
        }
    }
    
    private var fullScreenVolumeButton: some View {
        HStack(spacing: 6) {
            LockScreenButton(
                icon: volumeIcon,
                iconColor: isCurrentlyMuted ? .gray : .white.opacity(0.85),
                size: 32,
                action: {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        showFullScreenVolumeSlider.toggle()
                    }
                }
            )
            .background(
                SliderScrollWheelRepresentable { deltaStep in
                    let step = Float32(deltaStep) * 0.02
                    VolumeManager.shared.adjustRelative(delta: step)
                }
            )
            
            if showFullScreenVolumeSlider {
                LockScreenVolumeSlider(
                    volume: Binding(
                        get: { Double(volumeManager.rawVolume) },
                        set: { newValue in
                            musicManager.setVolume(to: newValue)
                        }
                    ),
                    isLight: false,
                    isCompact: false
                )
                .frame(width: 80, height: 16)
                .background(
                    SliderScrollWheelRepresentable { deltaStep in
                        let step = Float32(deltaStep) * 0.02
                        VolumeManager.shared.adjustRelative(delta: step)
                    }
                )
                .transition(.scale.combined(with: .opacity))
            }
        }
    }
    
    private var repeatIcon: String {
        switch musicManager.repeatMode {
        case .off, .all:
            return "repeat"
        case .one:
            return "repeat.1"
        }
    }
    
    private var isCurrentlyMuted: Bool {
        return volumeManager.isMuted || volumeManager.rawVolume == 0
    }
    
    private var volumeIcon: String {
        if isCurrentlyMuted {
            return "speaker.slash.fill"
        } else if volumeManager.rawVolume < 0.33 {
            return "speaker.wave.1.fill"
        } else if volumeManager.rawVolume < 0.66 {
            return "speaker.wave.2.fill"
        } else {
            return "speaker.wave.3.fill"
        }
    }
    
    private func scrollToActiveLyric(proxy: ScrollViewProxy, forceTop: Bool = false) {
        guard !musicManager.syncedLyrics.isEmpty else { return }
        let elapsed = musicManager.estimatedPlaybackPosition(at: Date())
        let target = forceTop ? 0 : (musicManager.currentLyricIndex(at: elapsed) ?? 0)
        activeLyricIndex = target
        let anchor: UnitPoint = (target == 0 || forceTop) ? .top : .center
        proxy.scrollTo(target, anchor: anchor)
    }
    
    private func scheduleMultiPassScroll(proxy: ScrollViewProxy, forceTop: Bool = false) {
        scrollToActiveLyric(proxy: proxy, forceTop: forceTop)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            scrollToActiveLyric(proxy: proxy, forceTop: forceTop)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            scrollToActiveLyric(proxy: proxy, forceTop: forceTop)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.40) {
            withAnimation(.smooth(duration: 0.3)) {
                scrollToActiveLyric(proxy: proxy, forceTop: forceTop)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
            withAnimation(.smooth(duration: 0.25)) {
                scrollToActiveLyric(proxy: proxy, forceTop: forceTop)
            }
        }
    }
}

// =========================================================================
// MARK: - LockScreenScrubberView (Apple Native Timeline Scrubber)
// =========================================================================

private struct LockScreenScrubberView: View {
    @Binding var sliderValue: Double
    @Binding var dragging: Bool
    @Binding var lastDragged: Date
    let duration: Double
    let color: NSColor
    let estimatedPlaybackTime: Double
    var isCompact: Bool
    var isLight: Bool = false
    var onValueChange: (Double) -> Void
    
    @Default(.sliderColor) private var sliderColorPref
    @Default(.playerColorTinting) private var playerColorTinting
    @State private var isHoveringTrack: Bool = false
    
    private var effectiveElapsed: Double {
        dragging ? sliderValue : estimatedPlaybackTime
    }
    
    private var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(effectiveElapsed / duration, 0.0), 1.0)
    }
    
    private var trackColor: Color {
        if sliderColorPref == .albumArt {
            return isLight
                ? Color(nsColor: color).ensureMaximumBrightness(factor: 0.45)
                : Color(nsColor: color).ensureMinimumBrightness(factor: 0.85)
        } else if sliderColorPref == .accent {
            return .effectiveAccent
        } else {
            return isCompact ? .primary : .white
        }
    }
    
    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                let width = max(1, geo.size.width)
                let height: CGFloat = dragging ? (isCompact ? 7 : 9) : (isHoveringTrack ? (isCompact ? 6 : 8) : (isCompact ? 4 : 5))
                let filledWidth = width * CGFloat(progress)
                
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(isCompact ? Color.secondary.opacity(0.20) : Color.white.opacity(0.22))
                        .frame(height: height)
                    
                    Capsule()
                        .fill(trackColor)
                        .frame(width: max(height, filledWidth), height: height)
                    
                    if dragging || isHoveringTrack {
                        Circle()
                            .fill(isCompact ? Color.primary : Color.white)
                            .frame(width: height + 6, height: height + 6)
                            .offset(x: max(0, min(width - (height + 6), filledWidth - (height + 6) / 2)))
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            if !dragging {
                                withAnimation(.easeInOut(duration: 0.12)) {
                                    dragging = true
                                }
                            }
                            let fraction = min(max(gesture.location.x / width, 0.0), 1.0)
                            let newPos = fraction * duration
                            sliderValue = newPos
                        }
                        .onEnded { gesture in
                            let fraction = min(max(gesture.location.x / width, 0.0), 1.0)
                            let finalPos = fraction * duration
                            sliderValue = finalPos
                            onValueChange(finalPos)
                            dragging = false
                            lastDragged = Date()
                        }
                )
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isHoveringTrack = hovering
                    }
                }
                .animation(.spring(response: 0.28, dampingFraction: 0.75), value: dragging)
                .animation(.easeInOut(duration: 0.15), value: isHoveringTrack)
            }
            .frame(height: isCompact ? 10 : 12)
            
            HStack {
                Text(timeFormatted(seconds: effectiveElapsed))
                    .font(isCompact ? .caption2.monospacedDigit().weight(.medium) : .caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(isCompact ? .secondary : .white.opacity(0.75))
                
                Spacer()
                
                Text("-" + timeFormatted(seconds: max(0, duration - effectiveElapsed)))
                    .font(isCompact ? .caption2.monospacedDigit().weight(.medium) : .caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(isCompact ? .secondary : .white.opacity(0.75))
            }
        }
        .onChange(of: estimatedPlaybackTime) { _, newTime in
            guard !dragging, Date().timeIntervalSince(lastDragged) > 0.4 else { return }
            sliderValue = newTime
        }
    }
    
    private func timeFormatted(seconds: Double) -> String {
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}

// =========================================================================
// MARK: - LockScreenButton (Declarative Native Apple Button)
// =========================================================================

private struct LockScreenButton: View {
    let icon: String
    var iconColor: Color? = nil
    var size: CGFloat = 28
    var isPrimary: Bool = false
    var disabled: Bool = false
    let action: () -> Void
    
    @State private var isHovering: Bool = false
    
    var body: some View {
        let hitSize = isPrimary ? size + 10 : size + 6
        let iconSize = isPrimary ? size * 0.54 : size * 0.50
        
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(
                        isPrimary
                            ? (isHovering ? Color.primary.opacity(0.18) : Color.primary.opacity(0.10))
                            : (isHovering ? Color.primary.opacity(0.10) : Color.clear)
                    )
                    .frame(width: hitSize, height: hitSize)
                
                Image(systemName: icon)
                    .font(.system(size: iconSize, weight: isPrimary ? .bold : .medium))
                    .foregroundStyle(iconColor ?? (isPrimary ? .primary : .secondary))
                    .contentTransition(.symbolEffect)
                    .offset(x: (icon == "play.fill" && isPrimary) ? 1.0 : 0)
            }
            .frame(width: hitSize, height: hitSize)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1.0)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}

// =========================================================================
// MARK: - LockScreenVolumeSlider (Native Volume Pill Slider)
// =========================================================================

private struct LockScreenVolumeSlider: View {
    @Binding var volume: Double
    var isLight: Bool = false
    var isCompact: Bool = true
    @State private var dragging: Bool = false
    @State private var localVolume: Double? = nil
    
    var body: some View {
        GeometryReader { geo in
            let width = max(1, geo.size.width)
            let height = CGFloat(dragging ? 6 : 4)
            let curVal = localVolume ?? volume
            let fillWidth = width * CGFloat(min(max(curVal, 0.0), 1.0))
            
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(isCompact ? Color.secondary.opacity(0.20) : Color.white.opacity(0.22))
                    .frame(height: height)
                
                Capsule()
                    .fill(isCompact ? Color.primary : Color.white)
                    .frame(width: max(height, fillWidth), height: height)
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        dragging = true
                        let fraction = min(max(gesture.location.x / width, 0.0), 1.0)
                        localVolume = fraction
                        volume = fraction
                    }
                    .onEnded { gesture in
                        let fraction = min(max(gesture.location.x / width, 0.0), 1.0)
                        localVolume = nil
                        volume = fraction
                        dragging = false
                    }
            )
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: dragging)
        }
    }
}
