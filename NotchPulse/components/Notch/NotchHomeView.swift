import Combine
import Defaults
import SwiftUI

// MARK: - Bento Glass Card Wrapper
struct BentoCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.35))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.separator.opacity(0.4), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Music Player Components

struct MusicPlayerView: View {
    @ObservedObject var musicManager = MusicManager.shared
    let albumArtNamespace: Namespace.ID
    var allocatedWidth: CGFloat? = nil

    private var artSize: CGFloat {
        if let width = allocatedWidth {
            // Adaptive album art sizing from 80px to 100px based on allocated column width
            return min(100, max(80, (width - 28) * 0.30))
        }
        return 96
    }

    var body: some View {
        let controlsWidth = allocatedWidth.map { max(130, $0 - artSize - 26) }
        BentoCard {
            HStack(alignment: .center, spacing: 12) {
                AlbumArtView(albumArtNamespace: albumArtNamespace, size: artSize)
                MusicControlsView(allocatedWidth: controlsWidth)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxHeight: .infinity, alignment: .center)
        }
    }
}

struct AlbumArtView: View {
    @ObservedObject var musicManager = MusicManager.shared
    let albumArtNamespace: Namespace.ID
    var size: CGFloat = 96

    private var imageAspectRatio: CGFloat {
        let imgSize = musicManager.albumArt.size
        guard imgSize.width > 0 && imgSize.height > 0 else { return 1.0 }
        return imgSize.width / imgSize.height
    }

    var body: some View {
        albumArtButton
    }

    private var albumArtButton: some View {
        Button {
            musicManager.openMusicApp()
        } label: {
            ZStack(alignment: .bottomTrailing) {
                albumArtImage
                appIconOverlay
            }
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(musicManager.isPlaying ? 1.0 : 0.90)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: musicManager.isPlaying)
    }

    private var albumArtImage: some View {
        Image(nsImage: musicManager.albumArt)
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipped()
            .overlay {
                if !musicManager.isPlaying {
                    RoundedRectangle(
                        cornerRadius: 12,
                        style: .continuous
                    )
                    .fill(Color.black.opacity(0.35))
                    .allowsHitTesting(false)
                }
            }
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 12,
                    style: .continuous
                )
            )
            .overlay(
                RoundedRectangle(
                    cornerRadius: 12,
                    style: .continuous
                )
                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
            )
    }

    @ViewBuilder
    private var appIconOverlay: some View {
        if !musicManager.usingAppIconForArtwork && !musicManager.songTitle.isEmpty {
            let iconSize: CGFloat = max(20, size * 0.26)
            AppIcon(for: musicManager.bundleIdentifier ?? "com.apple.Music")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: iconSize, height: iconSize)
                .offset(x: 4, y: 4)
                .transition(.scale.combined(with: .opacity))
                .zIndex(2)
        }
    }
}

struct MusicControlsView: View {
    @ObservedObject var musicManager = MusicManager.shared
    @EnvironmentObject var vm: NotchPulseViewModel
    @ObservedObject var webcamManager = WebcamManager.shared
    var allocatedWidth: CGFloat? = nil
    @State private var sliderValue: Double = 0
    @State private var dragging: Bool = false
    @State private var lastDragged: Date = .distantPast
    @Default(.musicControlSlots) private var slotConfig
    @Default(.musicControlSlotLimit) private var slotLimit

