//
//  LockScreenMediaView.swift
//  NotchPulse
//
//  Created for NotchPulse v2.0 - iPhone-style Lock Screen Media Player
//

import Combine
import Defaults
import SwiftUI

struct LockScreenMediaView: View {
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject var faceIDManager = FaceIDManager.shared
    @Default(.lockScreenPlayerShowLyrics) var showLyrics
    @Default(.enableFaceID) var enableFaceID
    
    var body: some View {
        HStack(spacing: 20) {
            // MARK: - Left Column: Album Art & Controls
            leftColumn
                .frame(width: showLyrics ? 310 : 420)
            
            // MARK: - Right Column: Synced Lyrics (Karaoke Effect)
            if showLyrics {
                Divider()
                    .background(Color.white.opacity(0.12))
                    .frame(height: 190)
                
                rightLyricsColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(20)
        .frame(width: showLyrics ? 720 : 460, height: 250)
        .background(
            ZStack {
                // Dynamic ambient glow from album artwork
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color(nsColor: musicManager.avgColor).opacity(0.22))
                    .blur(radius: 35)
                
                // Frosted Glassmorphism background
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
                
                // Dark glass overlay
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.black.opacity(0.55))
                
                // Subtle border glow
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.3),
                                Color.white.opacity(0.08),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.5), radius: 25, x: 0, y: 12)
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Left Column Component
    private var leftColumn: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                // Large Album Artwork
                ZStack(alignment: .bottomTrailing) {
                    Image(nsImage: musicManager.albumArt)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 90, height: 90)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: Color(nsColor: musicManager.avgColor).opacity(0.4), radius: 10, x: 0, y: 4)
                    
                    // Source App Icon Badge
                    AppIcon(for: musicManager.bundleIdentifier ?? "com.apple.Music")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 22, height: 22)
                        .offset(x: 4, y: 4)
                        .shadow(radius: 4)
                }
                
                // Title & Artist Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(musicManager.songTitle)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    
                    Text(musicManager.artistName)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.7))
                        .lineLimit(1)
                    
                    Text(musicManager.album)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.gray.opacity(0.8))
                        .lineLimit(1)
                    
                    // Live Audio Waveform Animation
                    soundWaveform
                        .padding(.top, 2)
                }
                Spacer(minLength: 0)
                
                // Face ID Re-Scan Button on Lock Screen
                if enableFaceID && faceIDManager.isEnrolled {
                    Button {
                        faceIDManager.startRecognitionOnWake()
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: "faceid")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(faceIDManager.isScanning ? .cyan : .white.opacity(0.85))
                            
                            Text(faceIDManager.isScanning ? "Đang quét…" : "Face ID")
                                .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                                .foregroundStyle(faceIDManager.isScanning ? .cyan : .white.opacity(0.75))
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(faceIDManager.isScanning ? Color.cyan.opacity(0.25) : Color.white.opacity(0.1))
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Nhấp để quét lại Face ID")
                }
            }
            
            // Scrubber / Progress Bar
            VStack(spacing: 3) {
                TimelineView(.animation(minimumInterval: 0.2)) { timeline in
                    let elapsed = musicManager.estimatedPlaybackPosition(at: timeline.date)
                    let duration = max(1.0, musicManager.songDuration)
                    let progress = min(max(elapsed / duration, 0.0), 1.0)
                    
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.18))
                                .frame(height: 4)
                            
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.white, Color(nsColor: musicManager.avgColor)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geo.size.width * progress, height: 4)
                        }
                    }
                    .frame(height: 4)
                    
                    HStack {
                        Text(timeFormatted(seconds: elapsed))
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.gray)
                        Spacer()
                        Text("-" + timeFormatted(seconds: max(0, duration - elapsed)))
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.gray)
                    }
                }
            }
            
            // Playback Control Buttons
            HStack(spacing: 24) {
                Button(action: { musicManager.previousTrack() }) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: { musicManager.togglePlay() }) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.2))
                            .frame(width: 44, height: 44)
                        
                        Image(systemName: musicManager.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.white)
                            .offset(x: musicManager.isPlaying ? 0 : 1)
                    }
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: { musicManager.nextTrack() }) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .buttonStyle(PlainButtonStyle())
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }
    
    // MARK: - Right Column: Synced Lyrics (Karaoke Effect)
    private var rightLyricsColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("LYRICS", systemImage: "quote.bubble.fill")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.gray)
                Spacer()
                if musicManager.isFetchingLyrics {
                    ProgressView()
                        .scaleEffect(0.6)
                }
            }
            
            if !musicManager.syncedLyrics.isEmpty {
                TimelineView(.animation(minimumInterval: 0.25)) { timeline in
                    let currentElapsed = musicManager.estimatedPlaybackPosition(at: timeline.date)
                    let activeIndex = currentLyricIndex(at: currentElapsed)
                    
                    ScrollViewReader { proxy in
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 14) {
                                ForEach(Array(musicManager.syncedLyrics.enumerated()), id: \.offset) { index, item in
                                    let isCurrent = (index == activeIndex)
                                    let isPast = (index < activeIndex)
                                    
                                    Text(item.text)
                                        .font(.system(size: isCurrent ? 17 : 14, weight: isCurrent ? .bold : .medium, design: .rounded))
                                        .foregroundStyle(
                                            isCurrent
                                            ? Color.white
                                            : isPast
                                            ? Color.white.opacity(0.35)
                                            : Color.white.opacity(0.6)
                                        )
                                        .scaleEffect(isCurrent ? 1.05 : 1.0, anchor: .leading)
                                        .shadow(color: isCurrent ? Color(nsColor: musicManager.avgColor).opacity(0.8) : .clear, radius: 8)
                                        .animation(.easeInOut(duration: 0.25), value: isCurrent)
                                        .id(index)
                                }
                            }
                            .padding(.vertical, 30)
                        }
                        .onChange(of: activeIndex) { _, newIndex in
                            withAnimation(.smooth(duration: 0.4)) {
                                proxy.scrollTo(newIndex, anchor: .center)
                            }
                        }
                    }
                }
            } else if !musicManager.currentLyrics.isEmpty {
                ScrollView(.vertical, showsIndicators: false) {
                    Text(musicManager.currentLyrics)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineSpacing(6)
                        .padding(.vertical, 10)
                }
            } else {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "music.note.list")
                        .font(.system(size: 28))
                        .foregroundStyle(.gray.opacity(0.5))
                    Text(musicManager.isPlaying ? "Enjoy the music" : "Music is paused")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.gray)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
    
    // MARK: - Animated Waveform Helper
    private var soundWaveform: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<6) { i in
                WaveBar(isPlaying: musicManager.isPlaying, index: i, tintColor: Color(nsColor: musicManager.avgColor))
            }
        }
        .frame(height: 12)
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
            .fill(isPlaying ? tintColor.ensureMinimumBrightness(factor: 0.8) : Color.gray.opacity(0.4))
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
        let targetHeights: [CGFloat] = [6, 12, 9, 14, 8, 11]
        let h = targetHeights[index % targetHeights.count]
        
        withAnimation(.easeInOut(duration: randomDuration).repeatForever(autoreverses: true)) {
            animatingHeight = h
        }
    }
}
