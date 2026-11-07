import Foundation
import ImageIO
import Testing
@testable import YYReader

private actor AvatarRequestLog {
    private(set) var urls: [URL] = []
    func response(_ url: URL, data: Data, succeeds: Bool) async throws -> (Data, HTTPURLResponse) {
        urls.append(url)
        try await Task.sleep(for: .milliseconds(10))
        let status = succeeds && url.pathExtension == "jpg" ? 200 : 404
        return (data, HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

struct TavernAvatarTests {
    private let image = Data(base64Encoded: "R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw==")!

    @Test func sourceUsesObservedAuthorHostAndEscapesNames() {
        let urls = TavernAvatarStore.remoteCandidates(for: "千仞雪")
        #expect(urls.map(\.pathExtension) == ["png", "jpg", "webp", "jpeg"])
        #expect(urls.allSatisfy { $0.host == "raw.githubusercontent.com" && $0.path.contains("/INK-996/imgbed/main/斗二/千仞雪.") })
        #expect(TavernAvatarStore.remoteCandidates(for: "../其它目录").isEmpty)
        #expect(TavernAvatarStore.remoteCandidates(for: "{{user}}").isEmpty)
    }

    @Test func repeatedSpeakersShareRequestAndCacheWorksOffline() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let log = AvatarRequestLog()
        let store = TavernAvatarStore(rootDirectory: folder, loader: { [image] url in
            try await log.response(url, data: image, succeeds: true)
        })
        async let first = store.remote(for: "示例角色")
        async let second = store.remote(for: "示例角色")
        let (a, b) = try await (first, second)
        #expect(a == b)
        #expect(await log.urls.count == 2)
        let offline = TavernAvatarStore(rootDirectory: folder, loader: { _ in throw URLError(.notConnectedToInternet) })
        #expect(try await offline.remote(for: "示例角色") == a)
        let source = try #require(CGImageSourceCreateWithData(a as CFData, nil))
        let thumbnail = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(thumbnail.width <= 512 && thumbnail.height <= 512)
    }

    @Test func missingPortraitDoesNotRepeatedlyHitImageHost() async {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let log = AvatarRequestLog()
        let store = TavernAvatarStore(rootDirectory: folder, loader: { [image] url in
            try await log.response(url, data: image, succeeds: false)
        })
        for _ in 0..<2 {
            do { _ = try await store.remote(for: "无图角色"); Issue.record("Missing image should fail") }
            catch { }
        }
        #expect(await log.urls.count == 4)
    }

    @Test func importedAvatarStaysIndependentOfNetworkAndRejectsTraversal() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = TavernAvatarStore(rootDirectory: folder, loader: { _ in throw URLError(.notConnectedToInternet) })
        let name = try await store.save(image, character: "主角")
        #expect(try await store.read(name) == image)
        await #expect(throws: CocoaError.self) { _ = try await store.read("../outside.png") }
    }
}
