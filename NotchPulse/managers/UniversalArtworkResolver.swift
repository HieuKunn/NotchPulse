import AppKit
import Foundation

/// Universal media artwork resolver for all media players, web browsers, and streaming platforms.
/// Automatically resolves official high-resolution album covers or video thumbnails when the host app does not embed artwork data.
public final class UniversalArtworkResolver {
    public static let shared = UniversalArtworkResolver()

    private let memoryCache = NSCache<NSString, NSData>()
    private let fileManager = FileManager.default
    private let diskCacheURL: URL?
    private let urlSession: URLSession

    private var inFlightTasks = [String: Task<Data?, Never>]()
    private let lock = NSLock()

    private init() {
        memoryCache.countLimit = 150
        memoryCache.totalCostLimit = 64 * 1024 * 1024 // 64 MB

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 4.0
        config.timeoutIntervalForResource = 6.0
        config.requestCachePolicy = .returnCacheDataElseLoad
        self.urlSession = URLSession(configuration: config)

        if let cacheBase = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let dir = cacheBase.appendingPathComponent("NotchPulseMediaArtwork", isDirectory: true)
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            self.diskCacheURL = dir
        } else {
            self.diskCacheURL = nil
        }
    }

    // MARK: - Public API

    /// Attempts to retrieve cached artwork data synchronously.
    public func cachedArtwork(title: String, artist: String) -> Data? {
        let key = cacheKey(title: title, artist: artist)
        lock.lock()
        if let mem = memoryCache.object(forKey: key as NSString) {
            lock.unlock()
            return mem as Data
        }
        lock.unlock()

        if let diskURL = diskFileURL(for: key),
           fileManager.fileExists(atPath: diskURL.path),
           let data = try? Data(contentsOf: diskURL) {
            lock.lock()
            memoryCache.setObject(data as NSData, forKey: key as NSString, cost: data.count)
            lock.unlock()
            return data
        }
        return nil
    }

    /// Stores artwork data in cache for a given title/artist pair.
    public func cacheArtworkData(_ data: Data, title: String, artist: String) {
        let key = cacheKey(title: title, artist: artist)
        lock.lock()
        memoryCache.setObject(data as NSData, forKey: key as NSString, cost: data.count)
        lock.unlock()

        if let diskURL = diskFileURL(for: key) {
            DispatchQueue.global(qos: .background).async {
                try? data.write(to: diskURL, options: .atomic)
            }
        }
    }

    /// Asynchronously resolves high-resolution artwork for any media source.
    public func resolveArtwork(
        title: String,
        artist: String,
        album: String? = nil,
        bundleIdentifier: String? = nil,
        completion: @escaping (Data?) -> Void
    ) {
        let cleanTitle = sanitizeTitle(title)
        let cleanArtist = sanitizeArtist(artist)
        guard !cleanTitle.isEmpty else {
            completion(nil)
            return
        }

        let key = cacheKey(title: cleanTitle, artist: cleanArtist)

        if let cached = cachedArtwork(title: cleanTitle, artist: cleanArtist) {
            completion(cached)
            return
        }

        lock.lock()
        if let existingTask = inFlightTasks[key] {
            lock.unlock()
            Task {
                let data = await existingTask.value
                completion(data)
            }
            return
        }

        let task = Task<Data?, Never> { [weak self] () -> Data? in
            guard let self = self else { return nil }

            // 1. Try Apple Music / iTunes Public Search API (Best quality, official 600x600 cover)
            if let itunesData = await self.fetchFromiTunes(title: cleanTitle, artist: cleanArtist) {
                self.cacheArtworkData(itunesData, title: cleanTitle, artist: cleanArtist)
                return itunesData
            }

            // 2. Try YouTube Video Thumbnail (For YouTube, Zen Browser, web videos, lo-fi mixes)
            if let ytData = await self.fetchFromYouTube(title: title, artist: artist) {
                self.cacheArtworkData(ytData, title: cleanTitle, artist: cleanArtist)
                return ytData
            }

            // 3. Try Deezer Public Music Search
            if let deezerData = await self.fetchFromDeezer(title: cleanTitle, artist: cleanArtist) {
                self.cacheArtworkData(deezerData, title: cleanTitle, artist: cleanArtist)
                return deezerData
            }

            return nil
        }

        inFlightTasks[key] = task
        lock.unlock()

        Task {
            let result = await task.value
            self.lock.lock()
            self.inFlightTasks.removeValue(forKey: key)
            self.lock.unlock()
            completion(result)
        }
    }

    // MARK: - Resolvers

    /// Queries Apple's public iTunes Search API for official high-resolution album cover art
    private func fetchFromiTunes(title: String, artist: String) async -> Data? {
        var queryTerms: [String] = []

        if !artist.isEmpty && artist.lowercased() != "unknown artist" && artist.lowercased() != "youtube" {
            queryTerms.append("\(artist) \(title)")
        }
        queryTerms.append(title)

        for term in queryTerms {
            guard let encoded = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let url = URL(string: "https://itunes.apple.com/search?term=\(encoded)&entity=song&limit=1") else {
                continue
            }

            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")

            do {
                let (data, response) = try await urlSession.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { continue }

                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let results = json["results"] as? [[String: Any]],
                   let first = results.first,
                   let artUrlStr = first["artworkUrl100"] as? String {
                    // Upgrade standard 100x100 thumbnail to 600x600 high-res
                    let highResStr = artUrlStr.replacingOccurrences(of: "100x100bb", with: "600x600bb")
                    if let imgUrl = URL(string: highResStr),
                       let imgData = await downloadImage(from: imgUrl) {
                        return imgData
                    }
                }
            } catch {
                continue
            }
        }
        return nil
    }

    /// Queries YouTube search to extract the official high-resolution video thumbnail
    private func fetchFromYouTube(title: String, artist: String) async -> Data? {
        let cleanQuery = "\(title) \(artist)".trimmingCharacters(in: .whitespacesAndNewlines)
        guard let encoded = cleanQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://www.youtube.com/results?search_query=\(encoded)") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let html = String(data: data, encoding: .utf8) else { return nil }

            // Extract videoId from YouTube response
            var videoId: String? = nil
            if let match = html.range(of: "\"videoId\":\"([a-zA-Z0-9_-]{11})\"", options: .regularExpression) {
                let snippet = String(html[match])
                videoId = snippet
                    .replacingOccurrences(of: "\"videoId\":\"", with: "")
                    .replacingOccurrences(of: "\"", with: "")
            }

            if let vId = videoId, !vId.isEmpty {
                let candidateURLs = [
                    "https://i.ytimg.com/vi/\(vId)/maxresdefault.jpg",
                    "https://i.ytimg.com/vi/\(vId)/hq720.jpg",
                    "https://i.ytimg.com/vi/\(vId)/hqdefault.jpg"
                ]

                for thumbUrlStr in candidateURLs {
                    if let thumbURL = URL(string: thumbUrlStr),
                       let imgData = await downloadImage(from: thumbURL) {
                        return imgData
                    }
                }
            }
        } catch {
            return nil
        }
        return nil
    }

    /// Queries Deezer public API for cover art
    private func fetchFromDeezer(title: String, artist: String) async -> Data? {
        let query = !artist.isEmpty ? "\(artist) \(title)" : title
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.deezer.com/search?q=\(encoded)&limit=1") else {
            return nil
        }

        do {
            let (data, response) = try await urlSession.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let results = json["data"] as? [[String: Any]],
               let first = results.first,
               let album = first["album"] as? [String: Any],
               let coverUrlStr = (album["cover_xl"] as? String) ?? (album["cover_big"] as? String) ?? (album["cover_medium"] as? String),
               let coverURL = URL(string: coverUrlStr),
               let imgData = await downloadImage(from: coverURL) {
                return imgData
            }
        } catch {
            return nil
        }
        return nil
    }

    /// Downloads and validates an image from a URL
    private func downloadImage(from url: URL) async -> Data? {
        do {
            var req = URLRequest(url: url)
            req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await urlSession.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, data.count > 1024 else {
                return nil
            }
            // Ensure data is decodable as a valid image
            guard NSImage(data: data) != nil else { return nil }
            return data
        } catch {
            return nil
        }
    }

    // MARK: - Sanitization & Helpers

    private func sanitizeTitle(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // If title is "Artist - Song Title", extract just the song title or clean pair
        let parts = s.components(separatedBy: " - ")
        if parts.count == 2 {
            let left = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let right = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            s = "\(left) \(right)"
        }

        // Remove video-specific suffixes and noise patterns
        let noisePatterns = [
            #"(?i)\|.*$"#,                                 // Anything after a pipe symbol
            #"(?i)\[.*?official.*?\]"#,
            #"(?i)\(.*?(official|music video|mv|audio|video|lyric|lyrics|visualizer|remix).*?\)"#,
            #"(?i)\[.*?(mv|official|lyrics|hd|4k|audio|remix).*?\]"#,
            #"(?i)\b(official music video|official mv|official video|official audio|lyric video|lyrics video|audio visualizer)\b"#,
            #"(?i)\b(4k|hd|full hd|1080p|60fps)\b"#
        ]

        for pat in noisePatterns {
            s = s.replacingOccurrences(of: pat, with: "", options: .regularExpression)
        }

        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sanitizeArtist(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.lowercased() == "unknown artist" || s.lowercased() == "youtube" {
            return ""
        }
        // Remove trailing " - Topic" from YouTube generated channels
        s = s.replacingOccurrences(of: #"(?i)\s*-\s*topic$"#, with: "", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func cacheKey(title: String, artist: String) -> String {
        let raw = "\(title.lowercased())_\(artist.lowercased())"
        let allowed = CharacterSet.alphanumerics
        return raw.unicodeScalars
            .map { allowed.contains($0) ? Character($0) : "_" }
            .reduce(into: "") { $0.append($1) }
    }

    private func diskFileURL(for key: String) -> URL? {
        return diskCacheURL?.appendingPathComponent("\(key).jpg")
    }
}
