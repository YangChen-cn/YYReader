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
        #expect(catalog.chapters.map(\.sortIndex) == [1, 2])
        #expect(catalog.nextPageURL?.absoluteString == "https://www.qidiy.com/book/100_2/")
    }

    @Test
    func preservesCatalogOrderWhenExtraChaptersRestartAtOne() throws {
        let url = try #require(URL(string: "https://www.qidiy.com/book/100_2/"))
        let document = LoadedHTML(
            requestedURL: url,
            finalURL: url,
            html: """
                <h1>测试小说</h1><p>作者：测试作者</p>
                <ul class="section-list">
                    <li><a href="/book/100/20.html">第20章 正文结尾</a></li>
                    <li><a href="/book/100/extra-1.html">第1章 番外开始</a></li>
                    <li><a href="/book/100/extra-2.html">第2章 番外继续</a></li>
                </ul>
                """,
            retrievalKind: .urlSession
        )

        let catalog = try adapter.parseCatalogPage(document)

        #expect(catalog.chapters.map(\.title) == ["第20章 正文结尾", "第1章 番外开始", "第2章 番外继续"])
        #expect(catalog.chapters.map(\.sortIndex) == [1, 2, 3])
    }
}
