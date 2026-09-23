//
//  ScanAnimationView.swift
//  NotchPulse
//
//  Plays the authentic Face ID scan & green checkmark unlock animation from video assets.
//

import AVFoundation
import AppKit
import SwiftUI

enum ScanMedia: Equatable {
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

struct ScanAnimationView: NSViewRepresentable {
    let media: ScanMedia

    func makeNSView(context: Context) -> ScanAnimationHostView {
        let view = ScanAnimationHostView()
        view.apply(media: media)
        return view
    }

    func updateNSView(_ nsView: ScanAnimationHostView, context: Context) {
        nsView.apply(media: media)
        nsView.updateLayerFrames()
    }
}

final class ScanAnimationHostView: NSView {
    private static var firstFrameCache: [String: CGImage] = [:]

    private static func firstFrame(for resourceName: String) -> CGImage? {
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
    private var currentMedia: ScanMedia?
    private var readyObservation: NSKeyValueObservation?
    private var fallbackRevealWorkItem: DispatchWorkItem?
    private var loopObserver: NSObjectProtocol?

    override init(frame frameRect: NSRect) {
        let defaultFrame = frameRect.size.width > 0 ? frameRect : NSRect(x: 0, y: 0, width: 140, height: 135)
        super.init(frame: defaultFrame)
        wantsLayer = true
        let rootLayer = CALayer()
        rootLayer.masksToBounds = true
        layer = rootLayer

        stillImageLayer.contentsGravity = .resizeAspect
        stillImageLayer.masksToBounds = true
        stillImageLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        if let initialFrame = Self.firstFrame(for: "idleanimation") ?? Self.loadStillFromBundle()?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            stillImageLayer.contents = initialFrame
        }
        rootLayer.addSublayer(stillImageLayer)

        playerLayer.videoGravity = .resizeAspect
        playerLayer.masksToBounds = true
        playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        playerLayer.isHidden = true
        rootLayer.addSublayer(playerLayer)

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
        let rect = bounds.size.width > 0 ? bounds : NSRect(x: 0, y: 0, width: 140, height: 135)
        playerLayer.frame = rect
        stillImageLayer.frame = rect
        CATransaction.commit()
    }

    func apply(media: ScanMedia) {
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
            teardownPlayer()
            playerLayer.isHidden = true
            stillImageLayer.isHidden = false
            return
        }

        if let frame = Self.firstFrame(for: resource) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            stillImageLayer.contents = frame
            stillImageLayer.isHidden = false
            CATransaction.commit()
        }

        guard let url = Bundle.main.url(forResource: resource, withExtension: "mp4") else {
            return
        }

        teardownPlayer()
        let newPlayer = AVPlayer(url: url)
        newPlayer.isMuted = true
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

        let revealPlayerLayer: () -> Void = { [weak self] in
            guard let self = self else { return }
            self.readyObservation = nil
            self.fallbackRevealWorkItem?.cancel()
            self.fallbackRevealWorkItem = nil
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.playerLayer.isHidden = false
            self.stillImageLayer.isHidden = true
            CATransaction.commit()
        }

        if playerLayer.isReadyForDisplay {
            revealPlayerLayer()
        } else {
            readyObservation = playerLayer.observe(\.isReadyForDisplay, options: [.new]) { [weak self] _, change in
                if change.newValue == true {
                    DispatchQueue.main.async {
                        revealPlayerLayer()
                    }
                }
            }

            let workItem = DispatchWorkItem { [weak self] in
                revealPlayerLayer()
            }
            fallbackRevealWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
        }

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

    private static func loadStillFromBundle() -> NSImage? {
        guard let url = Bundle.main.url(forResource: "unlockstatic", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }
}
