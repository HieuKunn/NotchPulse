//
//  ThumbnailService.swift
//  NotchPulse
//
//  Created by Alexander on 2025-10-07.
//

import Foundation
import AppKit
import QuickLookThumbnailing
import UniformTypeIdentifiers

actor ThumbnailService {
    static let shared = ThumbnailService()

    private let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 30
        cache.totalCostLimit = 20 * 1024 * 1024 // 20 MB
        return cache
    }()
    private var pendingRequests: [String: Task<NSImage?, Never>] = [:]
    private let thumbnailGenerator = QLThumbnailGenerator.shared

    private init() {}
    
    func thumbnail(for url: URL, size: CGSize) async -> NSImage? {
        let cacheKey = "\(url.path)_\(size.width)x\(size.height)"
        
        if let cached = cache.object(forKey: cacheKey as NSString) {
            return cached
        }
        
        if let pending = pendingRequests[cacheKey] {
            return await pending.value
        }
        
        let task = Task<NSImage?, Never> {
            let thumbnail = await generateQuickLookThumbnail(for: url, size: size)
            if let thumbnail = thumbnail {
                let cost = Int(size.width * size.height * 4)
                cache.setObject(thumbnail, forKey: cacheKey as NSString, cost: cost)
            }
            pendingRequests[cacheKey] = nil
            return thumbnail
        }
        
        pendingRequests[cacheKey] = task
        return await task.value
    }
    
    func clearCache() {
        cache.removeAllObjects()
    }
    
    func clearCache(for url: URL) {
        cache.removeAllObjects()
    }
    
    // MARK: - Private Methods
    
    private func generateQuickLookThumbnail(for url: URL, size: CGSize) async -> NSImage? {
        let scale = await MainActor.run { NSScreen.main?.backingScaleFactor ?? 2.0 }
        
        return await url.accessSecurityScopedResource { scopedURL in
            let request = QLThumbnailGenerator.Request(
                fileAt: scopedURL,
                size: size,
                scale: scale,
                representationTypes: .all
            )
            request.iconMode = true

            return await withCheckedContinuation { (continuation: CheckedContinuation<NSImage?, Never>) in
                thumbnailGenerator.generateBestRepresentation(for: request) { representation, error in
                    if let rep = representation {
                        continuation.resume(returning: rep.nsImage)
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            }
        }
    }
}

// MARK: - Extensions

extension QLThumbnailRepresentation {
    var nsImage: NSImage {
        return NSImage(cgImage: self.cgImage, size: self.cgImage.size)
    }
}

extension CGImage {
    var size: NSSize {
        return NSSize(width: self.width, height: self.height)
    }
}
