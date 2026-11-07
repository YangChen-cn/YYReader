import Foundation
import CryptoKit
import ImageIO

actor TavernAvatarStore {
    static let shared = TavernAvatarStore()
    private let cache = NSCache<NSString, NSData>()
    private let failures = NSCache<NSString, NSDate>()
    private var pending: [String: Task<Data, Error>] = [:]
    private let rootDirectory: URL?
    private let loader: @Sendable (URL) async throws -> (Data, HTTPURLResponse)

    init(rootDirectory: URL? = nil, loader: (@Sendable (URL) async throws -> (Data, HTTPURLResponse))? = nil) {
        self.rootDirectory = rootDirectory
        self.loader = loader ?? { url in
            var request = URLRequest(url: url)
            request.timeoutInterval = 12
            // Download to an OS-managed temporary file first, so an oversized
            // original cannot occupy unbounded memory before the size check.
            let (file, response) = try await URLSession.shared.download(for: request)
            defer { try? FileManager.default.removeItem(at: file) }
            guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 10 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
            return (try Data(contentsOf: file), response)
        }
        cache.totalCostLimit = 8 * 1024 * 1024
        failures.countLimit = 128
    }

    private func directory() throws -> URL {
        if let rootDirectory {
            try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
            return rootDirectory
        }
        let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        let directory = root.appendingPathComponent("YYReader/TavernAvatars", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func prepare(from url: URL) throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 10 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
        let data = try Data(contentsOf: url)
        guard data.count <= 10 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
        try Task.checkCancellation()
        return try Self.thumbnail(data)
    }

    private static func thumbnail(_ data: Data) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 512
              ] as CFDictionary) else { throw CocoaError(.fileReadCorruptFile) }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        return output as Data
    }

    func save(_ data: Data, character: String) throws -> String {
        let prefix = SHA256.hash(data: Data(character.utf8)).map { String(format: "%02x", $0) }.joined()
        let folder = try directory()
        let name = prefix + "-" + UUID().uuidString + ".png"
        try data.write(to: folder.appendingPathComponent(name), options: .atomic)
        // Retain one small image per character; prior selections are disposable.
        for old in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            where old.lastPathComponent.hasPrefix(prefix + "-") && old.lastPathComponent != name {
            try FileManager.default.removeItem(at: old)
        }
        cache.removeAllObjects()
        cache.setObject(data as NSData, forKey: name as NSString, cost: data.count)
        return name
    }

    func read(_ name: String) throws -> Data {
        guard name == URL(fileURLWithPath: name).lastPathComponent, name.hasSuffix(".png") else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        if let cached = cache.object(forKey: name as NSString) { return cached as Data }
        let data = try Data(contentsOf: directory().appendingPathComponent(name))
        cache.setObject(data as NSData, forKey: name as NSString, cost: data.count)
        return data
    }

    /// Source used by the supplied author's helper, corroborated against the
    /// live browser. Only visible NPCs are resolved; user uploads always win.
    static func remoteCandidates(for speaker: String) -> [URL] {
        let name = speaker.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 40, !name.contains("/"), !name.contains("\\"), name != "{{user}}" else { return [] }
        let base = URL(string: "https://raw.githubusercontent.com/INK-996/imgbed/main/%E6%96%97%E4%BA%8C/")!
        return ["png", "jpg", "webp", "jpeg"].map { base.appendingPathComponent(name + "." + $0) }
    }

    func remote(for speaker: String) async throws -> Data {
        try Task.checkCancellation()
        let key = "remote-" + SHA256.hash(data: Data(speaker.utf8)).map { String(format: "%02x", $0) }.joined() + ".png"
        if let cached = cache.object(forKey: key as NSString) { return cached as Data }
        let file = try directory().appendingPathComponent(key)
        if FileManager.default.fileExists(atPath: file.path) { return try read(key) }
        if let until = failures.object(forKey: key as NSString), until.timeIntervalSinceNow > 0 { throw URLError(.fileDoesNotExist) }
        if let task = pending[key] { return try await task.value }
        guard pending.count < 8 else { throw URLError(.resourceUnavailable) }
        // Bounded shared requests survive a single cell disappearing. Each cell
        // checks cancellation before display; repeated speakers share one fetch.
        let task = Task { try await fetchRemote(speaker: speaker, key: key, file: file) }
        pending[key] = task
        defer { pending.removeValue(forKey: key) }
        return try await task.value
    }

    private func fetchRemote(speaker: String, key: String, file: URL) async throws -> Data {
        do {
            for url in Self.remoteCandidates(for: speaker) {
                let (data, response) = try await loader(url)
                if response.statusCode == 404 { continue }
                guard response.statusCode == 200 else { throw URLError(.badServerResponse) }
                guard data.count <= 10 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
                let result = try Self.thumbnail(data)
                try result.write(to: file, options: .atomic)
                cache.setObject(result as NSData, forKey: key as NSString, cost: result.count)
                try trimRemoteCache()
                return result
            }
            throw URLError(.fileDoesNotExist)
        } catch {
            failures.setObject(Date(timeIntervalSinceNow: 600) as NSDate, forKey: key as NSString)
            throw error
        }
    }

    private func trimRemoteCache() throws {
        let files = try FileManager.default.contentsOfDirectory(at: directory(), includingPropertiesForKeys: [.contentModificationDateKey])
            .filter { $0.lastPathComponent.hasPrefix("remote-") }
        guard files.count > 64 else { return }
        let ordered = try files.map { ($0, try $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast) }
            .sorted { $0.1 > $1.1 }
        for (file, _) in ordered.dropFirst(64) { try FileManager.default.removeItem(at: file) }
    }

}
