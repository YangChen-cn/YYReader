import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct MangaImagePayload: Sendable {
    let data: Data
    let aspectRatio: Double
}

/// Disk-backed original images; decoding and thumbnail creation stay off the UI actor.
/// One request runs at a time, including explicit offline downloads.
actor MangaImageCache {
    static let shared = MangaImageCache()
    private let directory: URL
    private let session: URLSession
    private let limiter = HostRateLimiter(defaultMinimumDelay: .milliseconds(180))
    private var tail: Task<Data, any Error>?
    private var retryAfter: Date?

    init(directory: URL? = nil, session: URLSession = .shared) {
        self.directory = directory ?? URL.applicationSupportDirectory
            .appending(path: "YYReader/MangaImages", directoryHint: .isDirectory)
        self.session = session
    }

    func image(at url: URL, referer: URL) async throws -> MangaImagePayload {
        let data = try await original(at: url, referer: referer)
        try Task.checkCancellation()
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 2400,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else {
            try remove([url])
            throw HTMLLoadError.invalidResponse
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)
        else { throw HTMLLoadError.invalidResponse }
        CGImageDestinationAddImage(destination, thumbnail, nil)
        guard CGImageDestinationFinalize(destination) else { throw HTMLLoadError.invalidResponse }
        return MangaImagePayload(data: output as Data, aspectRatio: Double(thumbnail.width) / Double(thumbnail.height))
    }

    func original(at url: URL, referer: URL) async throws -> Data {
        try Task.checkCancellation()
        if let cached = try cachedData(at: url) { return cached }
        let previous = tail
        let task = Task {
            // A failed/cancelled predecessor must not poison subsequent image requests.
            if let previous { _ = await previous.result }
            try Task.checkCancellation()
            return try await self.fetch(url, referer: referer)
        }
        tail = task
        return try await withTaskCancellationHandler {
            let data = try await task.value
            try Task.checkCancellation()
            return data
        } onCancel: { task.cancel() }
    }

    func containsAll(_ urls: [URL]) -> Bool {
        !urls.isEmpty && urls.allSatisfy { FileManager.default.fileExists(atPath: fileURL($0).path) }
    }

    /// Enforce the per-book disk budget by evicting the oldest read chapters.
    /// The current chapter and unread prefetch/downloads are never discarded.
    func trimReadChapters(_ chapters: [MangaChapterCacheRecord], currentChapterID: UUID,
                          maxBytes: Int = 512 * 1024 * 1024) throws -> [UUID] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])
        var sizes: [String: Int] = [:]
        for file in files { sizes[file.lastPathComponent] = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0 }
        var references: [URL: Int] = [:]
        for record in chapters {
            for url in Set(record.imageURLs) where sizes[fileURL(url).lastPathComponent] != nil {
                references[url, default: 0] += 1
            }
        }
        var bytes = references.keys.reduce(0) { $0 + (sizes[fileURL($1).lastPathComponent] ?? 0) }
        guard bytes > maxBytes else { return [] }
        let read = chapters.filter { $0.lastReadAt != nil && $0.id != currentChapterID }
            .sorted { ($0.lastReadAt ?? .distantPast) < ($1.lastReadAt ?? .distantPast) }
        var removed: [UUID] = []
        for record in read where bytes > maxBytes {
            let cached = Set(record.imageURLs).filter { references[$0] != nil }
            guard !cached.isEmpty else { continue }
            for url in cached {
                references[url, default: 0] -= 1
                if references[url] == 0 {
                    try remove([url])
                    bytes -= sizes[fileURL(url).lastPathComponent] ?? 0
                    references[url] = nil
                }
            }
            removed.append(record.id)
        }
        return removed
    }

    func cacheSummary(for entries: [LocalBookCacheEntry]) throws -> LocalCacheSummary {
        guard FileManager.default.fileExists(atPath: directory.path) else { return LocalCacheSummary(books: entries) }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])
        var sizes: [String: Int] = [:]
        for file in files { sizes[file.lastPathComponent] = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0 }
        let books = entries.map { entry in
            var sized = entry
            sized.imageBytes = Set(entry.imageURLs).reduce(0) { $0 + (sizes[fileURL($1).lastPathComponent] ?? 0) }
            return sized
        }
        return LocalCacheSummary(books: books, imageBytes: sizes.values.reduce(0, +))
    }

    func removeAll() async throws {
        let running = tail
        running?.cancel()
        _ = await running?.result
        tail = nil
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    func remove(_ urls: [URL]) throws {
        for url in Set(urls) {
            let file = fileURL(url)
            if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
        }
    }

    private func cachedData(at url: URL) throws -> Data? {
        let file = fileURL(url)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try Data(contentsOf: file, options: .mappedIfSafe)
    }

    private func fetch(_ url: URL, referer: URL) async throws -> Data {
        if let data = try cachedData(at: url) { return data }
        guard ["https", "http"].contains(url.scheme?.lowercased() ?? "") else {
            throw HTMLLoadError.invalidResponse
        }
        if let retryAfter, retryAfter > .now {
            throw HTMLLoadError.rateLimited(retryAfterSeconds: Int(ceil(retryAfter.timeIntervalSinceNow)))
        }
        try await limiter.wait(for: url)
        var request = URLRequest(url: url, timeoutInterval: 30)
        // Haoduo's public reader explicitly uses referrerpolicy="no-referrer".
        if !(referer.host?.hasSuffix("haoduoman.com") ?? false) {
            request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer")
        }
        request.setValue("image/webp,image/*;q=0.9", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw HTMLLoadError.invalidResponse }
        if http.statusCode == 429 {
            let value = http.value(forHTTPHeaderField: "Retry-After")
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
            let seconds = value.flatMap(Double.init)
                ?? value.flatMap { formatter.date(from: $0)?.timeIntervalSinceNow } ?? 60
            retryAfter = .now.addingTimeInterval(max(1, seconds))
            throw HTMLLoadError.rateLimited(retryAfterSeconds: Int(ceil(max(1, seconds))))
        }
        guard (200..<300).contains(http.statusCode) else { throw HTMLLoadError.httpStatus(http.statusCode) }
        guard data.count <= 30 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else { throw HTMLLoadError.invalidResponse }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: fileURL(url), options: .atomic)
        return data
    }

    private func fileURL(_ url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appending(path: digest)
    }
}
