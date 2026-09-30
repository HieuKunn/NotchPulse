//
//  FaceIDScanAnimationView.swift
//  NotchPulse
//
//  Plays a scan animation once and holds its final frame — deliberately not
//  looping, since each video ends on a meaningful resolved state.
//

import SwiftUI
import AVFoundation
import AppKit

/// Which media the overlay is showing. `.idle` is a still image (the first
/// frame of the success video or unlockstatic asset) so the transition into a playing video is
/// seamless.
enum FaceIDScanMedia: Equatable {
    case idle
    case success
    case failure

    var videoResourceName: String? {
        switch self {
        case .idle: return nil
        case .success: return "unlockanimation"
        case .failure: return "unsuccessfulunlockanimation"
        }
    }
}

struct FaceIDScanAnimationView: View {
    let media: FaceIDScanMedia

    var body: some View {
        ZStack {
            // 1. Static asset: Guaranteed to display instantly upon waking/opening
            FaceIDStaticAssetView()
                .opacity(media == .idle ? 1.0 : 0.0)

            // 2. Dynamic Video Player: Plays outcome video on success / failure
            if media != .idle {
                FaceIDScanVideoPlayerView(media: media)
                    .transition(.opacity)
            }
        }
    }
}

// MARK: - Instant Static Asset View
struct FaceIDStaticAssetView: View {
    var body: some View {
        if let image = Self.loadStaticImage() {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
        } else if let cgFrame = FaceIDScanAnimationHostView.loadStillCGImage() {
            Image(decorative: cgFrame, scale: 1.0)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "faceid")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.white)
        }
    }

    private static func loadStaticImage() -> NSImage? {
        if let image = NSImage(named: "unlockstatic") {
            return image
        }
        if let url = Bundle.main.url(forResource: "unlockstatic", withExtension: "pdf"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        if let url = Bundle.main.url(forResource: "unlockstatic", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        if let url = Bundle.main.url(forResource: "unlockstatic", withExtension: "tiff"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return nil
    }
}

// MARK: - Representable Video Player
struct FaceIDScanVideoPlayerView: NSViewRepresentable {
    let media: FaceIDScanMedia

    func makeNSView(context: Context) -> FaceIDScanAnimationHostView {
        let view = FaceIDScanAnimationHostView()
        view.apply(media: media)
        return view
    }

    func updateNSView(_ nsView: FaceIDScanAnimationHostView, context: Context) {
        nsView.apply(media: media)
    }
}

final class FaceIDScanAnimationHostView: NSView {
    private static var firstFrameCache: [String: CGImage] = [:]

    static func firstFrame(for resourceName: String) -> CGImage? {
        if let cached = firstFrameCache[resourceName] { return cached }
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "mp4") else { return nil }
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        if let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil) {
            firstFrameCache[resourceName] = cgImage
            return cgImage
        }
        return nil
    }

    private var player: AVPlayer?
    private let playerLayer = AVPlayerLayer()
    private let stillImageLayer = CALayer()
    private var currentMedia: FaceIDScanMedia?
    private var readyObservation: NSKeyValueObservation?
    private var fallbackRevealWorkItem: DispatchWorkItem?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        let root = CALayer()
        root.masksToBounds = true
        layer = root

        stillImageLayer.contentsGravity = .resizeAspect
        stillImageLayer.masksToBounds = true
        if let still = Self.loadStillCGImage() {
            stillImageLayer.contents = still
        }
        stillImageLayer.isHidden = false
        root.addSublayer(stillImageLayer)

        playerLayer.videoGravity = .resizeAspect
        playerLayer.masksToBounds = true
        playerLayer.isHidden = true
        root.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        updateLayerFrames()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateLayerFrames()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateLayerFrames()
    }

    private func updateLayerFrames() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        stillImageLayer.frame = bounds
        CATransaction.commit()
    }

    func apply(media: FaceIDScanMedia) {
        guard media != currentMedia else { return }
        currentMedia = media
        readyObservation = nil
        fallbackRevealWorkItem?.cancel()

        guard let resource = media.videoResourceName else {
            teardownPlayer()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            if let still = Self.loadStillCGImage() {
                stillImageLayer.contents = still
            }
            playerLayer.isHidden = true
            stillImageLayer.isHidden = false
            CATransaction.commit()
            return
        }

        if let frame = Self.firstFrame(for: resource) ?? Self.loadStillCGImage() {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            stillImageLayer.contents = frame
            stillImageLayer.isHidden = false
            playerLayer.isHidden = true
            CATransaction.commit()
        }

        guard let url = Bundle.main.url(forResource: resource, withExtension: "mp4") else {
            assertionFailure("\(resource).mp4 missing from bundle — check NotchPulse/Resources/")
            return
        }

        teardownPlayer()
        let newPlayer = AVPlayer(url: url)
        // This can play at the lock screen — never make noise.
        newPlayer.isMuted = true
        // Leaves the player paused on its final frame rather than rewinding.
        newPlayer.actionAtItemEnd = .none

        playerLayer.player = newPlayer
        player = newPlayer

        // Waits for `isReadyForDisplay` rather than a fixed delay, which raced the
        // real decode time and produced a black-frame flash.
        let reveal: () -> Void = { [weak self] in
            guard let self else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.playerLayer.isHidden = false
            self.stillImageLayer.isHidden = true
            CATransaction.commit()
        }
        readyObservation = playerLayer.observe(\.isReadyForDisplay, options: [.new]) { [weak self] _, change in
            guard change.newValue == true else { return }
            DispatchQueue.main.async {
                self?.fallbackRevealWorkItem?.cancel()
                reveal()
                self?.readyObservation = nil
            }
        }
        let fallback = DispatchWorkItem { reveal() }
        fallbackRevealWorkItem = fallback
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: fallback)

        newPlayer.seek(to: .zero)
        newPlayer.play()
    }

    private func teardownPlayer() {
        readyObservation = nil
        fallbackRevealWorkItem?.cancel()
        player?.pause()
        player = nil
        playerLayer.player = nil
    }

    static func loadStillCGImage() -> CGImage? {
        if let url = Bundle.main.url(forResource: "unlockstatic", withExtension: "pdf") as CFURL?,
           let source = CGImageSourceCreateWithURL(url, nil),
           let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            return cgImage
        }
        if let url = Bundle.main.url(forResource: "unlockstatic", withExtension: "png") as CFURL?,
           let source = CGImageSourceCreateWithURL(url, nil),
           let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            return cgImage
        }
        if let image = NSImage(named: "unlockstatic") {
            var rect = CGRect(origin: .zero, size: image.size)
            if let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) {
                return cgImage
            }
        }
        if let frame = firstFrame(for: "idleanimation") ?? firstFrame(for: "unlockanimation") {
            return frame
        }
        return nil
    }
}
