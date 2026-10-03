//
//  LockScreenMediaView.swift
//  NotchPulse
//
//  Created for NotchPulse v2.0 - iPhone-style Lock Screen Media Player
//  Supports Compact Card & Full-Screen Immersive Lyrics Modes
//

import AppKit
import Combine
import Defaults
import SwiftUI

struct LockScreenMediaView: View {
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
    @State private var localVolume: Double? = nil
    @State private var lastVolumeUpdateTime: Date = .distantPast
    
    private let lyricsTimer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ZStack(alignment: .top) {
            if windowController.isWindowVisible {
                switch windowController.displayMode {
                case .standby:
                    StandbyClockView(
                        onToggleMusic: {
                            windowController.switchToMode(.compactMedia)
                        },
                        onClose: {
                            if windowController.isPreviewMode {
                                windowController.togglePreview()
                            }
                        }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    
                case .compactMedia:
                    compactPlayerView
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    
                case .fullScreenLyrics:
                    fullScreenPlayerView
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
        }
        .animation(.spring(response: 0.55, dampingFraction: 0.82, blendDuration: 0), value: windowController.displayMode)
        .onAppear {
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
            guard windowController.isWindowVisible else { return }
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
    private var compactPlayerView: some View {
        let hasLyrics = lockScreenPlayerShowLyrics && (
            !musicManager.syncedLyrics.isEmpty ||
            !musicManager.currentLyrics.isEmpty
        )
        
        return VStack(spacing: 9) {
            // Hàng 1: Album Art + Thông tin bài hát (Marquee) + Sóng nhạc động
            HStack(alignment: .center, spacing: 12) {
                // Album Art (54x54) - Tương tự AlbumArtView trong Notch
                Button {
                    windowController.setFullScreen(true)
                } label: {
                    ZStack(alignment: .bottomTrailing) {
                        Image(nsImage: musicManager.albumArt)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 54, height: 54)
                            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                            .scaleEffect(musicManager.isPlaying ? 1.0 : 0.92)
                            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: musicManager.isPlaying)
                            .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 3)
                            .shadow(color: Color(nsColor: musicManager.avgColor).opacity(0.3), radius: 8, x: 0, y: 4)
                        
                        // Lớp phủ tối khi tạm dừng
                        if !musicManager.isPlaying {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(Color.black.opacity(0.35))
                                .frame(width: 54, height: 54)
                                .allowsHitTesting(false)
                        }
                        
                        // Icon app phát nhạc (Apple Music, Spotify, ...)
                        if !musicManager.usingAppIconForArtwork {
                            AppIcon(for: musicManager.bundleIdentifier ?? "com.apple.Music")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 16, height: 16)
                                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                                .offset(x: 3, y: 3)
                                .shadow(radius: 3)
                        }
                    }
                }
                .buttonStyle(.plain)
                .help("Click to expand to full-screen lyrics")
                
                // Tên bài hát & Ca sĩ hỗ trợ MarqueeText tự cuộn khi chữ dài
                VStack(alignment: .leading, spacing: 2) {
                    MarqueeText(
                        $musicManager.songTitle,
                        font: .system(size: 15, weight: .bold, design: .rounded),
                        nsFont: .headline,
                        textColor: .white,
                        frameWidth: 268
                    )
                    
                    MarqueeText(
                        $musicManager.artistName,
                        font: .system(size: 13, weight: .medium, design: .rounded),
                        nsFont: .subheadline,
                        textColor: playerColorTinting
                            ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.75)
                            : .white.opacity(0.68),
                        frameWidth: 268
                    )
                }
                
                Spacer(minLength: 4)
                
                // Cột sóng nhạc sống động góc phải
                soundWaveform
            }
            
            // Hàng 2: Câu hát thời gian thực (nếu bật tuỳ chọn Lời bài hát)
            if hasLyrics {
                TimelineView(.animation(minimumInterval: 0.25)) { timeline in
                    let effectiveElapsed: Double = compactDragging
                        ? compactSliderValue
                        : musicManager.estimatedPlaybackPosition(at: timeline.date)
                    let activeIndex = musicManager.currentLyricIndex(at: effectiveElapsed)
                    let line: String = {
                        if musicManager.isFetchingLyrics { return "Loading lyrics…" }
                        if !musicManager.syncedLyrics.isEmpty {
                            return musicManager.lyricLine(at: effectiveElapsed)
                        }
                        let trimmed = musicManager.currentLyrics.trimmingCharacters(in: .whitespacesAndNewlines)
                        return trimmed.isEmpty ? "♪  ♫  ♪" : trimmed.replacingOccurrences(of: "\n", with: " ")
                    }()
                    let cleanText = MusicManager.stripLRCTimestamps(from: line)
                    let displayText = cleanText.isEmpty ? "♪  ♫  ♪" : cleanText
                    let isPersian = displayText.unicodeScalars.contains { scalar in
                        let v = scalar.value
                        return v >= 0x0600 && v <= 0x06FF
                    }
                    
                    Button {
                        windowController.setFullScreen(true)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "quote.bubble.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.85))
                            
                            Text(displayText)
                                .id(activeIndex != nil ? "compact-lyric-\(activeIndex!)" : "compact-lyric-\(displayText)")
                                .font(isPersian ? .custom("Vazirmatn-Regular", size: 12) : .system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(
                                    musicManager.isFetchingLyrics
                                        ? Color.white.opacity(0.6)
                                        : (activeIndex != nil ? Color.white.opacity(0.95) : Color.white.opacity(0.65))
                                )
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
            
            // Hàng 3: Thanh tiến trình chuẩn tương tác & tua nhạc (Scrubber)
            TimelineView(.animation(minimumInterval: musicManager.playbackRate > 0 ? 0.1 : 0.5)) { timeline in
                let currentEstimated = musicManager.estimatedPlaybackPosition(at: timeline.date)
                
                LockScreenScrubberView(
                    sliderValue: $compactSliderValue,
                    dragging: $compactDragging,
                    lastDragged: $compactLastDragged,
                    duration: max(1.0, musicManager.songDuration),
                    color: musicManager.avgColor,
                    estimatedPlaybackTime: currentEstimated,
                    isCompact: true,
                    onValueChange: { newValue in
                        musicManager.seek(to: newValue)
                    }
                )
            }
            
            // Hàng 4: Cụm phím điều khiển đồng bộ theo cài đặt Notch & Nút Lời bài hát & Nút StandBy Clock
            HStack(spacing: 0) {
                if Defaults[.enableLockScreenStandBy] {
                    Button {
                        windowController.switchToMode(.standby)
                    } label: {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(Color.white.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .help("Switch to StandBy Clock")
                }
                
                Spacer()
                
                // Các nút điều khiển theo cấu hình slots đã cài đặt
                let slots = activeSlots
                HStack(spacing: slots.count > 3 ? 18 : 28) {
                    ForEach(Array(slots.enumerated()), id: \.offset) { _, slot in
                        compactSlotButton(for: slot)
                    }
                }
                
                Spacer()
                
                // Nút Lời bài hát góc phải
                Button {
                    windowController.switchToMode(.fullScreenLyrics)
                } label: {
                    Image(systemName: "quote.bubble.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(hasLyrics ? Color.white.opacity(0.95) : Color.white.opacity(0.4))
                }
                .buttonStyle(.plain)
                .help("Click to expand to full-screen lyrics")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
        .frame(width: 420, height: hasLyrics ? 218 : 185)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(white: 0.12).opacity(0.94))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Color.black.opacity(0.4), radius: 14, x: 0, y: 7)
    }
    
    // =========================================================================
    // MARK: - 2. Full-Screen Immersive Player View (Ảnh bìa to + Lời bài hát)
    // =========================================================================
    private var fullScreenPlayerView: some View {
        ZStack {
            // Nền Ambient phát sáng màu của bài hát phủ toàn màn hình
            ambientDynamicBackground
            
            // Nút đóng góc trên bên phải
            VStack {
                HStack {
                    Spacer()
                    Button {
                        windowController.setFullScreen(false)
                    } label: {
                        Image(systemName: "chevron.down.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.white.opacity(0.85), .white.opacity(0.2))
                            .symbolRenderingMode(.palette)
                            .shadow(radius: 6)
                    }
                    .buttonStyle(.plain)
                    .help("Collapse to compact player (Esc)")
                    .padding(.trailing, 28)
                    .padding(.top, 28)
                }
                Spacer()
            }
            .zIndex(10)
            
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
    
    // Nền Ambient nhẹ nhàng tối ưu GPU phủ toàn màn hình
    private var ambientDynamicBackground: some View {
        ZStack {
            Color(white: 0.08)
            RadialGradient(
                colors: [
                    Color(nsColor: musicManager.avgColor).opacity(0.4),
                    Color.clear
                ],
                center: .topLeading,
                startRadius: 80,
                endRadius: 750
            )
        }
    }
    
    // Cột trái Full Screen: Ảnh bài hát to + Thông tin + Điều khiển
    private func fullScreenLeftColumn(albumSize: CGFloat) -> some View {
        VStack(spacing: albumSize * 0.07) {
            // Ảnh bìa bài hát to nổi bật (bấm vào để thu nhỏ về compact)
            Button {
                windowController.switchToMode(.compactMedia)
            } label: {
                ZStack(alignment: .bottomTrailing) {
                    Image(nsImage: musicManager.albumArt)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: albumSize, height: albumSize)
                        .clipShape(RoundedRectangle(cornerRadius: albumSize * 0.08, style: .continuous))
                        .scaleEffect(musicManager.isPlaying ? 1.0 : 0.94)
                        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: musicManager.isPlaying)
                        .shadow(color: Color(nsColor: musicManager.avgColor).opacity(0.55), radius: albumSize * 0.1, x: 0, y: albumSize * 0.05)
                        .shadow(color: .black.opacity(0.6), radius: albumSize * 0.06, x: 0, y: albumSize * 0.02)
                    
                    if !musicManager.isPlaying {
                        RoundedRectangle(cornerRadius: albumSize * 0.08, style: .continuous)
                            .fill(Color.black.opacity(0.35))
                            .frame(width: albumSize, height: albumSize)
                            .allowsHitTesting(false)
                    }
                    
                    if !musicManager.usingAppIconForArtwork {
                        AppIcon(for: musicManager.bundleIdentifier ?? "com.apple.Music")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: albumSize * 0.11, height: albumSize * 0.11)
                            .clipShape(RoundedRectangle(cornerRadius: albumSize * 0.025, style: .continuous))
                            .offset(x: albumSize * 0.02, y: albumSize * 0.02)
                            .shadow(radius: 6)
                    }
                }
            }
            .buttonStyle(.plain)
            .help("Click artwork to collapse")
            
            // Thông tin bài hát
            VStack(spacing: albumSize * 0.02) {
                Text(musicManager.songTitle)
                    .font(.system(size: max(albumSize * 0.075, 20), weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                
                Text(musicManager.artistName)
                    .font(.system(size: max(albumSize * 0.055, 15), weight: .medium, design: .rounded))
                    .foregroundStyle(Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.8))
                    .lineLimit(1)
                
                if !musicManager.album.isEmpty {
                    Text(musicManager.album)
                        .font(.system(size: max(albumSize * 0.04, 12), weight: .regular))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
            }
            
            // Thanh tiến trình lớn tương tác
            TimelineView(.animation(minimumInterval: musicManager.playbackRate > 0 ? 0.1 : 0.5)) { timeline in
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
            }
            
            // Thanh âm lượng dạng slider khi ở chế độ Full Screen
            HStack(spacing: 12) {
                Image(systemName: "speaker.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
                
                LockScreenVolumeSlider(
                    volume: Binding(
                        get: { Double(volumeManager.rawVolume) },
                        set: { newValue in
                            musicManager.setVolume(to: newValue)
                        }
                    )
                )
                .frame(height: 6)
                
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .frame(width: albumSize * 0.95)
            .padding(.top, 4)
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
                                        .shadow(color: isCurrent ? Color(nsColor: musicManager.avgColor).opacity(0.9) : .clear, radius: 12)
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
                iconColor: musicManager.isShuffled ? Color.green : .white.opacity(0.6),
                size: 28,
                action: { musicManager.toggleShuffle() }
            )
        case .previous:
            LockScreenButton(
                icon: "backward.fill",
                iconColor: .white.opacity(0.9),
                size: 30,
                action: { musicManager.previousTrack() }
            )
        case .playPause:
            LockScreenButton(
                icon: musicManager.isPlaying ? "pause.fill" : "play.fill",
                iconColor: .white,
                size: 38,
                isPrimary: true,
                action: { musicManager.togglePlay() }
            )
        case .next:
            LockScreenButton(
                icon: "forward.fill",
                iconColor: .white.opacity(0.9),
                size: 30,
                action: { musicManager.nextTrack() }
            )
        case .repeatMode:
            LockScreenButton(
                icon: repeatIcon,
                iconColor: repeatIconColor,
                size: 28,
                action: { musicManager.toggleRepeat() }
            )
        case .volume:
            compactVolumeButton
        case .favorite:
            LockScreenButton(
                icon: musicManager.isFavoriteTrack ? "heart.fill" : "heart",
                iconColor: musicManager.isFavoriteTrack ? Color.red : .white.opacity(0.7),
                size: 28,
                disabled: !musicManager.canFavoriteTrack,
                action: { musicManager.toggleFavoriteTrack() }
            )
        case .goBackward:
            LockScreenButton(
                icon: "gobackward.15",
                iconColor: .white.opacity(0.85),
                size: 28,
                action: { musicManager.skip(seconds: -15) }
            )
        case .goForward:
            LockScreenButton(
                icon: "goforward.15",
                iconColor: .white.opacity(0.85),
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
                iconColor: musicManager.isShuffled ? Color.green : .white.opacity(0.65),
                size: 32,
                action: { musicManager.toggleShuffle() }
            )
        case .previous:
            LockScreenButton(
                icon: "backward.fill",
                iconColor: .white.opacity(0.92),
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
            }
            .buttonStyle(.plain)
        case .next:
            LockScreenButton(
                icon: "forward.fill",
                iconColor: .white.opacity(0.92),
                size: 36,
                action: { musicManager.nextTrack() }
            )
        case .repeatMode:
            LockScreenButton(
                icon: repeatIcon,
                iconColor: repeatIconColor,
                size: 32,
                action: { musicManager.toggleRepeat() }
            )
        case .favorite:
            LockScreenButton(
                icon: musicManager.isFavoriteTrack ? "heart.fill" : "heart",
                iconColor: musicManager.isFavoriteTrack ? Color.red : .white.opacity(0.75),
                size: 32,
                disabled: !musicManager.canFavoriteTrack,
                action: { musicManager.toggleFavoriteTrack() }
            )
        case .goBackward:
            LockScreenButton(
                icon: "gobackward.15",
                iconColor: .white.opacity(0.9),
                size: 32,
                action: { musicManager.skip(seconds: -15) }
            )
        case .goForward:
            LockScreenButton(
                icon: "goforward.15",
                iconColor: .white.opacity(0.9),
                size: 32,
                action: { musicManager.skip(seconds: 15) }
            )
        case .volume, .none:
            EmptyView()
        }
    }
    
    // Nút Volume tương tác trong Compact Card
    private var compactVolumeButton: some View {
        HStack(spacing: 4) {
            LockScreenButton(
                icon: volumeIcon,
                iconColor: isCurrentlyMuted ? .gray : .white.opacity(0.85),
                size: 28,
                action: {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        showCompactVolumeSlider.toggle()
                    }
                }
            )
            
            if showCompactVolumeSlider {
                LockScreenVolumeSlider(
                    volume: Binding(
                        get: { Double(volumeManager.rawVolume) },
                        set: { newValue in
                            musicManager.setVolume(to: newValue)
                        }
                    )
                )
                .frame(width: 52, height: 5)
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
            return .white.opacity(0.55)
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
    
    // MARK: - Animated Waveform Helper
    private var soundWaveform: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<5) { i in
                WaveBar(isPlaying: musicManager.isPlaying, index: i, tintColor: Color(nsColor: musicManager.avgColor))
            }
        }
        .frame(height: 14)
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
            return Color(nsColor: color).ensureMinimumBrightness(factor: 0.85)
        } else if sliderColorPref == .accent {
            return .effectiveAccent
        } else {
            return .white
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
                        .fill(Color.white.opacity(0.18))
                        .frame(height: height)
                    
                    // Thanh tiến trình đã phát
                    Capsule()
                        .fill(trackColor)
                        .frame(width: max(height, filledWidth), height: height)
                    
                    // Nút đầu ngón tay / chấm tròn chỉ báo khi di chuột hoặc kéo
                    if dragging || isHoveringTrack {
                        Circle()
                            .fill(Color.white)
                            .frame(width: height + 6, height: height + 6)
                            .shadow(color: Color.black.opacity(0.4), radius: 3, x: 0, y: 1)
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
                            ? Color(nsColor: color).ensureMinimumBrightness(factor: 0.75)
                            : .white.opacity(0.65)
                    )
                
                Spacer()
                
                Text("-" + timeFormatted(seconds: max(0, duration - effectiveElapsed)))
                    .font(.system(size: isCompact ? 11 : 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.65))
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
    let action: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            ZStack {
                Capsule()
                    .fill(isHovering && !disabled ? Color.white.opacity(0.18) : Color.clear)
                    .frame(width: size + 8, height: size + 8)
                
                Image(systemName: icon)
                    .font(.system(size: isPrimary ? size * 0.62 : size * 0.52, weight: isPrimary ? .bold : .medium))
                    .foregroundStyle(iconColor)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1.0)
        .scaleEffect(isHovering && !disabled ? 1.06 : 1.0)
        .onHover { hovering in
            withAnimation(.smooth(duration: 0.2)) {
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
                    .fill(Color.white.opacity(0.2))
                    .frame(height: height)
                
                Capsule()
                    .fill(Color.white.opacity(0.92))
                    .frame(width: fillWidth, height: height)
            }
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

// =========================================================================
// MARK: - WaveBar Component (Cột sóng nhạc nhảy theo nhạc)
// =========================================================================

private struct WaveBar: View {
    let isPlaying: Bool
    let index: Int
    let tintColor: Color
    
    @State private var animatingHeight: CGFloat = 3
    
    var body: some View {
        Capsule()
            .fill(isPlaying ? tintColor.ensureMinimumBrightness(factor: 0.85) : Color.white.opacity(0.35))
            .frame(width: 3, height: isPlaying ? animatingHeight : 3)
            .onAppear {
                if isPlaying {
                    startAnimation()
                }
            }
            .onChange(of: isPlaying) { _, playing in
                if playing {
                    startAnimation()
                } else {
                    withAnimation(.easeOut(duration: 0.2)) {
                        animatingHeight = 3
                    }
                }
            }
    }
    
    private func startAnimation() {
        let randomDuration = Double.random(in: 0.35...0.65)
        let targetHeights: [CGFloat] = [7, 14, 11, 15, 9]
        let h = targetHeights[index % targetHeights.count]
        
        withAnimation(.easeInOut(duration: randomDuration).repeatForever(autoreverses: true)) {
            animatingHeight = h
        }
    }
}
