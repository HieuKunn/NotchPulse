import AppKit
import Cocoa
import SwiftUI

class AudioSpectrum: NSView {
    private var barLayers: [CAShapeLayer] = []
    private var isPlaying: Bool = true
    private var isAnimating: Bool = false

    private let barKeyframes: [[NSNumber]] = [
        [0.35, 0.85, 0.40, 0.95, 0.50, 0.80, 0.35],
        [0.35, 0.55, 1.00, 0.45, 0.90, 0.60, 0.35],
        [0.35, 0.95, 0.35, 0.80, 0.45, 1.00, 0.35],
        [0.35, 0.65, 0.90, 0.40, 0.75, 0.50, 0.35]
    ]
    private let barDurations: [CFTimeInterval] = [0.85, 0.72, 0.92, 0.78]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setupBars()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        setupBars()
    }

    private func setupBars() {
        let barWidth: CGFloat = 2
        let barCount = 4
        let spacing: CGFloat = barWidth
        let totalWidth = CGFloat(barCount) * (barWidth + spacing)
        let totalHeight: CGFloat = 14
        frame.size = CGSize(width: totalWidth, height: totalHeight)

        for i in 0 ..< barCount {
            let xPosition = CGFloat(i) * (barWidth + spacing)
            let barLayer = CAShapeLayer()
            barLayer.frame = CGRect(x: xPosition, y: 0, width: barWidth, height: totalHeight)
            barLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            barLayer.position = CGPoint(x: xPosition + barWidth / 2, y: totalHeight / 2)
            barLayer.fillColor = NSColor.white.cgColor
            barLayer.backgroundColor = NSColor.white.cgColor
            barLayer.allowsGroupOpacity = false
            barLayer.masksToBounds = true
            let path = NSBezierPath(roundedRect: CGRect(x: 0, y: 0, width: barWidth, height: totalHeight),
                                    xRadius: barWidth / 2,
                                    yRadius: barWidth / 2)
            barLayer.path = path.cgPath
            barLayer.transform = CATransform3DMakeScale(1, 0.35, 1)
            barLayers.append(barLayer)
            layer?.addSublayer(barLayer)
        }
    }

    private func startAnimating() {
        guard !isAnimating else { return }
        isAnimating = true

        for (i, barLayer) in barLayers.enumerated() {
            let animation = CAKeyframeAnimation(keyPath: "transform.scale.y")
            animation.values = barKeyframes[i]
            animation.duration = barDurations[i]
            animation.repeatCount = .infinity
            animation.autoreverses = true
            animation.calculationMode = .cubic
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animation.isRemovedOnCompletion = false
            if #available(macOS 13.0, *) {
                animation.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
            }
            barLayer.add(animation, forKey: "spectrumWave")
        }
    }

    private func stopAnimating() {
        guard isAnimating else { return }
        isAnimating = false

        for barLayer in barLayers {
            barLayer.removeAnimation(forKey: "spectrumWave")
            barLayer.transform = CATransform3DMakeScale(1, 0.35, 1)
        }
    }

    func setPlaying(_ playing: Bool) {
        isPlaying = playing
        if isPlaying && window != nil {
            startAnimating()
        } else {
            stopAnimating()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            stopAnimating()
        } else if isPlaying {
            startAnimating()
        }
    }
}

struct AudioSpectrumView: NSViewRepresentable {
    @Binding var isPlaying: Bool
    
    func makeNSView(context: Context) -> AudioSpectrum {
        let spectrum = AudioSpectrum()
        spectrum.setPlaying(isPlaying)
        return spectrum
    }
    
    func updateNSView(_ nsView: AudioSpectrum, context: Context) {
        nsView.setPlaying(isPlaying)
    }

    static func dismantleNSView(_ nsView: AudioSpectrum, coordinator: ()) {
        nsView.setPlaying(false)
    }
}

#Preview {
    AudioSpectrumView(isPlaying: .constant(true))
        .frame(width: 16, height: 20)
        .padding()
}
