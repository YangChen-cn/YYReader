import Foundation
import Testing
@testable import YYReader

struct GenericCatalogBoundaryTests {
    private func catalog(_ titles: [String]) -> ParsedBookCatalog {
        ParsedBookCatalog(title: "测试", author: "作者", chapters: titles.enumerated().map {
            ChapterSeed(title: $0.element, url: URL(string: "https://example.com/\($0.offset).html")!, sortIndex: $0.offset + 1)
        }, nextPageURL: nil)
    }

    @Test func readingOrderWorksForNovelsAndMangaWithoutSortingIndividualEntries() {
        for titles in [
            ["第十二章", "公告", "第十一章", "第十章"],
            ["第3话", "第2话 下", "第2话 上", "第1话"],
            ["Chapter 103", "Chapter 102", "Chapter 101"],
            ["003·新篇", "002·中篇", "001·旧篇"],
            ["第697话", "第696话", "第900话 上", "第900话 下", "第695话", "第694话", "第693话"]
        ] {
            let result = catalog(titles).inReadingOrder()
            #expect(result.chapters.map(\.title) == Array(titles.reversed()))
            #expect(result.chapters.map(\.sortIndex) == Array(1...titles.count))
            #expect(result.inReadingOrder().chapters == result.chapters)
        }
    }

    @Test func uncertainMixedAndVolumeResetCatalogsKeepDOMOrder() {
        for titles in [
            ["第一章", "第二章", "第三章"],
            ["第9章", "第1章", "第2章", "第3章"],
            ["序章", "番外", "后记"],
            ["第2章", "第1章"],
            ["第10章", "第9章", "第8章", "第7章", "第6章", "第5章", "第4章", "第3章", "第2章", "第1章", "第10章", "第9章", "第8章", "第7章", "第6章", "第5章", "第4章", "第3章", "第2章", "第1章"]
        ] {
            #expect(catalog(titles).inReadingOrder().chapters.map(\.title) == titles)
        }
    }

    @Test func descendingPaginatedCatalogIsReversedAfterMerging() async throws {
        let first = catalog(["第六章", "第五章", "第四章"])
        let second = ParsedBookCatalog(title: "测试", author: "作者", chapters: [3,2,1].map {
            ChapterSeed(title: "第\($0)章", url: URL(string: "https://example.com/next/\($0).html")!, sortIndex: $0)
        }, nextPageURL: nil)
        let result = try await NovelProcessingWorker().aggregateCatalogPages([first, second])
        #expect(result.chapters.map(\.title) == ["第1章", "第2章", "第3章", "第四章", "第五章", "第六章"])
    }

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
