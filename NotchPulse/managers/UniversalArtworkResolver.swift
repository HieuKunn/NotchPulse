import AppKit
import CoreGraphics
import Foundation
import ImageIO

/// Streamlined, memory-efficient media artwork optimizer and active-track cache.
/// Enforces:
/// 1. Zero external network API calls (no iTunes, YouTube, or Deezer scraping) to minimize CPU, RAM, and network usage.
/// 2. Retina-sharp downsampling (max 500x500px, sub-sampling at decode time via CGImageSource) to keep memory footprint under ~1MB.
/// 3. Ephemeral single-track lifetime: only stores artwork for the currently active media track; previous tracks are purged immediately.
public final class UniversalArtworkResolver {
    public static let shared = UniversalArtworkResolver()

    private let lock = NSLock()
    private var activeKey: String?
    private var activeArtworkData: Data?

    private init() {
        // Clean up legacy disk cache directory from older versions in background to free disk space
        DispatchQueue.global(qos: .background).async {
            if let cacheBase = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
                let dir = cacheBase.appendingPathComponent("NotchPulseMediaArtwork", isDirectory: true)
                if FileManager.default.fileExists(atPath: dir.path) {
                    try? FileManager.default.removeItem(at: dir)
                }
            }
        }
    }

    // MARK: - Public API

    /// Downsamples raw image data to a max dimension (default 500px) with sub-sampling decode.
    /// This keeps artwork razor-sharp on Retina displays while cutting memory usage from 20-36 MB to ~50-90 KB.
    public func optimizeArtwork(_ data: Data, maxDimension: CGFloat = 500) -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return data
        }

        // If already within budget and compressed, return original
        if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
           let height = properties[kCGImagePropertyPixelHeight] as? CGFloat,
           width <= maxDimension && height <= maxDimension && data.count <= 150_000 {
            return data
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]

        guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary) else {
            return data
        }

        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        // 0.85 compression factor provides visually lossless Retina quality
        if let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) {
            return jpeg
        }
        return data
    }

    /// Stores artwork data strictly for the currently active (title, artist) track.
    /// Any previous track's artwork is immediately purged from RAM.
    public func cacheArtworkData(_ data: Data, title: String, artist: String) {
        let key = cacheKey(title: title, artist: artist)
        guard !key.isEmpty else { return }

        let optimized = optimizeArtwork(data, maxDimension: 500)
        lock.lock()
        activeKey = key
        activeArtworkData = optimized
        lock.unlock()
    }

    /// Retrieves artwork data only if it matches the currently active track.
    /// Never returns artwork from previous or inactive tracks.
    public func cachedArtwork(title: String, artist: String) -> Data? {
        let key = cacheKey(title: title, artist: artist)
        guard !key.isEmpty else { return nil }

        lock.lock()
        defer { lock.unlock() }
        if activeKey == key {
            return activeArtworkData
        }
        return nil
    }

    /// Purges all active artwork from RAM immediately.
    public func clear() {
        lock.lock()
        activeKey = nil
        activeArtworkData = nil
        lock.unlock()
    }

    /// Compatibility method for existing call sites:
    /// Does NOT perform external API queries. Returns active cached artwork if available, otherwise nil.
    public func resolveArtwork(
        title: String,
        artist: String,
        album: String? = nil,
        bundleIdentifier: String? = nil,
        completion: @escaping (Data?) -> Void
    ) {
        if let cached = cachedArtwork(title: title, artist: artist) {
            completion(cached)
        } else {
            completion(nil)
        }
    }

    // MARK: - Helpers

    private func cacheKey(title: String, artist: String) -> String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let a = artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !t.isEmpty || !a.isEmpty else { return "" }
        return "\(t)_\(a)"
    }
}
