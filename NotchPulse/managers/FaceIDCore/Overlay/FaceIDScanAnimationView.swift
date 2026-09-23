//
//  FaceIDScanAnimationView.swift
//  NotchPulse
//
//  Plays a scan animation once and holds its final frame — deliberately not
//  looping, since each video ends on a meaningful resolved state.
//  Exact 1:1 implementation matching Glance.
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
        let initialRect = frameRect.size.width > 0 ? frameRect : NSRect(x: 0, y: 0, width: 140, height: 135)
        super.init(frame: initialRect)
        wantsLayer = true
        let root = CALayer()
        root.masksToBounds = true
        layer = root

        stillImageLayer.contentsGravity = .resizeAspect
        stillImageLayer.masksToBounds = true
        if let still = Self.loadStillFromBundle() {
            stillImageLayer.contents = still
        }
        root.addSublayer(stillImageLayer)

        playerLayer.videoGravity = .resizeAspect
        playerLayer.masksToBounds = true
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
    }

    func updateLayerFrames() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let rect = bounds.size.width > 0 ? bounds : NSRect(x: 0, y: 0, width: 140, height: 135)
        playerLayer.frame = rect
        stillImageLayer.frame = rect
        CATransaction.commit()
    }

    func apply(media: FaceIDScanMedia) {
        updateLayerFrames()
        guard media != currentMedia else { return }
        currentMedia = media
        readyObservation = nil
        fallbackRevealWorkItem?.cancel()

        guard let resource = media.videoResourceName else {
            teardownPlayer()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            playerLayer.isHidden = true
            stillImageLayer.isHidden = false
            CATransaction.commit()
            return
        }

        guard let url = Bundle.main.url(forResource: resource, withExtension: "mp4") else {
            assertionFailure("\(resource).mp4 missing from bundle — check NotchPulse/Resources/")
            return
        }

        teardownPlayer()
        let item = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: item)
        // This can play at the lock screen — never make noise.
        newPlayer.isMuted = true
        // Leaves the player paused on its final frame rather than rewinding.
        newPlayer.actionAtItemEnd = .none

        if media == .scanning {
            loopObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak newPlayer] _ in
                newPlayer?.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
                newPlayer?.play()
            }
        }

        playerLayer.player = newPlayer
        player = newPlayer

        // Waits for `isReadyForDisplay` rather than a fixed delay, which raced the
        // real decode time and produced a black-frame flash.
        let reveal: () -> Void = { [weak self] in
            guard let self else { return }
            // Without disabling implicit actions, toggling `isHidden` cross-fades both
            // layers over CALayer's default duration instead of swapping instantly.
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
        // Safety net only — if isReadyForDisplay never fires for some
        // reason, don't get stuck on the still forever.
        let fallback = DispatchWorkItem { reveal() }
        fallbackRevealWorkItem = fallback
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: fallback)

        newPlayer.seek(to: .zero)
        newPlayer.play()
    }

    private func teardownPlayer() {
        if let observer = loopObserver {
            NotificationCenter.default.removeObserver(observer)
            loopObserver = nil
        }
        readyObservation = nil
        fallbackRevealWorkItem?.cancel()
        player?.pause()
        player = nil
        playerLayer.player = nil
    }

    private static func loadStillFromBundle() -> CGImage? {
        guard let url = Bundle.main.url(forResource: "unlockstatic", withExtension: "png") else { return nil }
        guard let image = NSImage(contentsOf: url) else { return nil }
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}
