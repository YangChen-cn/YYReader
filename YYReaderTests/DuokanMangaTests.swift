import Foundation
import Testing
@testable import YYReader

struct DuokanMangaTests {
    private let chapter = URL(string: "https://www.duokanmh.com/manhua/sample/1.html")!
    private let png = "iVBORw0KGgoAAAANSUhEUgAAAAIAAAADCAIAAAA2iEnWAAAAEElEQVR4nGMomLAAiBhQKABlVQnBJBo8DwAAAABJRU5ErkJggg=="
    private func loaded(_ html: String) -> LoadedHTML {
        LoadedHTML(requestedURL: chapter, finalURL: chapter, html: html, retrievalKind: .webKit)
    }

    @Test func normalPublicListProducesStableURLsAndChapterNavigation() async throws {
        let html = #"""
        <h1>001</h1><div class='chapter-images'><img src='blob:temporary'></div>
        <img src='https://example.com/ad.jpg'>
        <script id='yyreader-manga-images' type='application/json'>{"imageURLs":["https://cdn.example.com/1.webp","https://cdn.example.com/2.webp","https://cdn.example.com/1.webp"],"chapterTitle":"001","bookTitle":"自造漫画","catalogURL":"/manhua/sample"}</script>
        <a href='/manhua/sample/2.html'>下一章</a>
        """#
        let page = try await NovelParserRegistry().parseChapterPage(loaded(html))
        #expect(page.imageURLs.map(\.lastPathComponent) == ["1.webp", "2.webp"])
        #expect(page.bookTitle == "自造漫画" && page.catalogURL?.path == "/manhua/sample")
        #expect(page.nextChapterURL?.path == "/manhua/sample/2.html")
        #expect(page.paragraphs.isEmpty)
        #expect(try await NovelParserRegistry().parseChapterPage(loaded(html), contentType: .manga).imageURLs == page.imageURLs)
    }

    @Test func blobsWithoutPublicMetadataAndInvalidListsAreRejected() throws {
        for html in ["<h1>001</h1><div class='chapter-images'><img src='blob:temporary'></div>",
                     "<script id='yyreader-manga-images' type='application/json'>{\"imageURLs\":[\"blob:bad\"]}</script>"] {
            #expect(throws: NovelParsingError.noMangaImages) { try DuokanMangaAdapter().parseChapterPage(loaded(html)) }
        }
        #expect(!DuokanMangaAdapter.supports(URL(string: "https://duokanmh.com.evil.example/manhua/a/1.html")!))
    }

    @Test func onlyRequestedBlobIsReadAndDiskCacheWorksWithoutBrowser() async throws {
        let directory = URL.temporaryDirectory.appending(path: "BlobCache-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let counter = BlobRequestCounter()
        let encoded = png
        let cache = MangaImageCache(directory: directory, blobReader: { url, _ in
            await counter.record(url)
            return .encoded(encoded)
        })
        let image = URL(string: "https://cdn.example.com/1.webp")!
        let first = try await cache.image(at: image, referer: chapter)
        #expect(first.aspectRatio == 2.0 / 3.0)
        #expect(await counter.urls == [image])
        _ = try await cache.image(at: image, referer: chapter)
        #expect(await counter.urls == [image])
        let offline = MangaImageCache(directory: directory, blobReader: { _, _ in throw HTMLLoadError.invalidResponse })
        let bytes = try await offline.original(at: image, referer: chapter)
        #expect(bytes == Data(base64Encoded: png))
    }

    @Test func invalidBlobBytesDoNotBecomeOfflineCache() async throws {
        let directory = URL.temporaryDirectory.appending(path: "InvalidBlob-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = URL(string: "https://cdn.example.com/invalid.webp")!
        for encoded in ["not base64", Data("not an image".utf8).base64EncodedString()] {
            let cache = MangaImageCache(directory: directory, blobReader: { _, _ in .encoded(encoded) })
            await #expect(throws: HTMLLoadError.self) { try await cache.original(at: image, referer: chapter) }
            #expect(!(await cache.containsAll([image])))
        }
    }

    @Test func cancelledBlobDoesNotBlockNewPageOrWriteStaleCache() async throws {
        let directory = URL.temporaryDirectory.appending(path: "CancelBlob-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let counter = BlobRequestCounter()
        let encoded = png
        let cache = MangaImageCache(directory: directory, blobReader: { url, _ in
            await counter.record(url)
            if url.path.contains("slow") { try await Task.sleep(for: .seconds(30)) }
            return .encoded(encoded)
        })
        let slow = URL(string: "https://cdn.example.com/slow.webp")!
        let next = URL(string: "https://cdn.example.com/next.webp")!
        let old = Task { try await cache.original(at: slow, referer: chapter) }
        while await counter.urls.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        old.cancel()
        let bytes = try await cache.original(at: next, referer: chapter)
        #expect(bytes == Data(base64Encoded: png))
        #expect(!(await cache.containsAll([slow])))
        if case .success = await old.result { Issue.record("Cancelled blob request completed successfully") }
    }
}

private actor BlobRequestCounter {
    private(set) var urls: [URL] = []
    func record(_ url: URL) { urls.append(url) }
}
