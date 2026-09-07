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
    
    var body: some View {
        ZStack {
            if windowController.isFullScreen {
                fullScreenPlayerView
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                compactPlayerView
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(.spring(response: 0.65, dampingFraction: 0.82, blendDuration: 0), value: windowController.isFullScreen)
    }
    
    // =========================================================================
    // MARK: - 1. Compact Player View (Y hệt ảnh Lock Screen iPhone người dùng gửi)
    // =========================================================================
    private var compactPlayerView: some View {
        VStack(spacing: 12) {
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
            
            // Hàng 3: Cụm phím điều khiển Previous, Play/Pause, Next & AirPlay icon
            HStack(spacing: 0) {
                Spacer()
                
                // Cụm 3 nút chính căn giữa
                HStack(spacing: 32) {
                    Button {
                        musicManager.previousTrack()
                    } label: {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        musicManager.togglePlay()
                    } label: {
                        Image(systemName: musicManager.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        musicManager.nextTrack()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .buttonStyle(.plain)
                }
                
                Spacer()
                
                // Icon nguồn nhạc / AirPlay góc phải
                Button {
                    windowController.setFullScreen(true)
                } label: {
                    Image(systemName: "airplayaudio")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(width: 410, height: 180)
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
            
            VStack(spacing: 0) {
                // Thanh tiêu đề phía trên (Thu nhỏ chỉ cần bấm vào ảnh đĩa/album)
                HStack {
                    Spacer()
                    
                    // Nút tua lùi 5s / tua tới 5s (chỉ hiện nếu user có thêm trong tuỳ chỉnh)
                    if musicControlSlots.contains(.goBackward) || musicControlSlots.contains(.goForward) {
                        HStack(spacing: 12) {
                            Button {
                                musicManager.skip(seconds: -5)
                            } label: {
                                Image(systemName: "gobackward.5")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.white.opacity(0.75))
                            }
                            .buttonStyle(.plain)
                            
                            Button {
                                musicManager.skip(seconds: 5)
                            } label: {
                                Image(systemName: "goforward.5")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.white.opacity(0.75))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 48)
                .padding(.top, 40)
                
                Spacer(minLength: 20)
                
                // Nội dung 2 cột: Trái là Ảnh bìa to & Điều khiển, Phải là Lời bài hát Karaoke
                let hasLyrics = !musicManager.syncedLyrics.isEmpty || !musicManager.currentLyrics.isEmpty || musicManager.isFetchingLyrics
                
                HStack(alignment: .center, spacing: 60) {
                    if hasLyrics {
                        // CỘT TRÁI: Ảnh bìa to + Tên bài hát + Timeline + Phím điều khiển
                        fullScreenLeftColumn
                            .frame(maxWidth: 440)
                        
                        // CỘT PHẢI: Lời bài hát Karaoke chạy thời gian thực
                        fullScreenLyricsColumn
                            .frame(maxWidth: 580)
                    } else {
                        Spacer()
                        
                        // CỘT TRÁI: Đưa ra giữa khi không có lời bài hát
                        fullScreenLeftColumn
                            .frame(maxWidth: 440)
                        
                        Spacer()
                    }
                }
                .padding(.horizontal, 50)
                
                Spacer(minLength: 40)
            }
            .scaleEffect(0.9)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }
    
    // Nền Ambient động phủ toàn màn hình
    private var ambientDynamicBackground: some View {
        ZStack {
            Color.black
            
            // Quầng sáng to chính giữa bên trái
            Circle()
                .fill(Color(nsColor: musicManager.avgColor).opacity(0.45))
                .frame(width: 650, height: 650)
                .blur(radius: 120)
                .offset(x: -250, y: -50)
            
            // Quầng sáng phụ bên phải
            Circle()
                .fill(Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.9).opacity(0.35))
                .frame(width: 550, height: 550)
                .blur(radius: 110)
                .offset(x: 280, y: 120)
            
            // Lớp kính mờ phủ ngoài
            Rectangle()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
            
            Rectangle()
                .fill(Color.black.opacity(0.45))
        }
    }
    
    // Cột trái Full Screen: Ảnh bài hát to + Thông tin + Điều khiển
    private var fullScreenLeftColumn: some View {
        VStack(spacing: 24) {
            // Ảnh bìa bài hát to nổi bật (bấm vào để thu nhỏ về compact)
            Button {
                windowController.setFullScreen(false)
            } label: {
                ZStack(alignment: .bottomTrailing) {
                    Image(nsImage: musicManager.albumArt)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 320, height: 320)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .shadow(color: Color(nsColor: musicManager.avgColor).opacity(0.55), radius: 35, x: 0, y: 15)
                        .shadow(color: .black.opacity(0.6), radius: 20, x: 0, y: 8)
                    
                    AppIcon(for: musicManager.bundleIdentifier ?? "com.apple.Music")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 34, height: 34)
                        .offset(x: 6, y: 6)
                        .shadow(radius: 6)
                }
            }
            .buttonStyle(.plain)
            .help("Nhấp vào ảnh để thu nhỏ")
            
            // Thông tin bài hát
            VStack(spacing: 6) {
                Text(musicManager.songTitle)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
                
                Text(musicManager.artistName)
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.8))
                    .lineLimit(1)
                
                if !musicManager.album.isEmpty {
                    Text(musicManager.album)
                        .font(.system(size: 13, weight: .regular))
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
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.65))
                        Spacer()
                        Text("-" + timeFormatted(seconds: max(0, duration - elapsed)))
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                }
            }
            
            // Bộ phím điều khiển đầy đủ: Shuffle, Prev, Play/Pause to tròn, Next, Repeat
            HStack(spacing: 28) {
                Button {
                    musicManager.toggleShuffle()
                } label: {
                    Image(systemName: "shuffle")
                        .font(.system(size: 17))
                        .foregroundStyle(musicManager.isShuffled ? Color.green : Color.white.opacity(0.55))
                }
                .buttonStyle(.plain)
                
                Button {
                    musicManager.previousTrack()
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .buttonStyle(.plain)
                
                Button {
                    musicManager.togglePlay()
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.2))
                            .frame(width: 58, height: 58)
                        
                        Image(systemName: musicManager.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.white)
                            .offset(x: musicManager.isPlaying ? 0 : 1)
                    }
                }
                .buttonStyle(.plain)
                
                Button {
                    musicManager.nextTrack()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .buttonStyle(.plain)
                
                Button {
                    musicManager.toggleRepeat()
                } label: {
                    Image(systemName: musicManager.repeatMode == .one ? "repeat.1" : "repeat")
                        .font(.system(size: 17))
                        .foregroundStyle(musicManager.repeatMode != .off ? Color.green : Color.white.opacity(0.55))
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    // Cột phải Full Screen: Lời bài hát Karaoke toàn màn hình
    private var fullScreenLyricsColumn: some View {
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
                TimelineView(.animation(minimumInterval: 0.25)) { timeline in
                    let currentElapsed = musicManager.estimatedPlaybackPosition(at: timeline.date)
                    let activeIndex = currentLyricIndex(at: currentElapsed)
                    
                    ScrollViewReader { proxy in
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 22) {
                                ForEach(Array(musicManager.syncedLyrics.enumerated()), id: \.offset) { index, item in
                                    let isCurrent = (index == activeIndex)
                                    let isPast = (index < activeIndex)
                                    
                                    Button {
                                        // Nhấp vào câu hát bất kỳ để tua tới đoạn đó
                                        musicManager.seek(to: item.time)
                                    } label: {
                                        Text(item.text)
                                            .font(.system(size: isCurrent ? 26 : 19, weight: isCurrent ? .bold : .medium, design: .rounded))
                                            .foregroundStyle(
                                                isCurrent
                                                ? Color.white
                                                : isPast
                                                ? Color.white.opacity(0.3)
                                                : Color.white.opacity(0.6)
                                            )
                                            .scaleEffect(isCurrent ? 1.05 : 1.0, anchor: .leading)
                                            .shadow(color: isCurrent ? Color(nsColor: musicManager.avgColor).opacity(0.9) : .clear, radius: 12)
                                            .multilineTextAlignment(.leading)
                                            .fixedSize(horizontal: false, vertical: true)
                                            .animation(.easeInOut(duration: 0.25), value: isCurrent)
                                    }
                                    .buttonStyle(.plain)
                                    .id(index)
                                }
                            }
                            .padding(.vertical, 100)
                        }
                        .onChange(of: activeIndex) { _, newIndex in
                            withAnimation(.smooth(duration: 0.45)) {
                                proxy.scrollTo(newIndex, anchor: .center)
                            }
                        }
                    }
                }
            } else if !musicManager.currentLyrics.isEmpty {
                ScrollView(.vertical, showsIndicators: false) {
                    Text(musicManager.currentLyrics)
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.8))
                        .lineSpacing(10)
                        .padding(.vertical, 30)
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
        .frame(maxHeight: 520)
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
