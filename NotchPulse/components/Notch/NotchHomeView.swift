//
//  NotchHomeView.swift
//  NotchPulse
//
//  Created by Hugo Persson on 2024-08-18.
//  Modified by Harsh Vardhan Goswami & Richard Kunkli & Mustafa Ramadan
//

import Combine
import Defaults
import SwiftUI

// MARK: - Music Player Components

struct MusicPlayerView: View {
    @EnvironmentObject var vm: NotchPulseViewModel
    let albumArtNamespace: Namespace.ID
    var allocatedWidth: CGFloat? = nil

    private var artSize: CGFloat {
        if let width = allocatedWidth {
            // Adaptive album art sizing from 82px to 110px based on allocated column width
            return min(110, max(82, (width - 24) * 0.30))
        }
        return 110
    }

    var body: some View {
        HStack(spacing: 8) {
            AlbumArtView(vm: vm, albumArtNamespace: albumArtNamespace, size: artSize)
                .padding(.vertical, 2)
            MusicControlsView().drawingGroup().compositingGroup()
        }
    }
}

struct AlbumArtView: View {
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject var vm: NotchPulseViewModel
    let albumArtNamespace: Namespace.ID
    var size: CGFloat = 110

    private var imageAspectRatio: CGFloat {
        let imgSize = musicManager.albumArt.size
        guard imgSize.width > 0 && imgSize.height > 0 else { return 1.0 }
        return imgSize.width / imgSize.height
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if Defaults[.lightingEffect] {
                albumArtBackground
            }
            albumArtButton
        }
        // Comfortable breathing room from the left curved notch corner
        .padding(.leading, 8)
    }

    private var albumArtBackground: some View {
        Image(nsImage: musicManager.albumArt)
            .resizable()
            .aspectRatio(imageAspectRatio, contentMode: .fit)
            .frame(width: size, height: size)
            .clipped()
            .clipShape(
                RoundedRectangle(
                    cornerRadius: Defaults[.cornerRadiusScaling]
                        ? MusicPlayerImageSizes.cornerRadiusInset.opened
                        : MusicPlayerImageSizes.cornerRadiusInset.closed)
            )
            .scaleEffect(x: 1.3, y: 1.4)
            .rotationEffect(.degrees(92))
            .blur(radius: 40)
            .opacity(musicManager.isPlaying ? 0.5 : 0)
    }

    private var albumArtButton: some View {
        ZStack {
            Button {
                musicManager.openMusicApp()
            } label: {
                ZStack(alignment:.bottomTrailing) {
                    albumArtImage
                    appIconOverlay
                }
            }
            .buttonStyle(PlainButtonStyle())
            .scaleEffect(musicManager.isPlaying ? 1 : 0.85)
            
            albumArtDarkOverlay
        }
    }

    private var albumArtDarkOverlay: some View {
        RoundedRectangle(
            cornerRadius: Defaults[.cornerRadiusScaling]
                ? MusicPlayerImageSizes.cornerRadiusInset.opened
                : MusicPlayerImageSizes.cornerRadiusInset.closed)
            .aspectRatio(imageAspectRatio, contentMode: .fit)
            .frame(width: size, height: size)
            .foregroundColor(Color.black)
            .opacity(musicManager.isPlaying ? 0 : 0.8)
            .blur(radius: 50)
            .allowsHitTesting(false)
    }

    private var albumArtImage: some View {
        Image(nsImage: musicManager.albumArt)
            .resizable()
            .aspectRatio(imageAspectRatio, contentMode: .fit)
            .frame(width: size, height: size)
            .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
            .clipped()
            .clipShape(
                RoundedRectangle(
                    cornerRadius: Defaults[.cornerRadiusScaling]
                        ? MusicPlayerImageSizes.cornerRadiusInset.opened
                        : MusicPlayerImageSizes.cornerRadiusInset.closed)
            )
    }

    @ViewBuilder
    private var appIconOverlay: some View {
        if vm.notchState == .open && !musicManager.usingAppIconForArtwork {
            let iconSize: CGFloat = max(22, size * 0.27)
            AppIcon(for: musicManager.bundleIdentifier ?? "com.apple.Music")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: iconSize, height: iconSize)
                .offset(x: 8, y: 8)
                .transition(.scale.combined(with: .opacity))
                .zIndex(2)
        }
    }
}

