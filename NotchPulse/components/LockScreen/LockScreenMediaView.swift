//
//  LockScreenMediaView.swift
//  NotchPulse
//
//  Created for NotchPulse v2.0 - iPhone-style Lock Screen Media Player
//  Supports Compact Card & Full-Screen Immersive Lyrics Modes
//

import Combine
import Defaults
import SwiftUI

struct LockScreenMediaView: View {
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject var windowController: LockScreenMediaWindow
    @Default(.musicControlSlots) private var musicControlSlots
    @State private var activeLyricIndex: Int = 0
    
    var body: some View {
        ZStack {
            if windowController.isWindowVisible {
                if windowController.isFullScreen {
                    fullScreenPlayerView
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                } else {
                    compactPlayerView
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
        }
        .animation(.spring(response: 0.65, dampingFraction: 0.82, blendDuration: 0), value: windowController.isFullScreen)
        .onAppear {
            musicManager.ensureLyricsLoaded()
        }
        .onChange(of: musicManager.songTitle) { _, _ in
            musicManager.ensureLyricsLoaded()
            let elapsed = musicManager.estimatedPlaybackPosition(at: Date())
            activeLyricIndex = currentLyricIndex(at: max(0, elapsed - 0.7))
        }
        .onChange(of: windowController.isFullScreen) { _, isFull in
            if isFull {
                let elapsed = musicManager.estimatedPlaybackPosition(at: Date())
                activeLyricIndex = currentLyricIndex(at: max(0, elapsed - 0.7))
            }
        }
    }
    
    // =========================================================================
    // MARK: - 1. Compact Player View (Y hệt ảnh Lock Screen iPhone người dùng gửi)
    // =========================================================================
    private var compactPlayerView: some View {
        let hasLyrics = !musicManager.syncedLyrics.isEmpty || !musicManager.currentLyrics.isEmpty
        
        return VStack(spacing: 10) {
            // Hàng 1: Ảnh bìa nhỏ + Tên bài hát/ca sĩ + Sóng nhạc góc phải
            HStack(alignment: .center, spacing: 12) {
                // Album Art nhỏ (52x52) - Nhấp vào đây để phóng to Full Screen
                Button {
                    windowController.setFullScreen(true)
                } label: {
                    ZStack(alignment: .bottomTrailing) {
                        Image(nsImage: musicManager.albumArt)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 52, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 3)
                        
                        // Icon app nguồn nhỏ ở góc
                        AppIcon(for: musicManager.bundleIdentifier ?? "com.apple.Music")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 14, height: 14)
                            .offset(x: 3, y: 3)
                    }
                }
                .buttonStyle(.plain)
                .help("Nhấp để phóng to toàn màn hình hiển thị lời bài hát")
                
                // Tên bài hát & Tên ca sĩ
                VStack(alignment: .leading, spacing: 2) {
                    Text(musicManager.songTitle)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    
                    Text(musicManager.artistName)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.75))
                        .lineLimit(1)
                }
                
                Spacer(minLength: 4)
                
                // Cột sóng nhạc sống động góc phải
                soundWaveform
            }
            
            // Hàng 1.5: Câu hát Karaoke thời gian thực (nếu bài có lời)
            if !musicManager.syncedLyrics.isEmpty {
                TimelineView(.animation(minimumInterval: 0.25)) { timeline in
                    let elapsed = musicManager.estimatedPlaybackPosition(at: timeline.date)
                    let activeIndex = currentLyricIndex(at: max(0, elapsed - 0.7))
                    if activeIndex >= 0 && activeIndex < musicManager.syncedLyrics.count {
                        let text = musicManager.syncedLyrics[activeIndex].text
                        if !text.isEmpty {
                            Button {
                                windowController.setFullScreen(true)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "quote.bubble.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.85))
                                    Text(text)
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.white.opacity(0.92))
                                        .lineLimit(1)
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                            .help("Nhấp để phóng to toàn màn hình hiển thị lời bài hát (Karaoke)")
                        }
                    }
                }
            } else if !musicManager.currentLyrics.isEmpty {
                Button {
                    windowController.setFullScreen(true)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "quote.bubble.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.85))
                        Text("Xem lời bài hát (Lyrics)")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.75))
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
            
