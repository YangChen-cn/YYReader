import Foundation
import Testing
@testable import YYReader

struct QidiySourceAdapterTests {
    private let adapter = QidiySourceAdapter()

    @Test
    func parsesChapterAndRemovesPaginationNoise() throws {
        let url = try #require(URL(string: "https://www.qidiy.com/book/100/1.html"))
        let document = LoadedHTML(
            requestedURL: url,
            finalURL: url,
            html: try TestFixture.html("qidiy_chapter_1"),
            retrievalKind: .urlSession
        )

        let page = try adapter.parseChapterPage(document)

        #expect(page.title == "第1章 出发")
        #expect(page.bookTitle == "测试小说")
        #expect(page.paragraphs == ["第一段测试文字。", "第二段测试文字。"])
        #expect(page.nextPageURL?.absoluteString == "https://www.qidiy.com/book/100/1/2.html")
        #expect(page.catalogURL?.absoluteString == "https://www.qidiy.com/book/100/")
    }

    @Test
    func parsesCatalogAndNextCatalogPage() throws {
        let url = try #require(URL(string: "https://www.qidiy.com/book/100/"))
        let document = LoadedHTML(
            requestedURL: url,
            finalURL: url,
            html: try TestFixture.html("qidiy_catalog_1"),
            retrievalKind: .urlSession
        )

        let catalog = try adapter.parseCatalogPage(document)

        #expect(catalog.title == "测试小说")
        #expect(catalog.author == "测试作者")
        #expect(catalog.chapters.map(\.sortIndex) == [1, 2, 4])
        #expect(catalog.nextPageURL?.absoluteString == "https://www.qidiy.com/book/100_2/")
    }
}
