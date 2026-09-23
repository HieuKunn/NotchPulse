//
//  FaceIDScanAnimationView.swift
//  NotchPulse
//
//  Plays a scan animation once and holds its final frame — looping when scanning.
//  Uses SwiftUI native static image rendering for instant 0ms display on drop-down,
//  with AVPlayerLayer video playback overlaid when media animation is active.
//

import SwiftUI
import AVFoundation
import AppKit

/// Which media the overlay is showing. `.idle` is a still image (unlockstatic)
/// so the transition into a playing video is seamless with zero black flashes.
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

/// Thread-safe provider ensuring unlockstatic image is always loaded and cached
/// from any available format (Asset catalog, PNG, TIFF, PDF, JPEG, video frame, or SF Symbol).
@MainActor
final class FaceIDStaticImageProvider {
    static let shared = FaceIDStaticImageProvider()

    let image: NSImage?

    private init() {
        // 1. Asset catalog named "unlockstatic"
        if let img = NSImage(named: "unlockstatic"), img.isValid && img.size.width > 0 {
            self.image = img
            return
        }

        // 2. Direct bundle resources across common image formats
        let extensions = ["png", "tiff", "tif", "pdf", "jpg", "jpeg"]
        for ext in extensions {
            if let url = Bundle.main.url(forResource: "unlockstatic", withExtension: ext),
               let img = NSImage(contentsOf: url), img.isValid && img.size.width > 0 {
                self.image = img
                return
            }
        }

        // 3. Extract first frame from bundled animation videos
        for videoName in ["idleanimation", "unlockanimation"] {
            if let url = Bundle.main.url(forResource: videoName, withExtension: "mp4") {
                let asset = AVURLAsset(url: url)
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                if let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil) {
                    let img = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                    self.image = img
                    return
                }
            }
        }

        // 4. Built-in system SF Symbol fallback
        if let symbol = NSImage(systemSymbolName: "faceid", accessibilityDescription: "Face ID") {
            self.image = symbol
            return
        }

        self.image = nil
    }
}

/// Native SwiftUI static image view guaranteed to paint at frame 0 (0ms)
/// without waiting for CoreAnimation layer compositing or video player init.
struct FaceIDStaticImageView: View {
    var body: some View {
        if let nsImage = FaceIDStaticImageProvider.shared.image {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "faceid")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.white)
        }
    }
}

/// SwiftUI View presenting Face ID media: static face at 0ms, followed by
/// smooth cross-fade to video playback (idle looping, success, or failure).
struct FaceIDScanAnimationView: View {
    let media: FaceIDScanMedia

    @State private var isVideoReady = false

    var body: some View {
        ZStack {
            // Layer 1: Always-present static face image at 0ms
            FaceIDStaticImageView()
                .opacity((isVideoReady && media.videoResourceName != nil) ? 0 : 1)
                .animation(.easeInOut(duration: 0.15), value: isVideoReady)

            // Layer 2: Video playback layer when resource is available
            if let resource = media.videoResourceName {
                FaceIDVideoPlayerRepresentable(
                    resourceName: resource,
                    isScanning: media == .scanning,
                    onReady: {
                        isVideoReady = true
                    }
                )
                .opacity(isVideoReady ? 1 : 0)
                .animation(.easeInOut(duration: 0.15), value: isVideoReady)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: media) { _, newMedia in
            if newMedia.videoResourceName == nil {
                isVideoReady = false
            }
        }
    }
}

/// NSViewRepresentable wrapping AVPlayerLayer for seamless video display
struct FaceIDVideoPlayerRepresentable: NSViewRepresentable {
    let resourceName: String
    let isScanning: Bool
    let onReady: () -> Void

    func makeNSView(context: Context) -> FaceIDVideoPlayerHostView {
        let view = FaceIDVideoPlayerHostView()
        view.onReady = onReady
        view.loadVideo(named: resourceName, isScanning: isScanning)
        return view
    }

    func updateNSView(_ nsView: FaceIDVideoPlayerHostView, context: Context) {
        nsView.onReady = onReady
        nsView.loadVideo(named: resourceName, isScanning: isScanning)
        nsView.updateLayerFrames()
    }
}

final class FaceIDVideoPlayerHostView: NSView {
    var onReady: (() -> Void)?
    private var player: AVPlayer?
    private let playerLayer = AVPlayerLayer()
    private var currentResourceName: String?
    private var readyObservation: NSKeyValueObservation?
    private var loopObserver: NSObjectProtocol?
    private var fallbackItem: DispatchWorkItem?

    override init(frame frameRect: NSRect) {
        let initialRect = frameRect.size.width > 0 ? frameRect : NSRect(x: 0, y: 0, width: 140, height: 135)
        super.init(frame: initialRect)
        wantsLayer = true
        let root = CALayer()
        root.masksToBounds = true
        layer = root

        playerLayer.videoGravity = .resizeAspect
        playerLayer.masksToBounds = true
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

    func updateLayerFrames() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }

    func loadVideo(named name: String, isScanning: Bool) {
        updateLayerFrames()
        guard name != currentResourceName else { return }
        currentResourceName = name
        teardownPlayer()

        guard let url = Bundle.main.url(forResource: name, withExtension: "mp4") else {
            return
        }

        let item = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.isMuted = true
        newPlayer.actionAtItemEnd = .none

        if isScanning {
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

        let notifyReady: () -> Void = { [weak self] in
            DispatchQueue.main.async {
                self?.fallbackItem?.cancel()
                self?.onReady?()
                self?.readyObservation = nil
            }
        }

        readyObservation = playerLayer.observe(\.isReadyForDisplay, options: [.new]) { _, change in
            guard change.newValue == true else { return }
            notifyReady()
        }

        let fallback = DispatchWorkItem { notifyReady() }
        fallbackItem = fallback
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: fallback)

        newPlayer.seek(to: .zero)
        newPlayer.play()
    }

    private func teardownPlayer() {
        if let observer = loopObserver {
            NotificationCenter.default.removeObserver(observer)
            loopObserver = nil
        }
        readyObservation = nil
        fallbackItem?.cancel()
        player?.pause()
        player = nil
        playerLayer.player = nil
    }

    deinit {
        teardownPlayer()
    }
}
