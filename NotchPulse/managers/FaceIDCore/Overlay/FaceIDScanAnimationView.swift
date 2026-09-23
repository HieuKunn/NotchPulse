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
/// frame of the success video) so the transition into a playing video is
/// seamless.
enum FaceIDScanMedia: Equatable {
    case idle
    case scanning
    case success
    case failure

    var videoResourceName: String? {
        switch self {
        case .idle: return nil
        case .scanning: return "idleanimation"
        case .success: return "unlockanimation"
        case .failure: return "unsuccessfulunlockanimation"
        }
    }
}

struct FaceIDScanAnimationView: NSViewRepresentable {
    let media: FaceIDScanMedia

    func makeNSView(context: Context) -> FaceIDScanAnimationHostView {
        let view = FaceIDScanAnimationHostView()
        view.apply(media: media)
        return view
    }

    func updateNSView(_ nsView: FaceIDScanAnimationHostView, context: Context) {
        nsView.apply(media: media)
        nsView.updateLayerFrames()
    }
}

final class FaceIDScanAnimationHostView: NSView {
    private var player: AVPlayer?
    private let playerLayer = AVPlayerLayer()
    private let stillImageLayer = CALayer()
    private var currentMedia: FaceIDScanMedia?
    private var readyObservation: NSKeyValueObservation?
    private var fallbackRevealWorkItem: DispatchWorkItem?
    private var loopObserver: NSObjectProtocol?

    override init(frame frameRect: NSRect) {
        let defaultFrame = frameRect.size.width > 0 ? frameRect : NSRect(x: 0, y: 0, width: 140, height: 135)
        super.init(frame: defaultFrame)
        wantsLayer = true
        let root = CALayer()
        root.masksToBounds = true
        layer = root

        stillImageLayer.contentsGravity = .resizeAspect
        stillImageLayer.masksToBounds = true
        stillImageLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        if let still = Self.loadStillFromBundle() {
            stillImageLayer.contents = still
        }
        root.addSublayer(stillImageLayer)

        playerLayer.videoGravity = .resizeAspect
        playerLayer.masksToBounds = true
        playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        playerLayer.isHidden = true
        root.addSublayer(playerLayer)

        updateLayerFrames()
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

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        updateLayerFrames()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateLayerFrames()
        if window != nil, let player = player, currentMedia == .scanning, player.timeControlStatus != .playing {
            player.play()
        }
    }

    func updateLayerFrames() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let rect = bounds.size.width > 0 ? bounds : NSRect(x: 0, y: 0, width: 155, height: 135)
        playerLayer.frame = rect
        stillImageLayer.frame = rect
        CATransaction.commit()
    }

    func apply(media: FaceIDScanMedia) {
        updateLayerFrames()
        if media == currentMedia {
            if media == .scanning, let player = player, player.timeControlStatus != .playing {
                player.play()
            }
            return
        }
        currentMedia = media
        readyObservation = nil
        fallbackRevealWorkItem?.cancel()

        guard let resource = media.videoResourceName else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            stillImageLayer.isHidden = false
            playerLayer.isHidden = true
            CATransaction.commit()
            teardownPlayer()
            return
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

        if media == .scanning {
            loopObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: newPlayer.currentItem,
                queue: .main
            ) { [weak newPlayer] _ in
                newPlayer?.seek(to: .zero)
                newPlayer?.play()
            }
        }

        playerLayer.player = newPlayer
        player = newPlayer

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.isHidden = false
        stillImageLayer.isHidden = true
        CATransaction.commit()

        newPlayer.seek(to: .zero)
        newPlayer.play()
    }

    private func teardownPlayer() {
        readyObservation = nil
        fallbackRevealWorkItem?.cancel()
        if let observer = loopObserver {
            NotificationCenter.default.removeObserver(observer)
            loopObserver = nil
        }
        player?.pause()
        player = nil
        playerLayer.player = nil
    }

    /// The asset lives in Resources/ rather than an asset catalog, so
    /// `NSImage(named:)` won't find it — load by URL instead.
    private static func loadStillFromBundle() -> NSImage? {
        guard let url = Bundle.main.url(forResource: "unlockstatic", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }
}