struct MusicControlsView: View {
    @ObservedObject var musicManager = MusicManager.shared
        @EnvironmentObject var vm: NotchPulseViewModel
        @ObservedObject var webcamManager = WebcamManager.shared
    @State private var sliderValue: Double = 0
    @State private var dragging: Bool = false
    @State private var lastDragged: Date = .distantPast
    @Default(.musicControlSlots) private var slotConfig
    @Default(.musicControlSlotLimit) private var slotLimit

    var body: some View {
        VStack(alignment: .leading) {
            songInfoAndSlider
            slotToolbar
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var songInfoAndSlider: some View {
        GeometryReader { geo in
            VStack(alignment: .leading, spacing: 4) {
                songInfo(width: geo.size.width)
                musicSlider
            }
        }
        .padding(.top, 6)
        .padding(.leading, 2)
    }

    private func songInfo(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            MarqueeText(
                $musicManager.songTitle, font: .headline, nsFont: .headline, textColor: .white,
                frameWidth: width)
            MarqueeText(
                $musicManager.artistName,
                font: .headline,
                nsFont: .headline,
                textColor: Defaults[.playerColorTinting]
                    ? Color(nsColor: musicManager.avgColor)
                        .ensureMinimumBrightness(factor: 0.6) : .gray,
                frameWidth: width
            )
            .fontWeight(.medium)
            if Defaults[.enableLyrics] {
                TimelineView(.animation(minimumInterval: 0.25)) { timeline in
                    let currentElapsed: Double = {
                        guard musicManager.isPlaying else { return musicManager.elapsedTime }
                        let delta = timeline.date.timeIntervalSince(musicManager.timestampDate)
                        let progressed = musicManager.elapsedTime + (delta * musicManager.playbackRate)
                        return min(max(progressed, 0), musicManager.songDuration)
                    }()
                    let line: String = {
                        if musicManager.isFetchingLyrics { return "Loading lyrics…" }
                        if !musicManager.syncedLyrics.isEmpty {
                            return musicManager.lyricLine(at: currentElapsed)
                        }
                        let trimmed = musicManager.currentLyrics.trimmingCharacters(in: .whitespacesAndNewlines)
                        return trimmed.isEmpty ? "No lyrics found" : trimmed.replacingOccurrences(of: "\n", with: " ")
                    }()
                    let isPersian = line.unicodeScalars.contains { scalar in
                        let v = scalar.value
                        return v >= 0x0600 && v <= 0x06FF
                    }
                    MarqueeText(
                        .constant(line),
                        font: .subheadline,
                        nsFont: .subheadline,
                        textColor: musicManager.isFetchingLyrics ? .gray.opacity(0.7) : .gray,
                        frameWidth: width
                    )
                    .font(isPersian ? .custom("Vazirmatn-Regular", size: NSFont.preferredFont(forTextStyle: .subheadline).pointSize) : .subheadline)
                    .lineLimit(1)
                    .opacity(musicManager.isPlaying ? 1 : 0)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private var musicSlider: some View {
        TimelineView(.animation(minimumInterval: musicManager.playbackRate > 0 ? 0.1 : nil)) { timeline in
            MusicSliderView(
                sliderValue: $sliderValue,
                duration: $musicManager.songDuration,
                lastDragged: $lastDragged,
                color: musicManager.avgColor,
                dragging: $dragging,
                currentDate: timeline.date,
                timestampDate: musicManager.timestampDate,
                elapsedTime: musicManager.elapsedTime,
                playbackRate: musicManager.playbackRate,
                isPlaying: musicManager.isPlaying
            ) { newValue in
                MusicManager.shared.seek(to: newValue)
            }
            .padding(.top, 5)
            .frame(height: 36)
        }
    }

    private var slotToolbar: some View {
        let slots = activeSlots
        let spacing: CGFloat = Defaults[.notchOpenWidth] <= 620 ? 4 : 6
        return HStack(spacing: spacing) {
            ForEach(Array(slots.enumerated()), id: \.offset) { index, slot in
                slotView(for: slot)
                    .frame(alignment: .center)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var activeSlots: [MusicControlButton] {
        let sanitizedLimit = min(
            max(slotLimit, MusicControlButton.minSlotCount),
            MusicControlButton.maxSlotCount
        )
        let padded = slotConfig.padded(to: sanitizedLimit, filler: .none)
        let result = Array(padded.prefix(sanitizedLimit))
        // If calendar and camera are both visible alongside music, hide the edge slots
        let shouldHideEdges = Defaults[.showCalendar] && Defaults[.showMirror] && webcamManager.cameraAvailable && vm.isCameraExpanded
        if shouldHideEdges && result.count >= 5 {
            return Array(result.dropFirst().dropLast())
        }

        return result
    }

    @ViewBuilder
    private func slotView(for slot: MusicControlButton) -> some View {
        switch slot {
        case .shuffle:
            HoverButton(icon: "shuffle", iconColor: musicManager.isShuffled ? .red : .primary, scale: .medium) {
                MusicManager.shared.toggleShuffle()
            }
        case .previous:
            HoverButton(icon: "backward.fill", scale: .medium) {
                MusicManager.shared.previousTrack()
            }
        case .playPause:
            HoverButton(icon: musicManager.isPlaying ? "pause.fill" : "play.fill", scale: .large) {
                MusicManager.shared.togglePlay()
            }
        case .next:
            HoverButton(icon: "forward.fill", scale: .medium) {
                MusicManager.shared.nextTrack()
            }
        case .repeatMode:
            HoverButton(icon: repeatIcon, iconColor: repeatIconColor, scale: .medium) {
                MusicManager.shared.toggleRepeat()
            }
        case .volume:
            VolumeControlView()
        case .favorite:
            FavoriteControlButton()
        case .goBackward:
            HoverButton(icon: "gobackward.15", scale: .medium) {
                MusicManager.shared.skip(seconds: -15)
            }
        case .goForward:
            HoverButton(icon: "goforward.15", scale: .medium) {
                MusicManager.shared.skip(seconds: 15)
            }
        case .none:
            Color.clear.frame(height: 1)
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
            return .primary
        case .all, .one:
            return .red
        }
    }
}

struct FavoriteControlButton: View {
    @ObservedObject var musicManager = MusicManager.shared

    var body: some View {
        HoverButton(icon: iconName, iconColor: iconColor, scale: .medium) {
            MusicManager.shared.toggleFavoriteTrack()
        }
        .disabled(!musicManager.canFavoriteTrack)
        .opacity(musicManager.canFavoriteTrack ? 1 : 0.35)
    }

    private var iconName: String {
        musicManager.isFavoriteTrack ? "heart.fill" : "heart"
    }

    private var iconColor: Color {
        musicManager.isFavoriteTrack ? .red : .primary
    }
}

private extension Array where Element == MusicControlButton {
    func padded(to length: Int, filler: MusicControlButton) -> [MusicControlButton] {
        if count >= length { return self }
        return self + Array(repeating: filler, count: length - count)
    }
}

// MARK: - Volume Control View

struct VolumeControlView: View {
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject var volumeManager = VolumeManager.shared
    @State private var volumeSliderValue: Double = 0.5
    @State private var dragging: Bool = false
    @State private var showVolumeSlider: Bool = false
    @State private var lastVolumeUpdateTime: Date = Date.distantPast
    private let volumeUpdateThrottle: TimeInterval = 0.1
    
    private var isCurrentlyMuted: Bool {
        if musicManager.volumeControlSupported {
            return volumeSliderValue == 0
        } else {
            return volumeManager.isMuted || volumeManager.rawVolume == 0
        }
    }

    private var currentEffectiveVolume: Double {
        if musicManager.volumeControlSupported {
            return volumeSliderValue
        } else {
            return Double(volumeManager.rawVolume)
        }
    }

    private var volumeIcon: String {
        if isCurrentlyMuted {
            return "speaker.slash.fill"
        } else if currentEffectiveVolume < 0.33 {
            return "speaker.wave.1.fill"
        } else if currentEffectiveVolume < 0.66 {
            return "speaker.wave.2.fill"
        } else {
            return "speaker.wave.3.fill"
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.12)) {
                    showVolumeSlider.toggle()
                }
            }) {
                Image(systemName: volumeIcon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isCurrentlyMuted ? .gray : .white)
            }
            .buttonStyle(PlainButtonStyle())
            .frame(width: 24)

            if showVolumeSlider {
                CustomSlider(
                    value: Binding(
                        get: { currentEffectiveVolume },
                        set: { newValue in
                            volumeSliderValue = newValue
                            if musicManager.volumeControlSupported {
                                MusicManager.shared.setVolume(to: newValue)
                            } else {
                                VolumeManager.shared.setAbsolute(Float32(newValue))
                            }
                        }
                    ),
                    range: 0.0...1.0,
                    color: .white,
                    dragging: $dragging,
                    lastDragged: .constant(Date.distantPast),
                    onValueChange: { newValue in
                        if musicManager.volumeControlSupported {
                            MusicManager.shared.setVolume(to: newValue)
                        } else {
                            VolumeManager.shared.setAbsolute(Float32(newValue))
                        }
                    },
                    onDragChange: { newValue in
                        let now = Date()
                        if now.timeIntervalSince(lastVolumeUpdateTime) > volumeUpdateThrottle {
                            if musicManager.volumeControlSupported {
                                MusicManager.shared.setVolume(to: newValue)
                            } else {
                                VolumeManager.shared.setAbsolute(Float32(newValue))
                            }
                            lastVolumeUpdateTime = now
                        }
                    }
                )
                .frame(width: 48, height: 8)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .clipped()
        .onReceive(musicManager.$volume) { volume in
            if !dragging && musicManager.volumeControlSupported {
                volumeSliderValue = volume
            }
        }
        .onReceive(volumeManager.$rawVolume) { vol in
            if !dragging && !musicManager.volumeControlSupported {
                volumeSliderValue = Double(vol)
            }
        }
        .onChange(of: showVolumeSlider) { _, isShowing in
            if isShowing && musicManager.volumeControlSupported {
                Task {
                    await MusicManager.shared.syncVolumeFromActiveApp()
                }
            }
        }
    }
}

// MARK: - Main View

struct NotchHomeView: View {
    @EnvironmentObject var vm: NotchPulseViewModel
    @ObservedObject var webcamManager = WebcamManager.shared
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject var coordinator = NotchPulseViewCoordinator.shared
    @Default(.notchOpenWidth) private var notchOpenWidth
    let albumArtNamespace: Namespace.ID

    var body: some View {
        Group {
            if !coordinator.firstLaunch {
                GeometryReader { geo in
                    mainContent(totalWidth: geo.size.width)
                }
                .frame(minHeight: 148, maxHeight: .infinity, alignment: .top)
            }
        }
        .transition(.opacity)
    }

    private var shouldShowCamera: Bool {
        Defaults[.showMirror] && webcamManager.cameraAvailable && vm.isCameraExpanded
    }

    @ViewBuilder
    private func mainContent(totalWidth: CGFloat) -> some View {
        let isCalendarVisible = Defaults[.showCalendar]
        let isCameraVisible = shouldShowCamera
        
        // Comfortable horizontal margin to prevent corner clipping
        let horizontalPadding: CGFloat = 12
        let spacing: CGFloat = 14
        let baseWidth = totalWidth > 0 ? totalWidth : notchOpenWidth
        let availableWidth = max(280, baseWidth - (horizontalPadding * 2))
        
        let (mediaWidth, calendarWidth, cameraWidth): (CGFloat, CGFloat, CGFloat) = {
            if isCalendarVisible && isCameraVisible {
                let camW: CGFloat = 130
                let remainW = max(200, availableWidth - camW - (spacing * 2))
                return (remainW * 0.55, remainW * 0.45, camW)
            } else if isCalendarVisible {
                // 55% Media - 45% Calendar distribution!
                let remainW = max(240, availableWidth - spacing)
                return (remainW * 0.55, remainW * 0.45, 0)
            } else if isCameraVisible {
                let camW: CGFloat = 160
                let remainW = max(200, availableWidth - camW - spacing)
                return (remainW, 0, camW)
            } else {
                return (availableWidth, 0, 0)
            }
        }()

        HStack(alignment: .top, spacing: spacing) {
            MusicPlayerView(albumArtNamespace: albumArtNamespace, allocatedWidth: mediaWidth)
                .frame(width: mediaWidth)

            if isCalendarVisible {
                CalendarView()
                    .frame(width: calendarWidth, height: 148)
                    .clipped()
                    .onHover { isHovering in
                        vm.isHoveringCalendar = isHovering
                    }
                    .environmentObject(vm)
                    .transition(.opacity)
            }

            if isCameraVisible {
                CameraPreviewView(webcamManager: webcamManager)
                    .frame(width: cameraWidth)
                    .scaledToFit()
                    .opacity(vm.notchState == .closed ? 0 : 1)
                    .blur(radius: vm.notchState == .closed ? 20 : 0)
                    .animation(.interactiveSpring(response: 0.32, dampingFraction: 0.76, blendDuration: 0), value: shouldShowCamera)
            }
        }
        .padding(.horizontal, horizontalPadding)
        .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)), removal: .opacity))
        .blur(radius: vm.notchState == .closed ? 30 : 0)
    }
}

struct MusicSliderView: View {
    @Binding var sliderValue: Double
    @Binding var duration: Double
    @Binding var lastDragged: Date
    var color: NSColor
    @Binding var dragging: Bool
    let currentDate: Date
    let timestampDate: Date
    let elapsedTime: Double
    let playbackRate: Double
    let isPlaying: Bool
    var onValueChange: (Double) -> Void


    var body: some View {
        VStack {
            CustomSlider(
                value: $sliderValue,
                range: 0...duration,
                color: Defaults[.sliderColor] == SliderColorEnum.albumArt
                    ? Color(nsColor: color).ensureMinimumBrightness(factor: 0.8)
                    : Defaults[.sliderColor] == SliderColorEnum.accent ? .effectiveAccent : .white,
                dragging: $dragging,
                lastDragged: $lastDragged,
                onValueChange: onValueChange
            )
            .frame(height: 10, alignment: .center)

            HStack {
                Text(timeString(from: sliderValue))
                Spacer()
                Text(timeString(from: duration))
            }
            .fontWeight(.medium)
            .foregroundColor(
                Defaults[.playerColorTinting]
                    ? Color(nsColor: color).ensureMinimumBrightness(factor: 0.6) : .gray
            )
            .font(.caption)
        }
        .onChange(of: currentDate) {
           guard !dragging, timestampDate.timeIntervalSince(lastDragged) > -1 else { return }
            sliderValue = MusicManager.shared.estimatedPlaybackPosition(at: currentDate)
        }
    }

    func timeString(from seconds: Double) -> String {
        let totalMinutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        } else {
            return String(format: "%d:%02d", minutes, remainingSeconds)
        }
    }
}

struct CustomSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var color: Color = .white
    @Binding var dragging: Bool
    @Binding var lastDragged: Date
    var onValueChange: ((Double) -> Void)?
    var onDragChange: ((Double) -> Void)?

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = CGFloat(dragging ? 9 : 5)
            let rangeSpan = range.upperBound - range.lowerBound

            let progress = rangeSpan == .zero ? 0 : (value - range.lowerBound) / rangeSpan
            let filledTrackWidth = min(max(progress, 0), 1) * width

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(.gray.opacity(0.3))
                    .frame(height: height)

                Rectangle()
                    .fill(color)
                    .frame(width: filledTrackWidth, height: height)
            }
            .cornerRadius(height / 2)
            .frame(height: 10)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        withAnimation {
                            dragging = true
                        }
                        let newValue = range.lowerBound + Double(gesture.location.x / width) * rangeSpan
                        value = min(max(newValue, range.lowerBound), range.upperBound)
                        onDragChange?(value)
                    }
                    .onEnded { _ in
                        onValueChange?(value)
                        dragging = false
                        lastDragged = Date()
                    }
            )
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: dragging)
        }
    }
}
