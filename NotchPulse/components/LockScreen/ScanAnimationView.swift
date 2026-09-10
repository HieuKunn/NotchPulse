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

struct ScanAnimationView: NSViewRepresentable {
    let media: ScanMedia

    func makeNSView(context: Context) -> ScanAnimationHostView {
        let view = ScanAnimationHostView()
        view.apply(media: media)
        return view
    }

    func updateNSView(_ nsView: ScanAnimationHostView, context: Context) {
        nsView.apply(media: media)
    }
}

final class ScanAnimationHostView: NSView {
    private var player: AVPlayer?
    private let playerLayer = AVPlayerLayer()
    private let stillImageLayer = CALayer()
    private var currentMedia: ScanMedia?
    private var readyObservation: NSKeyValueObservation?
    private var fallbackRevealWorkItem: DispatchWorkItem?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        let rootLayer = CALayer()
        rootLayer.masksToBounds = true
        layer = rootLayer

        stillImageLayer.contentsGravity = .resizeAspect
        stillImageLayer.masksToBounds = true
        if let still = Self.loadStillFromBundle() {
            stillImageLayer.contents = still
        }
        layer?.addSublayer(stillImageLayer)

        playerLayer.videoGravity = .resizeAspect
        playerLayer.masksToBounds = true
        playerLayer.isHidden = true
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        stillImageLayer.frame = bounds
        CATransaction.commit()
    }

    func apply(media: ScanMedia) {
        guard media != currentMedia else { return }
        currentMedia = media
        readyObservation = nil
        fallbackRevealWorkItem?.cancel()

        guard let resource = media.videoResourceName else {
            teardownPlayer()
            playerLayer.isHidden = true
            stillImageLayer.isHidden = false
            return
        }

        guard let url = Bundle.main.url(forResource: resource, withExtension: "mp4") else {
            return
        }

        teardownPlayer()
        let newPlayer = AVPlayer(url: url)
        newPlayer.isMuted = true
        newPlayer.actionAtItemEnd = .none

        playerLayer.player = newPlayer
        player = newPlayer

        let reveal: () -> Void = { [weak self] in
            guard let self = self else { return }
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: fallback)

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

    private static func loadStillFromBundle() -> NSImage? {
        guard let url = Bundle.main.url(forResource: "unlockstatic", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }
}