            // Hàng 2: Thanh tiến trình (Scrubber) + Thời gian 2 bên
            TimelineView(.animation(minimumInterval: 0.25)) { timeline in
                let elapsed = musicManager.estimatedPlaybackPosition(at: timeline.date)
                let duration = max(1.0, musicManager.songDuration)
                let progress = min(max(elapsed / duration, 0.0), 1.0)
                
                VStack(spacing: 5) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.18))
                                .frame(height: 5)
                            
                            Capsule()
                                .fill(Color.white.opacity(0.9))
                                .frame(width: geo.size.width * progress, height: 5)
                        }
                    }
                    .frame(height: 5)
                    
                    HStack {
                        Text(timeFormatted(seconds: elapsed))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.65))
                        Spacer()
                        Text("-" + timeFormatted(seconds: max(0, duration - elapsed)))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                }
            }
            
            // Hàng 3: Cụm phím điều khiển đồng bộ theo tuỳ chỉnh & Nút Lời bài hát
            HStack(spacing: 0) {
                Spacer()
                
                // Các nút điều khiển media
                let slots = musicControlSlots.filter { $0 != .none }
                HStack(spacing: slots.count > 3 ? 20 : 32) {
                    ForEach(slots, id: \.self) { slot in
                        mediaButton(for: slot, isCompact: true)
                    }
                }
                
                Spacer()
                
                // Icon Lời bài hát (Karaoke) góc phải
                Button {
                    windowController.setFullScreen(true)
                } label: {
                    Image(systemName: "quote.bubble.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(hasLyrics ? Color.white.opacity(0.95) : Color.white.opacity(0.45))
                }
                .buttonStyle(.plain)
                .help("Nhấp để phóng to toàn màn hình hiển thị lời bài hát (Karaoke)")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(width: 410, height: hasLyrics ? 205 : 180)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.black.opacity(0.85))
                
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
    
    // =========================================================================
    // MARK: - 2. Full-Screen Immersive Player View (Ảnh bìa to + Lời Karaoke)
    // =========================================================================
    private var fullScreenPlayerView: some View {
        ZStack {
            // Nền Ambient phát sáng màu của bài hát phủ toàn màn hình
            ambientDynamicBackground
            
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let albumSize = min(max(h * 0.45, 280), 600)
                let contentWidth = w * 0.85
                let hasLyrics = !musicManager.syncedLyrics.isEmpty || !musicManager.currentLyrics.isEmpty || musicManager.isFetchingLyrics
                
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
    
    // Nền Ambient động phủ toàn màn hình
    private var ambientDynamicBackground: some View {
        ZStack {
            Color(nsColor: musicManager.avgColor)
            
            // Quầng sáng to chính giữa bên trái
            Circle()
                .fill(Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.9).opacity(0.6))
                .frame(width: 650, height: 650)
                .blur(radius: 120)
                .offset(x: -250, y: -50)
            
            // Quầng sáng phụ bên phải
            Circle()
                .fill(Color.white.opacity(0.2))
                .frame(width: 550, height: 550)
                .blur(radius: 110)
                .offset(x: 280, y: 120)
            
            // Lớp kính mờ phủ ngoài
            Rectangle()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
            
            Rectangle()
                .fill(Color.black.opacity(0.2))
        }
    }
    
    // Cột trái Full Screen: Ảnh bài hát to + Thông tin + Điều khiển
    private func fullScreenLeftColumn(albumSize: CGFloat) -> some View {
        VStack(spacing: albumSize * 0.08) {
            // Ảnh bìa bài hát to nổi bật (bấm vào để thu nhỏ về compact)
            Button {
                windowController.setFullScreen(false)
            } label: {
                ZStack(alignment: .bottomTrailing) {
                    Image(nsImage: musicManager.albumArt)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: albumSize, height: albumSize)
                        .clipShape(RoundedRectangle(cornerRadius: albumSize * 0.08, style: .continuous))
                        .shadow(color: Color(nsColor: musicManager.avgColor).opacity(0.55), radius: albumSize * 0.1, x: 0, y: albumSize * 0.05)
                        .shadow(color: .black.opacity(0.6), radius: albumSize * 0.06, x: 0, y: albumSize * 0.02)
                    
                    AppIcon(for: musicManager.bundleIdentifier ?? "com.apple.Music")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: albumSize * 0.1, height: albumSize * 0.1)
                        .offset(x: albumSize * 0.02, y: albumSize * 0.02)
                        .shadow(radius: 6)
                }
            }
            .buttonStyle(.plain)
            .help("Nhấp vào ảnh để thu nhỏ")
            
            // Thông tin bài hát
            VStack(spacing: albumSize * 0.02) {
                Text(musicManager.songTitle)
                    .font(.system(size: max(albumSize * 0.075, 20), weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
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
            
            // Thanh tiến trình lớn
            TimelineView(.animation(minimumInterval: 0.25)) { timeline in
                let elapsed = musicManager.estimatedPlaybackPosition(at: timeline.date)
                let duration = max(1.0, musicManager.songDuration)
                let progress = min(max(elapsed / duration, 0.0), 1.0)
                
                VStack(spacing: 8) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.2))
                                .frame(height: 6)
                            
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.white, Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.9)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geo.size.width * progress, height: 6)
                        }
                    }
                    .frame(height: 6)
                    
                    HStack {
                        Text(timeFormatted(seconds: elapsed))
                            .font(.system(size: max(albumSize * 0.04, 11), weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.65))
                        Spacer()
                        Text("-" + timeFormatted(seconds: max(0, duration - elapsed)))
                            .font(.system(size: max(albumSize * 0.04, 11), weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                }
                .frame(width: albumSize * 1.3)
            }
            
            // Bộ phím điều khiển đồng bộ
            let slots = musicControlSlots.filter { $0 != .none }
            HStack(spacing: slots.count > 3 ? 20 : 28) {
                ForEach(slots, id: \.self) { slot in
                    mediaButton(for: slot, isCompact: false)
                }
            }
        }
    }
    
    // Cột phải Full Screen: Lời bài hát Karaoke toàn màn hình
    @ViewBuilder
    private func fullScreenLyricsColumn(columnWidth: CGFloat, viewHeight: CGFloat) -> some View {
        let baseFontSize = min(max(columnWidth * 0.065, 24), 48)
        let activeFontSize = baseFontSize + 2 // Zoom nhẹ 2px tránh xuống dòng
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
                                    Text(item.text)
                                        .font(.system(size: isCurrent ? activeFontSize : inactiveFontSize, weight: isCurrent ? .bold : .medium, design: .rounded))
                                        .foregroundStyle(
                                            isCurrent
                                            ? Color.white
                                            : isPast
                                            ? Color.white.opacity(0.3)
                                            : Color.white.opacity(0.6)
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
                    .background(
                        TimelineView(.animation(minimumInterval: 0.2)) { timeline in
                            let currentElapsed = max(0, musicManager.estimatedPlaybackPosition(at: timeline.date) - 0.7)
                            let newIndex = currentLyricIndex(at: currentElapsed)
                            Color.clear
                                .onChange(of: newIndex) { _, newValue in
                                    DispatchQueue.main.async {
                                        if newValue != activeLyricIndex {
                                            activeLyricIndex = newValue
                                            withAnimation(.smooth(duration: 0.45)) {
                                                proxy.scrollTo(newValue, anchor: .center)
                                            }
                                        }
                                    }
                                }
                                .onAppear {
                                    activeLyricIndex = newIndex
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        proxy.scrollTo(activeLyricIndex, anchor: .center)
                                    }
                                }
                        }
                    )
                }
            } else if !musicManager.currentLyrics.isEmpty {
                ScrollView(.vertical, showsIndicators: false) {
                    Text(musicManager.currentLyrics)
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
                    Text(musicManager.isPlaying ? "Đang phát nhạc" : "Đang tạm dừng")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(height: viewHeight)
    }

    
    // MARK: - Dynamic Media Button
    @ViewBuilder
    private func mediaButton(for slot: MusicControlButton, isCompact: Bool) -> some View {
        let size: CGFloat = isCompact ? (slot.prefersLargeScale ? 26 : 18) : (slot.prefersLargeScale ? 24 : 22)
        let opacity: Double = slot.prefersLargeScale ? 1.0 : 0.9
        
        switch slot {
        case .shuffle:
            Button { musicManager.toggleShuffle() } label: { Image(systemName: "shuffle").font(.system(size: isCompact ? 18 : 17)).foregroundStyle(musicManager.isShuffled ? Color.green : .white.opacity(0.55)) }.buttonStyle(.plain)
        case .previous:
            Button { musicManager.previousTrack() } label: { Image(systemName: "backward.fill").font(.system(size: size)).foregroundStyle(.white.opacity(opacity)) }.buttonStyle(.plain)
        case .playPause:
            Button { musicManager.togglePlay() } label: {
                if isCompact {
                    Image(systemName: musicManager.isPlaying ? "pause.fill" : "play.fill").font(.system(size: size)).foregroundStyle(.white)
                } else {
                    ZStack {
                        Circle().fill(Color.white.opacity(0.2)).frame(width: 58, height: 58)
                        Image(systemName: musicManager.isPlaying ? "pause.fill" : "play.fill").font(.system(size: size)).foregroundStyle(.white).offset(x: musicManager.isPlaying ? 0 : 1)
                    }
                }
            }.buttonStyle(.plain)
        case .next:
            Button { musicManager.nextTrack() } label: { Image(systemName: "forward.fill").font(.system(size: size)).foregroundStyle(.white.opacity(opacity)) }.buttonStyle(.plain)
        case .repeatMode:
            Button { musicManager.toggleRepeat() } label: { Image(systemName: musicManager.repeatMode == .one ? "repeat.1" : "repeat").font(.system(size: isCompact ? 18 : 17)).foregroundStyle(musicManager.repeatMode != .off ? Color.green : .white.opacity(0.55)) }.buttonStyle(.plain)
        case .favorite:
            Button { musicManager.toggleFavoriteTrack() } label: { Image(systemName: musicManager.isFavoriteTrack ? "heart.fill" : "heart").font(.system(size: isCompact ? 18 : 20)).foregroundStyle(musicManager.isFavoriteTrack ? Color.red : .white.opacity(opacity)) }.buttonStyle(.plain).disabled(!musicManager.canFavoriteTrack)
        case .goBackward:
            Button { musicManager.skip(seconds: -15) } label: { Image(systemName: "gobackward.15").font(.system(size: isCompact ? 18 : 20)).foregroundStyle(.white.opacity(opacity)) }.buttonStyle(.plain)
        case .goForward:
            Button { musicManager.skip(seconds: 15) } label: { Image(systemName: "goforward.15").font(.system(size: isCompact ? 18 : 20)).foregroundStyle(.white.opacity(opacity)) }.buttonStyle(.plain)
        case .volume:
            Button { musicManager.setVolume(to: musicManager.volume > 0 ? 0 : 0.5) } label: { Image(systemName: musicManager.volume > 0 ? "speaker.wave.2.fill" : "speaker.slash.fill").font(.system(size: isCompact ? 16 : 18)).foregroundStyle(.white.opacity(opacity)) }.buttonStyle(.plain)
        case .none:
            EmptyView()
        }
    }
    
    // MARK: - Animated Waveform Helper
    private var soundWaveform: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<6) { i in
                WaveBar(isPlaying: musicManager.isPlaying, index: i, tintColor: Color(nsColor: musicManager.avgColor))
            }
        }
        .frame(height: 14)
    }
    
    private func currentLyricIndex(at time: Double) -> Int {
        let lyrics = musicManager.syncedLyrics
        guard !lyrics.isEmpty else { return 0 }
        var result = 0
        for (i, item) in lyrics.enumerated() {
            if item.time <= time {
                result = i
            } else {
                break
            }
        }
        return result
    }
    
    private func timeFormatted(seconds: Double) -> String {
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - WaveBar Component
private struct WaveBar: View {
    let isPlaying: Bool
    let index: Int
    let tintColor: Color
    
    @State private var animatingHeight: CGFloat = 4
    
    var body: some View {
        Capsule()
            .fill(isPlaying ? tintColor.ensureMinimumBrightness(factor: 0.85) : Color.gray.opacity(0.4))
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
                    animatingHeight = 3
                }
            }
    }
    
    private func startAnimation() {
        let randomDuration = Double.random(in: 0.3...0.6)
        let targetHeights: [CGFloat] = [6, 14, 10, 16, 8, 12]
        let h = targetHeights[index % targetHeights.count]
        
        withAnimation(.easeInOut(duration: randomDuration).repeatForever(autoreverses: true)) {
            animatingHeight = h
        }
    }
}
