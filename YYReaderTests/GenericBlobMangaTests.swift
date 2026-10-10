import Foundation
import Testing
@testable import YYReader

struct GenericBlobMangaTests {
    private let chapter = URL(string: "https://unrelated.example.org/chapter/7?volume=2")!
    private func document(_ html: String) -> LoadedHTML {
        LoadedHTML(requestedURL: chapter, finalURL: chapter, html: html, retrievalKind: .webKit)
    }
    private func html(_ prefix: String = "uuid", pending: Bool = false) -> String {
        let pages = (0..<18).map { index in
            "<figure><img width='800' height='1200' src='\(pending && index > 0 ? "" : "blob:https://unrelated.example.org/\(prefix)-\(index)")'></figure>"
        }.joined()
        return "<h1>第7话</h1><section class='unfamiliar'>\(pages)</section><a href='/chapter/8'>下一话</a>"
    }

    @Test func unknownHostBlobReaderAutomaticallyUsesStableReferences() async throws {
        let page = try await NovelParserRegistry().parseChapterPage(document(html()))
        #expect(page.imageURLs.count == 18 && page.paragraphs.isEmpty)
        for (index, url) in page.imageURLs.enumerated() {
            let source = try #require(MangaBlobSource(url: url))
            #expect(source.chapterURL == chapter && source.index == index)
            #expect(!url.absoluteString.contains("uuid"))
        }
        await #expect(throws: NovelParsingError.noReadableContent) {
            try await NovelParserRegistry().parseChapterPage(document(html()), contentType: .novel)
        }
    }

    @Test func regeneratedBlobUUIDsAndPendingPagesKeepTheSameCacheKeys() throws {
        let adapter = GenericMangaAdapter()
        let original = try adapter.parseChapterPage(document(html()))
        let fresh = try adapter.parseChapterPage(document(html("another")))
        let pending = try adapter.parseChapterPage(document(html(pending: true)))
        #expect(original.imageURLs == fresh.imageURLs && fresh.imageURLs == pending.imageURLs)
        #expect(pending.imageURLs.count == 18)
    }

    @Test func mixedPagesKeepResolvedHTTPAddressesInsteadOfBlobExtraction() throws {
        // A page whose first and last images are displayed as blobs, while the
        // middle one only has a data: placeholder plus the real address in
        // data-src. That address is already usable and must survive.
        let mixed = """
        <h1>第7话</h1><section class='unfamiliar'>
        <figure><img width='800' height='1200' src='blob:https://unrelated.example.org/uuid-0'></figure>
        <figure><img width='800' height='1200' src='data:image/gif;base64,R0lGODlhAQABAAAAACw=' data-src='https://unrelated.example.org/page-1.jpg'></figure>
        <figure><img width='800' height='1200' src='blob:https://unrelated.example.org/uuid-2'></figure>
        </section><a href='/chapter/8'>下一话</a>
        """
        let page = try GenericMangaAdapter().parseChapterPage(document(mixed))
        #expect(page.imageURLs.count == 3)
        #expect(MangaBlobSource(url: page.imageURLs[0])?.index == 0)
        #expect(MangaBlobSource(url: page.imageURLs[2])?.index == 2)
        #expect(page.imageURLs[1].absoluteString == "https://unrelated.example.org/page-1.jpg")
    }

    @Test func relocationRescoresReaderInsteadOfUsingStaleDocumentOffsets() async throws {
        let source = MangaBlobSource(chapterURL: chapter, index: 3)
        let locator = MangaBlobRegionLocator()
        let first = try await locator.locate(source, in: document(html()))
        let second = try await locator.locate(source, in: document("<img class='ad' src='/advert.jpg'>" + html("fresh")))
        #expect(first.domIndex == 3 && second.domIndex == 4)
        #expect(second.directURL == nil)
        await #expect(throws: NovelParsingError.noMangaImages) {
            try await locator.locate(MangaBlobSource(chapterURL: chapter, index: 999), in: document(html()))
        }
    }

    @Test func privateSourceRoundTripsChapterQueriesAndRejectsInvalidInput() {
        let source = MangaBlobSource(chapterURL: chapter, index: 9)
        #expect(MangaBlobSource(url: source.url)?.chapterURL == chapter)
        #expect(MangaBlobSource(url: URL(string: "yyreader-blob://image?chapter=file%3A%2F%2F%2Fetc%2Fpasswd&index=0")!) == nil)
        #expect(MangaBlobSource(url: URL(string: "yyreader-blob://image?chapter=https%3A%2F%2Fexample.com&index=-1")!) == nil)
    }

    @Test func pendingImagesAloneDoNotActivateBlobAndForeignOriginIsRejected() throws {
        let empty = html(pending: true).replacingOccurrences(of: "blob:https://unrelated.example.org/uuid-0", with: "")
        let foreign = html().replacingOccurrences(of: "blob:https://unrelated.example.org/", with: "blob:https://foreign.example/")
        for markup in [empty, foreign] {
            #expect(throws: NovelParsingError.noMangaImages) { try GenericMangaAdapter().parseChapterPage(document(markup)) }
        }
    }

    @Test func genericBlobUsesNormalCacheAndCanReopenOffline() async throws {
        let directory = URL.temporaryDirectory.appending(path: "GenericBlob-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let png = "iVBORw0KGgoAAAANSUhEUgAAAAIAAAADCAIAAAA2iEnWAAAAEElEQVR4nGMomLAAiBhQKABlVQnBJBo8DwAAAABJRU5ErkJggg=="
        let cache = MangaImageCache(directory: directory, blobReader: { _, _ in .encoded(png) })
        let image = MangaBlobSource(chapterURL: chapter, index: 0).url
        let displayed = try await cache.image(at: image, referer: chapter)
        #expect(displayed.aspectRatio == 2.0 / 3.0)
        let offline = MangaImageCache(directory: directory, blobReader: { _, _ in throw HTMLLoadError.invalidResponse })
        #expect(try await offline.original(at: image, referer: chapter) == Data(base64Encoded: png))
    }
}
