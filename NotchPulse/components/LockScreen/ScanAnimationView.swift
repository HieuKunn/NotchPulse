//
//  ScanAnimationView.swift
//  NotchPulse
//
//  Plays the authentic Face ID scan & green checkmark unlock animation from video assets.
//

import AVFoundation
import AppKit
import SwiftUI
import ImageIO

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

    static func prewarm() {
        Task.detached(priority: .userInitiated) {
            _ = firstFrame(for: "idleanimation")
            _ = firstFrame(for: "unlockanimation")
            _ = firstFrame(for: "unsuccessfulunlockanimation")
            _ = loadStaticCGImage()
        }
    }

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

        // ARCHITECTURAL RULE: Layer ordering is critical.
        // playerLayer is added first (bottom layer, zPosition = 0).
        // stillImageLayer is added last (top-most layer, zPosition = 100).
        // This ensures the static face image renders instantly from frame 0 with zero black screen/flicker.
        playerLayer.videoGravity = .resizeAspect
        playerLayer.masksToBounds = true
        playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        playerLayer.isHidden = true
        playerLayer.zPosition = 0
        rootLayer.addSublayer(playerLayer)

        stillImageLayer.contentsGravity = .resizeAspect
        stillImageLayer.masksToBounds = true
        stillImageLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        if let initialFrame = Self.loadStaticCGImage() ?? Self.firstFrame(for: "idleanimation") {
            stillImageLayer.contents = initialFrame
        }
        stillImageLayer.isHidden = false
        stillImageLayer.zPosition = 100
        rootLayer.addSublayer(stillImageLayer)

        updateLayerFrames()
        Self.prewarm()
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
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            if let staticImg = Self.loadStaticCGImage() {
                stillImageLayer.contents = staticImg
            }
            playerLayer.isHidden = true
            playerLayer.zPosition = 0
            stillImageLayer.isHidden = false
            stillImageLayer.zPosition = 100
            CATransaction.commit()
            return
        }

        if let frame = Self.firstFrame(for: resource) ?? Self.loadStaticCGImage() {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            stillImageLayer.contents = frame
            stillImageLayer.isHidden = false
            stillImageLayer.zPosition = 100
            playerLayer.isHidden = true
            playerLayer.zPosition = 0
            CATransaction.commit()
        }

        guard let url = Bundle.main.url(forResource: resource, withExtension: "mp4") else {
            return
        }

        teardownPlayer()
        let item = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.isMuted = true
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

        let reveal: () -> Void = { [weak self] in
            guard let self else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.playerLayer.zPosition = 100
            self.playerLayer.isHidden = false
            self.stillImageLayer.isHidden = true
            self.stillImageLayer.zPosition = 0
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: fallback)

        newPlayer.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
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
        playerLayer.isHidden = true
        playerLayer.zPosition = 0
    }

    private static func loadStaticCGImage() -> CGImage? {
        let extensions = ["png", "tiff", "pdf", "jpg"]
        for ext in extensions {
            if let url = Bundle.main.url(forResource: "unlockstatic", withExtension: ext) as CFURL?,
               let source = CGImageSourceCreateWithURL(url, nil),
               let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                return cgImage
            }
        }
        
        if let image = NSImage(named: "unlockstatic"),
           let tiffData = image.tiffRepresentation,
           let source = CGImageSourceCreateWithData(tiffData as CFData, nil),
           let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            return cgImage
        }
        
        if let frame = firstFrame(for: "idleanimation") ?? firstFrame(for: "unlockanimation") {
            return frame
        }

        return nil
    }
}
