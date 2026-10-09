import Foundation
import Testing
@testable import YYReader

struct MangaImageLoadingTests {
    @Test func cancellingOneWaiterKeepsSharedDecodeAndCacheHit() async throws {
        let directory = URL.temporaryDirectory.appending(path: "MangaShared-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = MangaImageCache(directory: directory, session: session())
        let url = URL(string: "https://images.example.com/\(UUID()).png")!
        let first = Task { try await cache.image(at: url, referer: url) }
        let second = Task { try await cache.image(at: url, referer: url) }
        for _ in 0..<100 {
            if await cache.activeThumbnailWaiterCount == 2 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await cache.activeThumbnailWaiterCount == 2)
        first.cancel()
        let displayed = try await second.value
        #expect(displayed.aspectRatio > 0)
        _ = await first.result
        #expect(MangaImageTestProtocol.requests(url) == 1)
        #expect(await cache.cachedThumbnailCount == 1)
        let cached = try await cache.image(at: url, referer: url)
        #expect(cached.data == displayed.data)
        #expect(MangaImageTestProtocol.requests(url) == 1)
        let metadata = await cache.cachedAspectRatios(for: [url])
        #expect(metadata[url.absoluteString] == displayed.aspectRatio)
    }

    @Test func abandonedSlowPageDoesNotBlockNewPageOrRepopulateCache() async throws {
        let directory = URL.temporaryDirectory.appending(path: "MangaCancelled-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = MangaImageCache(directory: directory, session: session())
        let slow = URL(string: "https://images.example.com/slow-\(UUID()).png")!
        let next = URL(string: "https://images.example.com/next-\(UUID()).png")!
        let old = Task { try await cache.image(at: slow, referer: slow) }
        for _ in 0..<100 {
            if MangaImageTestProtocol.requests(slow) == 1 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        old.cancel()
        let clock = ContinuousClock()
        let start = clock.now
        let current = try await cache.image(at: next, referer: next)
        #expect(start.duration(to: clock.now) < .seconds(2))
        #expect(current.aspectRatio > 0)
        _ = await old.result
        #expect(await cache.cachedThumbnailCount == 1)
        #expect(!(await cache.containsAll([slow])))
        try await cache.removeAll()
        #expect(await cache.cachedThumbnailCount == 0)
    }

    private func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MangaImageTestProtocol.self]
        return URLSession(configuration: configuration)
    }
}

/// URLProtocol's callbacks may run on different queues; all mutable test state
/// is protected by locks. Responses are tiny invented images, not live requests.
private final class MangaImageTestProtocol: URLProtocol, @unchecked Sendable {
    private static let state = MangaImageProtocolState()
    private let lock = NSLock()
    private var pending: DispatchWorkItem?
    static func requests(_ url: URL) -> Int { state.count(url) }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        Self.state.start(url)
        let work = DispatchWorkItem { [self] in
            let cancelled = lock.withLock { pending?.isCancelled ?? true }
            guard !cancelled else { return }
            let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAIAAAADCAIAAAA2iEnWAAAAEElEQVR4nGMomLAAiBhQKABlVQnBJBo8DwAAAABJRU5ErkJggg==")!
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "image/png"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: png)
            client?.urlProtocolDidFinishLoading(self)
        }
        lock.withLock { pending = work }
        DispatchQueue.global().asyncAfter(deadline: .now() + (url.path.contains("slow-") ? 3 : 0.3), execute: work)
    }
    override func stopLoading() { lock.withLock { pending?.cancel() } }
}

private final class MangaImageProtocolState: @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [URL: Int] = [:]
    func count(_ url: URL) -> Int { lock.withLock { counts[url] ?? 0 } }
    func start(_ url: URL) { lock.withLock { counts[url, default: 0] += 1 } }
}