    private var currentWidth: CGFloat {
        allocatedWidth ?? 200
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            songInfo(width: currentWidth)
            musicSlider
            slotToolbar
        }
        .padding(.leading, 2)
        .buttonStyle(PlainButtonStyle())
        .frame(maxHeight: .infinity, alignment: .center)
    }

    private func songInfo(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(musicManager.songTitle.isEmpty ? (musicManager.isPlayerIdle ? loc("Not Playing") : "") : musicManager.songTitle)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: width, alignment: .leading)
            Text(musicManager.artistName)
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: width, alignment: .leading)
            if Defaults[.enableLyrics] {
                TimelineView(.animation(minimumInterval: 0.4, paused: musicManager.playbackRate <= 0 || musicManager.syncedLyrics.isEmpty || vm.notchState == .closed)) { timeline in
                    let currentElapsed: Double = musicManager.estimatedPlaybackPosition(at: timeline.date)
                    let activeIndex = musicManager.currentLyricIndex(at: currentElapsed)
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
                    Text(line)
                        .font(isPersian ? .custom("Vazirmatn-Regular", size: NSFont.preferredFont(forTextStyle: .subheadline).pointSize) : .system(size: 10.5, weight: .regular, design: .rounded))
                        .foregroundStyle(musicManager.isFetchingLyrics
                            ? .secondary.opacity(0.6)
                            : (activeIndex != nil ? Color.primary : Color.secondary))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: width, alignment: .leading)
                        .id(activeIndex != nil ? "lyric-\(activeIndex!)" : "lyric-\(line)")
                        .opacity(musicManager.isPlaying ? 1 : 0)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 4)),
                            removal: .opacity.combined(with: .offset(y: -4))
                        ))
                        .animation(.easeInOut(duration: 0.28), value: activeIndex)
                }
            }
        }
    }

    private var musicSlider: some View {
        TimelineView(.animation(minimumInterval: 0.5, paused: musicManager.playbackRate <= 0 || dragging || vm.notchState == .closed)) { timeline in
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
            .frame(height: 24)
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
            Button(action: { MusicManager.shared.toggleShuffle() }) {
                Image(systemName: "shuffle")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(musicManager.isShuffled ? Color.effectiveAccent : Color.secondary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        case .previous:
            Button(action: { MusicManager.shared.previousTrack() }) {
                Image(systemName: "backward.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        case .playPause:
            Button(action: {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                    MusicManager.shared.togglePlay()
                }
            }) {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 30, height: 30)
                    Image(systemName: musicManager.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.black)
                        .offset(x: musicManager.isPlaying ? 0 : 1)
                        .contentTransition(.symbolEffect(.replace))
                }
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
        case .next:
            Button(action: { MusicManager.shared.nextTrack() }) {
                Image(systemName: "forward.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        case .repeatMode:
            Button(action: { MusicManager.shared.toggleRepeat() }) {
                Image(systemName: repeatIcon)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(repeatIconColor)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        case .volume:
            VolumeControlView()
        case .favorite:
            FavoriteControlButton()
        case .goBackward:
            Button(action: { MusicManager.shared.skip(seconds: -15) }) {
                Image(systemName: "gobackward.15")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        case .goForward:
            Button(action: { MusicManager.shared.skip(seconds: 15) }) {
                Image(systemName: "goforward.15")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
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
            return .secondary
        case .all, .one:
            return Color.effectiveAccent
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


// MARK: - Volume Control View

struct VolumeControlView: View {
    @ObservedObject var volumeManager = VolumeManager.shared
    @State private var dragging: Bool = false
    @State private var showVolumeSlider: Bool = false
    @State private var lastVolumeUpdateTime: Date = Date.distantPast
    @State private var localVolume: Double? = nil
    private let volumeUpdateThrottle: TimeInterval = 0.05
    
    private var isCurrentlyMuted: Bool {
        return volumeManager.isMuted || volumeManager.rawVolume == 0
    }

    private var currentEffectiveVolume: Double {
        if let local = localVolume {
            return local
        }
        return Double(volumeManager.rawVolume)
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
            HoverButton(
                icon: volumeIcon,
                iconColor: isCurrentlyMuted ? .gray : .white.opacity(0.9),
                scale: .medium
            ) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                    showVolumeSlider.toggle()
                }
            }
            .contextMenu {
                Button(isCurrentlyMuted ? "Bật âm thanh" : "Tắt tiếng") {
                    VolumeManager.shared.toggleMuteAction()
                }
                Button(showVolumeSlider ? "Ẩn thanh âm lượng" : "Hiện thanh âm lượng") {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showVolumeSlider.toggle()
                    }
                }
            }
            .background(
                SliderScrollWheelRepresentable { deltaStep in
                    let step = Float32(deltaStep) * 0.02
                    VolumeManager.shared.adjustRelative(delta: step)
                }
            )

            if showVolumeSlider {
                CustomSlider(
                    value: Binding(
                        get: { currentEffectiveVolume },
                        set: { newValue in
                            localVolume = newValue
                            VolumeManager.shared.setAbsolute(Float32(newValue))
                            MusicManager.shared.setVolume(to: newValue)
                        }
                    ),
                    range: 0.0...1.0,
                    color: .white,
                    dragging: $dragging,
                    lastDragged: .constant(Date.distantPast),
                    onValueChange: { newValue in
                        localVolume = newValue
                        VolumeManager.shared.setAbsolute(Float32(newValue))
                        MusicManager.shared.setVolume(to: newValue)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            if !dragging {
                                localVolume = nil
                            }
                        }
                    },
                    onDragChange: { newValue in
                        localVolume = newValue
                        let now = Date()
                        if now.timeIntervalSince(lastVolumeUpdateTime) > volumeUpdateThrottle {
                            VolumeManager.shared.setAbsolute(Float32(newValue))
                            MusicManager.shared.setVolume(to: newValue)
                            lastVolumeUpdateTime = now
                        }
                    }
                )
                .frame(width: 52, height: 10)
                .background(
                    SliderScrollWheelRepresentable { deltaStep in
                        let step = Float32(deltaStep) * 0.02
                        VolumeManager.shared.adjustRelative(delta: step)
                    }
                )
                .transition(.scale.combined(with: .opacity))
            }
        }
        .clipped()
    }
}

// MARK: - Main View

struct NotchHomeView: View {
    @EnvironmentObject var vm: NotchPulseViewModel
    @ObservedObject var webcamManager = WebcamManager.shared
    @ObservedObject var coordinator = NotchPulseViewCoordinator.shared
    @Default(.notchOpenWidth) private var notchOpenWidth
    let albumArtNamespace: Namespace.ID

    var body: some View {
        let targetOpenWidth = max(minNotchWidth, min(maxNotchWidth, CGFloat(notchOpenWidth)))
        mainContent(totalWidth: targetOpenWidth)
            .frame(width: targetOpenWidth)
            .frame(minHeight: 148, maxHeight: .infinity, alignment: .top)
    }

    private var shouldShowCamera: Bool {
        Defaults[.showMirror] && webcamManager.cameraAvailable && vm.isCameraExpanded
    }

    private var isDynamicIsland: Bool {
        Defaults[.notchStyle] == .dynamicIsland
    }

    @ViewBuilder
    private func mainContent(totalWidth: CGFloat) -> some View {
        let isMediaVisible = Defaults[.enableMediaFeature]
        let isCalendarVisible = Defaults[.showCalendar]
        let isCameraVisible = shouldShowCamera
        let isCalendarFullPage = isCalendarVisible && vm.customOpenHeight != nil

        // Unified horizontal margin across all tabs handled by ContentView
        let horizontalPadding: CGFloat = 0
        let spacing: CGFloat = 16
        let baseWidth = totalWidth > 0 ? totalWidth : notchOpenWidth
        let availableWidth = max(280, baseWidth - 24)

        let (mediaWidth, calendarWidth, cameraWidth): (CGFloat, CGFloat, CGFloat) = {
            // Calendar full page: media and camera are hidden
            if isCalendarFullPage {
                return (0, availableWidth, 0)
            }
            if isMediaVisible && isCalendarVisible && isCameraVisible {
                let camW: CGFloat = 130
                let remainW = max(200, availableWidth - camW - (spacing * 2))
                return (remainW * 0.55, remainW * 0.45, camW)
            } else if isMediaVisible && isCalendarVisible {
                // 55% Media - 45% Calendar distribution!
                let remainW = max(240, availableWidth - spacing)
                return (remainW * 0.55, remainW * 0.45, 0)
            } else if isMediaVisible && isCameraVisible {
                let camW: CGFloat = 160
                let remainW = max(200, availableWidth - camW - spacing)
                return (remainW, 0, camW)
            } else if isCalendarVisible && isCameraVisible {
                let camW: CGFloat = 160
                let remainW = max(200, availableWidth - camW - spacing)
                return (0, remainW, camW)
            } else if isMediaVisible {
                return (availableWidth, 0, 0)
            } else if isCalendarVisible {
                return (0, availableWidth, 0)
            } else if isCameraVisible {
                return (0, 0, availableWidth)
            } else {
                return (0, 0, 0)
            }
        }()

        HStack(alignment: .center, spacing: isCalendarFullPage ? 0 : spacing) {
            if isMediaVisible && !isCalendarFullPage {
                MusicPlayerView(albumArtNamespace: albumArtNamespace, allocatedWidth: mediaWidth)
                    .frame(width: mediaWidth, height: isCalendarFullPage ? 228 : 148, alignment: .center)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }

            if isCalendarVisible {
                BentoCard {
                    CalendarView()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .clipped()
                }
                .frame(width: calendarWidth, height: isCalendarFullPage ? 228 : 148, alignment: .top)
                .environmentObject(vm)
                .compositingGroup()
                .transition(.opacity)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isCalendarFullPage)
            }

            if isCameraVisible && !isCalendarFullPage {
                BentoCard {
                    CameraPreviewView(webcamManager: webcamManager)
                        .frame(width: cameraWidth)
                        .scaledToFit()
                }
                .frame(width: cameraWidth)
                .animation(.interactiveSpring(response: 0.32, dampingFraction: 0.76, blendDuration: 0), value: shouldShowCamera)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .padding(.horizontal, horizontalPadding)
        .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)), removal: .opacity))
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isCalendarFullPage)
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
        VStack(spacing: 2) {
            CustomSlider(
                value: $sliderValue,
                range: 0...max(0.001, duration),
                color: .white,
                dragging: $dragging,
                lastDragged: $lastDragged,
                onValueChange: onValueChange
            )
            .frame(height: 8, alignment: .center)

            HStack {
                Text(timeString(from: sliderValue))
                Spacer()
                Text(timeString(from: duration))
            }
            .fontWeight(.medium)
            .foregroundStyle(.secondary)
            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
        }
        .onChange(of: currentDate) {
           guard !dragging, timestampDate.timeIntervalSince(lastDragged) > -1 else { return }
            sliderValue = MusicManager.shared.estimatedPlaybackPosition(at: currentDate)
        }
        .onChange(of: elapsedTime) {
            guard !dragging else { return }
            sliderValue = MusicManager.shared.estimatedPlaybackPosition()
        }
        .onAppear {
            if !dragging {
                sliderValue = MusicManager.shared.estimatedPlaybackPosition()
            }
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

    @State private var localDragValue: Double? = nil
    @State private var isHovering: Bool = false

    var body: some View {
        GeometryReader { geometry in
            let width = max(1, geometry.size.width)
            let isExpanded = dragging || isHovering
            let height: CGFloat = isExpanded ? 6 : 4
            let rangeSpan = range.upperBound - range.lowerBound

            let currentVal = localDragValue ?? value
            let progress = rangeSpan <= .zero ? 0 : (currentVal - range.lowerBound) / rangeSpan
            let filledTrackWidth = min(max(progress, 0), 1) * width

            ZStack(alignment: .leading) {
                // Background Track
                Capsule()
                    .fill(Color.white.opacity(0.18))
                    .frame(height: height)

                // Filled Track
                Capsule()
                    .fill(color)
                    .frame(width: filledTrackWidth, height: height)

                // Scrubber Thumb
                if isExpanded {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 10, height: 10)
                        .shadow(color: Color.black.opacity(0.35), radius: 2, y: 1)
                        .offset(x: max(0, min(width - 10, filledTrackWidth - 5)))
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(height: 12)
            .contentShape(Rectangle())
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovering = hovering
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if !dragging {
                            withAnimation(.easeInOut(duration: 0.1)) {
                                dragging = true
                            }
                        }
                        let fraction = width > 0 ? (gesture.location.x / width) : 0
                        let computed = range.lowerBound + Double(fraction) * rangeSpan
                        let clamped = min(max(computed, range.lowerBound), range.upperBound)
                        localDragValue = clamped
                        value = clamped
                        onDragChange?(clamped)
                    }
                    .onEnded { gesture in
                        let fraction = width > 0 ? (gesture.location.x / width) : 0
                        let computed = range.lowerBound + Double(fraction) * rangeSpan
                        let finalValue = min(max(computed, range.lowerBound), range.upperBound)
                        localDragValue = nil
                        value = finalValue
                        onValueChange?(finalValue)
                        dragging = false
                        lastDragged = Date()
                    }
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isExpanded)
        }
    }
}
