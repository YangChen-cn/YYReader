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
/// Display-sized thumbnails are also kept in a bounded memory cache: decoding and
/// PNG-encoding a 2400px page on every reappearance is far more expensive than
/// holding the encoded bytes while a chapter is being read.
actor MangaImageCache {
    static let shared = MangaImageCache()

    private struct Thumbnail {
        let payload: MangaImagePayload
        var lastUsed: UInt64
    }

    private let directory: URL
    private let session: URLSession
    private let limiter = HostRateLimiter(defaultMinimumDelay: .milliseconds(180))
    private let thumbnailByteLimit: Int
    private let blobReader: (@Sendable (URL, URL) async throws -> MangaImageReadResult)?
    private var tail: Task<Data, any Error>?
    private var tailID: UUID?
    private var retryAfter: Date?
    private var thumbnails: [String: Thumbnail] = [:]
    private var thumbnailRecency: UInt64 = 0
    private var thumbnailBytes = 0
    private struct ThumbnailWork {
        let id: UUID
        let task: Task<MangaImagePayload, any Error>
        var waiters: Set<UUID>
    }
    private var thumbnailTasks: [String: ThumbnailWork] = [:]
    /// Bumped by `removeAll()` so work started before a cache clear cannot
    /// repopulate the memory cache or the disk directory afterwards.
    private var generation = 0
    private var thumbnailGeneration = 0

    init(
        directory: URL? = nil,
        session: URLSession = .shared,
        thumbnailByteLimit: Int = 64 * 1024 * 1024,
        blobReader: (@Sendable (URL, URL) async throws -> MangaImageReadResult)? = nil
    ) {
        self.directory = directory ?? URL.applicationSupportDirectory
            .appending(path: "YYReader/MangaImages", directoryHint: .isDirectory)
        self.session = session
        self.thumbnailByteLimit = max(thumbnailByteLimit, 0)
        self.blobReader = blobReader
    }

    func image(at url: URL, referer: URL) async throws -> MangaImagePayload {
        try Task.checkCancellation()
        let key = url.absoluteString
        let generation = thumbnailGeneration
        if let cached = takeThumbnail(forKey: key) { return cached }
        let waiter = UUID()
        let work: ThumbnailWork
        if var running = thumbnailTasks[key] {
            running.waiters.insert(waiter)
            thumbnailTasks[key] = running
            work = running
        } else {
            let created = ThumbnailWork(id: UUID(), task: Task { try await self.makeThumbnail(at: url, referer: referer) },
                                        waiters: [waiter])
            thumbnailTasks[key] = created
            work = created
        }
        defer { releaseThumbnailWaiter(key: key, workID: work.id, waiter: waiter, cancel: false) }
        return try await withTaskCancellationHandler {
            let payload = try await work.task.value
            try Task.checkCancellation()
            if generation == thumbnailGeneration, thumbnailTasks[key]?.id == work.id { store(payload, forKey: key) }
            return payload
        } onCancel: {
            Task { await self.releaseThumbnailWaiter(key: key, workID: work.id, waiter: waiter, cancel: true) }
        }
    }

    private func releaseThumbnailWaiter(key: String, workID: UUID, waiter: UUID, cancel: Bool) {
        guard var work = thumbnailTasks[key], work.id == workID else { return }
        work.waiters.remove(waiter)
        if work.waiters.isEmpty {
            // Keep shared work only while another visible page still needs it.
            // Rapid jumps must not queue obsolete downloads ahead of the new page.
            if cancel { work.task.cancel() }
            thumbnailTasks[key] = nil
        } else { thumbnailTasks[key] = work }
    }

    /// Read dimensions from cached file headers, without downloading or decoding
    /// the chapter. Prefetched originals therefore reserve their real height.
    func cachedAspectRatios(for urls: [URL]) -> [String: Double] {
        var result: [String: Double] = [:]
        for url in urls {
            if let thumbnail = thumbnails[url.absoluteString] {
                result[url.absoluteString] = thumbnail.payload.aspectRatio
                continue
            }
            let file = fileURL(url)
            guard FileManager.default.fileExists(atPath: file.path),
                  let source = CGImageSourceCreateWithURL(file as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Double,
                  let height = properties[kCGImagePropertyPixelHeight] as? Double, width > 0, height > 0 else { continue }
            let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
            result[url.absoluteString] = (5...8).contains(orientation) ? height / width : width / height
        }
        return result
    }

    private func makeThumbnail(at url: URL, referer: URL) async throws -> MangaImagePayload {
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
        try Task.checkCancellation()
        return MangaImagePayload(data: output as Data, aspectRatio: Double(thumbnail.width) / Double(thumbnail.height))
    }

    private func takeThumbnail(forKey key: String) -> MangaImagePayload? {
        guard var entry = thumbnails[key] else { return nil }
        thumbnailRecency &+= 1
        entry.lastUsed = thumbnailRecency
        thumbnails[key] = entry
        return entry.payload
    }

    private func store(_ payload: MangaImagePayload, forKey key: String) {
        guard payload.data.count <= thumbnailByteLimit else { return }
        thumbnailRecency &+= 1
        if let existing = thumbnails.updateValue(Thumbnail(payload: payload, lastUsed: thumbnailRecency), forKey: key) {
            thumbnailBytes -= existing.payload.data.count
        }
        thumbnailBytes += payload.data.count
        while thumbnailBytes > thumbnailByteLimit,
              let oldest = thumbnails.min(by: { $0.value.lastUsed < $1.value.lastUsed }) {
            thumbnailBytes -= oldest.value.payload.data.count
            thumbnails[oldest.key] = nil
        }
    }

    func original(at url: URL, referer: URL) async throws -> Data {
        try Task.checkCancellation()
        if let cached = try cachedData(at: url) { return cached }
        let previous = tail
        let id = UUID()
        let task = Task {
            // A failed/cancelled predecessor must not poison subsequent image requests.
            if let previous { _ = await previous.result }
            try Task.checkCancellation()
            return try await self.fetch(url, referer: referer)
        }
        tail = task
        tailID = id
        defer {
            // A completed Task retains its Data result. Release it when the
            // queue drains, without detaching a newer request's predecessor.
            if tailID == id { tail = nil; tailID = nil }
        }
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
        for work in thumbnailTasks.values { work.task.cancel() }
        thumbnailTasks.removeAll()
        // Detach the queue before awaiting: a request arriving meanwhile must not
        // chain onto the cancelled task and then be orphaned by `tail = nil`.
        let running = tail
        tail = nil
        tailID = nil
        running?.cancel()
        _ = await running?.result
        generation &+= 1
        thumbnailGeneration &+= 1
        thumbnails.removeAll()
        thumbnailBytes = 0
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    func remove(_ urls: [URL]) throws {
        for url in Set(urls) {
            thumbnailTasks.removeValue(forKey: url.absoluteString)?.task.cancel()
            if let existing = thumbnails.removeValue(forKey: url.absoluteString) {
                thumbnailBytes -= existing.payload.data.count
            }
            let file = fileURL(url)
            if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
        }
    }

    /// Test and diagnostic hook: how many display thumbnails are in memory.
    var cachedThumbnailCount: Int { thumbnails.count }
    var activeThumbnailWaiterCount: Int { thumbnailTasks.values.reduce(0) { $0 + $1.waiters.count } }
    var hasPendingOriginalRequest: Bool { tail != nil }

    private func cachedData(at url: URL) throws -> Data? {
        let file = fileURL(url)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try Data(contentsOf: file, options: .mappedIfSafe)
    }

    private func fetch(_ url: URL, referer: URL) async throws -> Data {
        if let data = try cachedData(at: url) { return data }
        let writeGeneration = generation
        guard MangaBlobSource(url: url) != nil || ["https", "http"].contains(url.scheme?.lowercased() ?? "") else {
            throw HTMLLoadError.invalidResponse
        }
        if let retryAfter, retryAfter > .now {
            throw HTMLLoadError.rateLimited(retryAfterSeconds: Int(ceil(retryAfter.timeIntervalSinceNow)))
        }
        try await limiter.wait(for: url)
        let data: Data
        if MangaBlobSource(url: url) != nil || DuokanMangaAdapter.supports(referer) {
            let result: MangaImageReadResult
            if let blobReader { result = try await blobReader(url, referer) }
            else { result = try await MangaBlobImageBridge.shared.readImage(url, chapterURL: referer) }
            try Task.checkCancellation()
            switch result {
            case let .encoded(encoded):
                guard encoded.utf8.count <= 40 * 1024 * 1024,
                      let decoded = Data(base64Encoded: encoded) else { throw HTMLLoadError.invalidResponse }
                data = decoded
            case let .address(address): data = try await download(address, referer: referer)
            }
        } else { data = try await download(url, referer: referer) }
        try Task.checkCancellation()
        guard data.count <= 30 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else { throw HTMLLoadError.invalidResponse }
        // A cache clear that happened while this image was downloading keeps the
        // image for its caller, but must not write it back into the fresh directory.
        if writeGeneration == generation {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: fileURL(url), options: .atomic)
        }
        return data
    }

    private func download(_ url: URL, referer: URL) async throws -> Data {
        guard ["https", "http"].contains(url.scheme ?? "") else { throw HTMLLoadError.invalidResponse }
        var request = URLRequest(url: url, timeoutInterval: 30)
        // Haoduo's public reader explicitly uses referrerpolicy="no-referrer".
        if !(referer.host?.hasSuffix("haoduoman.com") ?? false) {
            request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer")
        }
        request.setValue("image/webp,image/*;q=0.9", forHTTPHeaderField: "Accept")
        let (received, response) = try await session.data(for: request)
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
        return received
    }

    private func fileURL(_ url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appending(path: digest)
    }
}
