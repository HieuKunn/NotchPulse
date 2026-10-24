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
    @State private var localVolume: Double? = nil
    @State private var lastVolumeUpdateTime: Date = .distantPast
    
    private let lyricsTimer = Timer.publish(every: 0.4, tolerance: 0.1, on: .main, in: .common).autoconnect()
    
    private var isLightMode: Bool {
        windowController.isLightMode
    }
    
    private var compactCardBg: Color {
        isLightMode ? Color.white : Color(white: 0.10)
    }
    
    private var compactCardBorder: Color {
        isLightMode ? Color.black.opacity(0.12) : Color.white.opacity(0.15)
    }
    
    private var compactPrimaryText: Color {
        isLightMode ? Color.black : Color.white
    }
    
    private var compactSecondaryText: Color {
        isLightMode ? Color.black.opacity(0.65) : Color.white.opacity(0.70)
    }
    
    private var compactIconColor: Color {
        isLightMode ? Color.black : Color.white
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
    // MARK: - 1. Compact Player View (iPhone-style Lock Screen Card)
    // =========================================================================
    private var compactArtistColor: Color {
        if playerColorTinting {
            return isLightMode
                ? Color(nsColor: musicManager.avgColor).ensureMaximumBrightness(factor: 0.35)
                : Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.75)
        }
        return compactSecondaryText
    }

    private var compactAlbumArtView: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(nsImage: musicManager.albumArt)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 54, height: 54)
                .overlay {
                    if !musicManager.isPlaying {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.black.opacity(0.35))
                            .allowsHitTesting(false)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            
            // Icon app phát nhạc (Apple Music, Spotify, ...)
            if !musicManager.usingAppIconForArtwork && !musicManager.songTitle.isEmpty {
                AppIcon(for: musicManager.bundleIdentifier ?? "com.apple.Music")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .offset(x: 3, y: 3)
            }
        }
        .scaleEffect(musicManager.isPlaying ? 1.0 : 0.92)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: musicManager.isPlaying)
    }

    private var compactHeaderRow: some View {
        HStack(alignment: .center, spacing: 12) {
            // Album Art (54x54) - Tương tự AlbumArtView trong Notch
            Button {
                windowController.setFullScreen(true)
            } label: {
                compactAlbumArtView
            }
            .buttonStyle(.plain)
            .help("Click to expand to full-screen lyrics")
            
            // Tên bài hát & Ca sĩ hiển thị cố định, dài quá thì "..."
            VStack(alignment: .leading, spacing: 2) {
                Text(musicManager.songTitle.isEmpty ? (musicManager.isPlayerIdle ? loc("Not Playing") : "") : musicManager.songTitle)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(compactPrimaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 268, alignment: .leading)
                
                Text(musicManager.artistName)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(compactArtistColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 290, alignment: .leading)
            }
            
            Spacer(minLength: 4)
        }
    }

    private var compactQuoteBubbleColor: Color {
        if isLightMode {
            return Color(nsColor: musicManager.avgColor).ensureMaximumBrightness(factor: 0.45)
        } else {
            return Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.85)
        }
    }

    private func compactLyricColor(isActive: Bool) -> Color {
        if isLightMode {
            if musicManager.isFetchingLyrics { return Color.black.opacity(0.50) }
            return isActive ? Color.black.opacity(0.92) : Color.black.opacity(0.58)
        } else {
            if musicManager.isFetchingLyrics { return Color.white.opacity(0.60) }
            return isActive ? Color.white.opacity(0.95) : Color.white.opacity(0.65)
        }
    }

    private func resolveCompactLyricText(elapsed: Double) -> (text: String, isPersian: Bool) {
        let line: String
        if musicManager.isFetchingLyrics {
            line = "Loading lyrics…"
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
            
            Button {
                windowController.setFullScreen(true)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "quote.bubble.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(compactQuoteBubbleColor)
                    
                    Text(lyric.text)
                        .id(activeIndex != nil ? "compact-lyric-\(activeIndex!)" : "compact-lyric-\(lyric.text)")
                        .font(lyric.isPersian ? .custom("Vazirmatn-Regular", size: 12) : .system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(compactLyricColor(isActive: activeIndex != nil))
                        .lineLimit(1)
                        .transition(.opacity.combined(with: .offset(y: 2)))
                        .animation(.easeInOut(duration: 0.25), value: activeIndex)
                    
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .help("Click to expand to full-screen lyrics")
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
            
            // Các nút điều khiển theo cấu hình slots đã cài đặt
            let slots = activeSlots
            HStack(spacing: slots.count > 3 ? 18 : 28) {
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

    // =========================================================================
    // MARK: - 1. Compact Player View (iPhone-style Lock Screen Card)
    // =========================================================================
    private var compactPlayerView: some View {
        let hasLyrics = lockScreenPlayerShowLyrics && (
            !musicManager.syncedLyrics.isEmpty ||
            !musicManager.currentLyrics.isEmpty
        )
        
        return VStack(spacing: 9) {
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
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(compactCardBg)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(compactCardBorder, lineWidth: 1.2)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
    
    // =========================================================================
    // MARK: - 2. Full-Screen Immersive Player View (Ảnh bìa to + Lời bài hát)
    // =========================================================================
    private var fullScreenPlayerView: some View {
        ZStack {
            // Nền Ambient lấy trực tiếp ảnh bìa bài hát phóng to và làm mờ tràn viền toàn màn hình
            ambientDynamicBackground
            
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let albumSize = min(max(h * 0.44, 280), 550)
                let contentWidth = w * 0.85
                let hasLyrics = !musicManager.syncedLyrics.isEmpty || !musicManager.currentLyrics.isEmpty
                
                VStack(spacing: 0) {
                    Spacer()
                    
                    HStack(alignment: .center, spacing: w * 0.05) {
                        if hasLyrics {
                            fullScreenLeftColumn(albumSize: albumSize)
                                .frame(width: contentWidth * 0.45)
                            
                            fullScreenLyricsColumn(columnWidth: contentWidth * 0.50, viewHeight: h * 0.7)
                                .frame(width: contentWidth * 0.50)
                        } else {
                            fullScreenLeftColumn(albumSize: albumSize)
                                .frame(width: albumSize * 1.3)
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
    
    // Nền Ambient lấy trực tiếp ảnh bìa bài hát phóng to và làm mờ tràn toàn màn hình
    private var ambientDynamicBackground: some View {
        GeometryReader { geo in
            ZStack {
                // Lớp nền đen sâu đề phòng khi ảnh đang load hoặc trong suốt
                Color.black
                
                // Lấy thẳng ảnh bài hát, phóng to vừa full màn hình và làm mờ
                Image(nsImage: musicManager.albumArt)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .scaleEffect(1.25) // Tránh viền hở khi blur ở 4 cạnh màn hình
                    .blur(radius: 65, opaque: true)
                    .overlay(
                        // Lớp phủ đen trong suốt nhẹ để chữ và điều khiển luôn tương phản rõ nét
                        Color.black.opacity(0.35)
                    )
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .animation(.easeInOut(duration: 0.5), value: musicManager.albumArt)
        }
        .ignoresSafeArea()
    }
    
    // Cột trái Full Screen: Ảnh bài hát to + Thông tin + Điều khiển
    private func fullScreenLeftColumn(albumSize: CGFloat) -> some View {
        VStack(spacing: albumSize * 0.07) {
            // Ảnh bìa bài hát to nổi bật (bấm vào để thu nhỏ về compact)
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
                                    .fill(Color.black.opacity(0.35))
                                    .allowsHitTesting(false)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: albumSize * 0.08, style: .continuous))
                    
                    if !musicManager.usingAppIconForArtwork && !musicManager.songTitle.isEmpty {
                        AppIcon(for: musicManager.bundleIdentifier ?? "com.apple.Music")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: albumSize * 0.11, height: albumSize * 0.11)
                            .clipShape(RoundedRectangle(cornerRadius: albumSize * 0.025, style: .continuous))
                            .offset(x: albumSize * 0.02, y: albumSize * 0.02)
                    }
                }
                .scaleEffect(musicManager.isPlaying ? 1.0 : 0.94)
                .animation(.spring(response: 0.35, dampingFraction: 0.75), value: musicManager.isPlaying)
            }
            .buttonStyle(.plain)
            .help("Click artwork to collapse")
            
            // Thông tin bài hát
            VStack(spacing: albumSize * 0.02) {
                Text(musicManager.songTitle.isEmpty ? (musicManager.isPlayerIdle ? loc("Not Playing") : "") : musicManager.songTitle)
                    .font(.system(size: max(albumSize * 0.075, 20), weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.center)
                
                Text(musicManager.artistName)
                    .font(.system(size: max(albumSize * 0.055, 15), weight: .medium, design: .rounded))
                    .foregroundStyle(Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.8))
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                if !musicManager.album.isEmpty {
                    Text(musicManager.album)
                        .font(.system(size: max(albumSize * 0.04, 12), weight: .regular))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            
            // Thanh tiến trình lớn tương tác
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
            
            // Bộ phím điều khiển đồng bộ
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
    
    // Cột phải Full Screen: Lời bài hát đồng bộ toàn màn hình
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
                                            ? Color.white.opacity(0.32)
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
                    Text(musicManager.isPlaying ? "Playing Music" : "Paused")
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
                iconColor: musicManager.isShuffled ? Color.green : compactIconColor,
                size: 28,
                isLight: isLightMode,
                action: { musicManager.toggleShuffle() }
            )
        case .previous:
            LockScreenButton(
                icon: "backward.fill",
                iconColor: compactIconColor,
                size: 30,
                isLight: isLightMode,
                action: { musicManager.previousTrack() }
            )
        case .playPause:
            LockScreenButton(
                icon: musicManager.isPlaying ? "pause.fill" : "play.fill",
                iconColor: compactIconColor,
                size: 38,
                isPrimary: true,
                isLight: isLightMode,
                action: {
                    musicManager.togglePlay()
                }
            )
        case .next:
            LockScreenButton(
                icon: "forward.fill",
                iconColor: compactIconColor,
                size: 30,
                isLight: isLightMode,
                action: { musicManager.nextTrack() }
            )
        case .repeatMode:
            LockScreenButton(
                icon: repeatIcon,
                iconColor: repeatIconColor,
                size: 28,
                isLight: isLightMode,
                action: { musicManager.toggleRepeat() }
            )
        case .volume:
            compactVolumeButton
        case .favorite:
            LockScreenButton(
                icon: musicManager.isFavoriteTrack ? "heart.fill" : "heart",
                iconColor: musicManager.isFavoriteTrack ? Color.red : compactIconColor,
                size: 28,
                disabled: !musicManager.canFavoriteTrack,
                isLight: isLightMode,
                action: { musicManager.toggleFavoriteTrack() }
            )
        case .goBackward:
            LockScreenButton(
                icon: "gobackward.15",
                iconColor: compactIconColor,
                size: 28,
                isLight: isLightMode,
                action: { musicManager.skip(seconds: -15) }
            )
        case .goForward:
            LockScreenButton(
                icon: "goforward.15",
                iconColor: compactIconColor,
                size: 28,
                isLight: isLightMode,
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
                iconColor: musicManager.isShuffled ? Color.green : .white,
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
                iconColor: musicManager.repeatMode == .off ? .white : .red,
                size: 32,
                action: { musicManager.toggleRepeat() }
            )
        case .favorite:
            LockScreenButton(
                icon: musicManager.isFavoriteTrack ? "heart.fill" : "heart",
                iconColor: musicManager.isFavoriteTrack ? Color.red : .white,
                size: 32,
                disabled: !musicManager.canFavoriteTrack,
                action: { musicManager.toggleFavoriteTrack() }
            )
        case .goBackward:
            LockScreenButton(
                icon: "gobackward.15",
                iconColor: .white,
                size: 32,
                action: { musicManager.skip(seconds: -15) }
            )
        case .goForward:
            LockScreenButton(
                icon: "goforward.15",
                iconColor: .white,
                size: 32,
                action: { musicManager.skip(seconds: 15) }
            )
        case .volume:
            fullScreenVolumeButton
        case .none:
            EmptyView()
        }
    }
    
    // Nút Volume tương tác trong Compact Card
    private var compactVolumeButton: some View {
        HStack(spacing: 4) {
            LockScreenButton(
                icon: volumeIcon,
                iconColor: isCurrentlyMuted ? (isLightMode ? Color.black.opacity(0.35) : Color.white.opacity(0.35)) : compactIconColor,
                size: 28,
                isLight: isLightMode,
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
                    isLight: isLightMode
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
    
    // Nút Volume tương tác trong Full Screen
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
                    )
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
        case .off:
            return "repeat"
        case .all:
            return "repeat"
        case .one:
            return "repeat.1"
        }
    }

    private var repeatIconColor: Color {
        switch musicManager.repeatMode {
        case .off:
            return compactIconColor
        case .all, .one:
            return .red
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
// MARK: - LockScreenScrubberView (Thanh trượt tua nhạc tương tác cao cấp)
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
            return (isCompact && isLight) ? Color.black.opacity(0.85) : .white
        }
    }
    
    var body: some View {
        VStack(spacing: 4) {
            // Thanh tiến trình với thanh trượt kéo thả
            GeometryReader { geo in
                let width = max(1, geo.size.width)
                let height: CGFloat = dragging ? (isCompact ? 8 : 10) : (isHoveringTrack ? (isCompact ? 7 : 8) : (isCompact ? 5 : 6))
                let filledWidth = width * CGFloat(progress)
                
                ZStack(alignment: .leading) {
                    // Thanh rãnh nền
                    Capsule()
                        .fill((isCompact && isLight) ? Color.black.opacity(0.12) : Color.white.opacity(0.18))
                        .frame(height: height)
                    
                    // Thanh tiến trình đã phát
                    Capsule()
                        .fill(trackColor)
                        .frame(width: max(height, filledWidth), height: height)
                    
                    // Nút đầu ngón tay / chấm tròn chỉ báo khi di chuột hoặc kéo
                    if dragging || isHoveringTrack {
                        Circle()
                            .fill((isCompact && isLight) ? Color.black : Color.white)
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
            
            // Nhãn thời gian: Đã phát (bên trái) và Còn lại (bên phải)
            HStack {
                Text(timeFormatted(seconds: effectiveElapsed))
                    .font(.system(size: isCompact ? 11 : 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(
                        playerColorTinting
                            ? (isLight
                                ? Color(nsColor: color).ensureMaximumBrightness(factor: 0.40)
                                : Color(nsColor: color).ensureMinimumBrightness(factor: 0.75))
                            : ((isCompact && isLight) ? Color.black.opacity(0.60) : .white.opacity(0.65))
                    )
                
                Spacer()
                
                Text("-" + timeFormatted(seconds: max(0, duration - effectiveElapsed)))
                    .font(.system(size: isCompact ? 11 : 12, weight: .semibold, design: .rounded))
                    .foregroundStyle((isCompact && isLight) ? Color.black.opacity(0.60) : .white.opacity(0.65))
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
// MARK: - LockScreenButton (Nút điều khiển với hiệu ứng Hover & Nhấn mượt mà)
// =========================================================================

private struct LockScreenButton: View {
    let icon: String
    var iconColor: Color = .white
    var size: CGFloat = 30
    var isPrimary: Bool = false
    var disabled: Bool = false
    var isLight: Bool = false
    let action: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        let hitSize: CGFloat = isPrimary ? (size + 14) : (size + 8)
        let iconSize: CGFloat = isPrimary ? (size * 0.62) : (size * 0.52)
        
        Button(action: action) {
            ZStack {
                Color.black.opacity(0.001)
                Circle()
                    .fill(
                        isHovering && !disabled
                            ? (isLight ? Color.black.opacity(0.08) : Color.white.opacity(0.18))
                            : Color.clear
                    )
                    .frame(width: hitSize, height: hitSize)
                Image(systemName: icon)
                    .font(.system(size: iconSize, weight: isPrimary ? .bold : .medium))
                    .foregroundStyle(iconColor)
                    .contentTransition(.symbolEffect)
                    .offset(x: (icon == "play.fill" && isPrimary) ? 1.5 : 0)
            }
            .frame(width: hitSize, height: hitSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1.0)
        .onHover { hovering in
            withAnimation(.smooth(duration: 0.18)) {
                isHovering = hovering
            }
        }
    }
}

// =========================================================================
// MARK: - LockScreenVolumeSlider (Thanh trượt âm lượng trực quan)
// =========================================================================

private struct LockScreenVolumeSlider: View {
    @Binding var volume: Double
    var isLight: Bool = false
    @State private var dragging: Bool = false
    @State private var localVolume: Double? = nil
    
    var body: some View {
        GeometryReader { geo in
            let width = max(1, geo.size.width)
            let height = CGFloat(dragging ? 7 : 4.5)
            let curVal = localVolume ?? volume
            let fillWidth = width * CGFloat(min(max(curVal, 0.0), 1.0))
            
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(isLight ? Color.black.opacity(0.12) : Color.white.opacity(0.2))
                    .frame(height: height)
                
                Capsule()
                    .fill(isLight ? Color.black.opacity(0.85) : Color.white.opacity(0.92))
                    .frame(width: fillWidth, height: height)
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


