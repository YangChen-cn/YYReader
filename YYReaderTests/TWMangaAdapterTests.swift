import Foundation
import Testing
@testable import YYReader

struct TWMangaAdapterTests {
    private let root = "https://www.twmanga.com"

    @Test @MainActor func mergesChapterPagesWithoutReadingTheNextChapter() async throws {
        let path = "/comic/chapter/sample/"
        let first = try #require(URL(string: root + path + "0_20.html"))
        let second = try #require(URL(string: root + path + "0_20_2.html"))
        let next = try #require(URL(string: root + path + "0_21.html"))
        let prior = try #require(URL(string: root + path + "0_19.html"))
        func page(_ number: Int, previous: URL, next: URL) -> String {
            """
            <title>第18話(\(number)/2) - 漫畫範例 - 包子漫畫</title>
            <amp-img class="comic-contain__item" src="https://example.com/ad.jpg"></amp-img>
            <ul class="comic-contain"><amp-img class="comic-contain__item" data-src="https://example.com/\(number).jpg"></amp-img></ul>
            <a id="prev-chapter" href="\(previous.absoluteString)">上一頁</a>
            <a id="next-chapter" href="\(next.absoluteString)">下一頁</a>
            """
        }
        let loader = MockHTMLLoader(documents: [
            first: page(1, previous: prior, next: second),
            second: page(2, previous: first, next: next)
        ])
        let result = try await NovelImportCoordinator(loader: loader).loadChapterContent(from: first)
        #expect(result.title == "第18話")
        #expect(result.imageURLs.map(\.lastPathComponent) == ["1.jpg", "2.jpg"])
        #expect(result.previousChapterURL == prior)
        #expect(result.nextChapterURL == next)
    }

    @Test func usesFullDirectoryInDOMOrderWithoutLatestRepetitions() throws {
        let url = try #require(URL(string: root + "/comic/sample"))
        func entry(_ slot: Int, _ title: String) -> String {
            """
            <a class="comics-chapters__item" href="/user/page_direct?comic_id=sample&amp;section_slot=0&amp;chapter_slot=\(slot)">\(title)</a>
            """
        }
        let document = LoadedHTML(requestedURL: url, finalURL: url, html: """
            <h1 class="comics-detail__title">測試漫畫</h1><h2 class="comics-detail__author">作者甲</h2>
            <div>\(entry(2, "第2話"))</div>
            <div id="chapter-items">\(entry(0, "第1話"))</div>
            <div id="chapters_other_list" hidden>\(entry(1, "後記"))\(entry(2, "第2話"))</div>
            """, retrievalKind: .urlSession)
        let result = try TWMangaAdapter().parseCatalogPage(document)
        #expect(result.author == "作者甲")
        #expect(result.chapters.map(\.title) == ["第1話", "後記", "第2話"])
        #expect(result.chapters.map { $0.url.lastPathComponent } == ["0_0.html", "0_1.html", "0_2.html"])
    }
}
