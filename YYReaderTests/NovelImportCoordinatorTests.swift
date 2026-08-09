import Foundation
import Testing
@testable import YYReader

@MainActor
struct NovelImportCoordinatorTests {
    @Test
    func acceptsDocumentedQidiyExampleMetadataAndTwoPageChapter() async throws {
        let chapter1 = URL(string: "https://www.qidiy.com/book/75509/35622389.html")!
        let chapter2 = URL(string: "https://www.qidiy.com/book/75509/35622389/2.html")!
        let catalog = URL(string: "https://www.qidiy.com/book/75509/")!
        let loader = MockHTMLLoader(documents: [
            chapter1: """
                <a href="/book/75509/">全职法师</a>
                <h1 class="title">第1章 世界大变（第1/2页）</h1>
                <div id="content">验收用第一段。<br>（本章未完，请点击下一页继续阅读）</div>
                <a href="/book/75509/">章节列表</a>
                <a href="/book/75509/35622389/2.html">下一页</a>
                """,
            chapter2: """
                <a href="/book/75509/">全职法师</a>
                <h1 class="title">第1章 世界大变（第2/2页）</h1>
                <div id="content">验收用第二段。</div>
                <a href="/book/75509/">章节列表</a>
                <a href="/book/75509/35622390.html">下一章</a>
                """,
            catalog: """
                <h1>全职法师</h1><p>作者：乱</p>
                <ul class="section-list">
                    <li><a href="/book/75509/35622389.html">第1章 世界大变</a></li>
                    <li><a href="/book/75509/35622390.html">第2章 魔法觉醒</a></li>
                </ul>
                """
        ])
        let coordinator = NovelImportCoordinator(loader: loader)

        let result = try await coordinator.importNovel(from: chapter1)

        #expect(result.bookTitle == "全职法师")
        #expect(result.author == "乱")
        #expect(result.chapterTitle == "第1章 世界大变")
        #expect(result.bodyText == "验收用第一段。\n\n验收用第二段。")
        #expect(result.nextChapterURL?.absoluteString == "https://www.qidiy.com/book/75509/35622390.html")
    }

    @Test
    func mergesChapterPagesAndAllCatalogPages() async throws {
        let chapter1 = try #require(URL(string: "https://www.qidiy.com/book/100/1.html"))
        let chapter2 = try #require(URL(string: "https://www.qidiy.com/book/100/1/2.html"))
        let catalog1 = try #require(URL(string: "https://www.qidiy.com/book/100/"))
        let catalog2 = try #require(URL(string: "https://www.qidiy.com/book/100_2/"))
        let loader = MockHTMLLoader(documents: [
            chapter1: try TestFixture.html("qidiy_chapter_1"),
            chapter2: try TestFixture.html("qidiy_chapter_2"),
            catalog1: try TestFixture.html("qidiy_catalog_1"),
            catalog2: try TestFixture.html("qidiy_catalog_2")
        ])
        let coordinator = NovelImportCoordinator(loader: loader)

        let result = try await coordinator.importNovel(from: chapter1)

        #expect(result.bookTitle == "测试小说")
        #expect(result.author == "测试作者")
        #expect(result.catalog.map(\.sortIndex) == [1, 2, 3, 4])
        #expect(result.bodyText.contains("第一段测试文字。"))
        #expect(result.bodyText.contains("第四段测试文字。"))
        #expect(!result.bodyText.contains("第1/2页"))
        #expect(result.nextChapterURL?.absoluteString == "https://www.qidiy.com/book/100/2.html")
    }

    @Test
    func rejectsPaginationLoop() async throws {
        let chapter = try #require(URL(string: "https://www.qidiy.com/book/100/1.html"))
        let loopingHTML = """
        <h1 class="title">第1章 循环</h1><a href="/book/100/">章节列表</a>
        <a href="/book/100/1.html">下一页</a><div id="content">足够用于解析的测试正文内容。</div>
        """
        let loader = MockHTMLLoader(documents: [chapter: loopingHTML])
        let coordinator = NovelImportCoordinator(loader: loader)

        await #expect(throws: NovelParsingError.self) {
            try await coordinator.loadChapterContent(from: chapter)
        }
    }
}
