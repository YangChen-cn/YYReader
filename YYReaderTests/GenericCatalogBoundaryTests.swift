import Foundation
import Testing
@testable import YYReader

struct GenericCatalogBoundaryTests {
    @Test
    func javascriptCatalogPreviewIsNotReportedAsComplete() throws {
        let url = try #require(URL(string: "https://example.com/novel/list.html"))
        let page = LoadedHTML(requestedURL: url, finalURL: url, html: try TestFixture.sharedHTML("ajax-catalog-preview"), retrievalKind: .urlSession)
        #expect(throws: NovelParsingError.catalogNeedsExpansion) {
            try GenericNovelAdapter().parseCatalogPage(page)
        }
    }

    @Test
    func novelContentWinsOverSemanticWrapperWithMetadata() throws {
        let url = try #require(URL(string: "https://example.com/book/1.html"))
        let page = LoadedHTML(requestedURL: url, finalURL: url, html: try TestFixture.sharedHTML("novel-content-body"), retrievalKind: .urlSession)
        let chapter = try GenericNovelAdapter().parseChapterPage(page)
        #expect(chapter.paragraphs.count == 2)
        #expect(!chapter.paragraphs.joined().contains("作者："))
    }

    @Test
    func latestUpdateOutsideCatalogDoesNotMoveLastChapterToFront() throws {
        let url = try #require(URL(string: "https://example.com/novel/"))
        let page = LoadedHTML(requestedURL: url, finalURL: url, html: try TestFixture.sharedHTML("latest-update-outside-catalog"), retrievalKind: .urlSession)

        let catalog = try GenericNovelAdapter().parseCatalogPage(page)

        #expect(catalog.chapters.map(\.title) == ["第1章 开始", "第2章 中途", "第3章 结尾"])
        #expect(catalog.chapters.map(\.sortIndex) == [1, 2, 3])
    }

    @Test
    func articleTextContainerExtractsBodyWithoutReaderControls() throws {
        let url = try #require(URL(string: "https://example.com/wangluo/12/100.html"))
        let page = LoadedHTML(requestedURL: url, finalURL: url, html: try TestFixture.sharedHTML("article-text-body"), retrievalKind: .urlSession)

        let chapter = try GenericNovelAdapter().parseChapterPage(page)

        #expect(chapter.title == "第一章 清晨")
        #expect(chapter.paragraphs.count == 2)
        #expect(!chapter.paragraphs.joined().contains("字号"))
        #expect(chapter.previousChapterURL == nil)
        #expect(chapter.nextChapterURL?.absoluteString == "https://example.com/wangluo/12/101.html")
    }

    @Test
    func lastChapterDoesNotNavigateToCatalogAsNextChapter() throws {
        let url = try #require(URL(string: "https://example.com/novel/3.html"))
        let page = LoadedHTML(requestedURL: url, finalURL: url, html: try TestFixture.sharedHTML("last-chapter-catalog-link"), retrievalKind: .urlSession)

        let chapter = try GenericNovelAdapter().parseChapterPage(page)

        #expect(chapter.previousChapterURL?.absoluteString == "https://example.com/novel/2.html")
        #expect(chapter.nextChapterURL == nil)
    }
}
