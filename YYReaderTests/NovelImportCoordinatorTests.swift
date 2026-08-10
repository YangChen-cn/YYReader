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
    func mergesChapterPagesAndLoadsOnlyFirstCatalogPageDuringImport() async throws {
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
        #expect(result.catalog.map(\.sortIndex) == [1, 2])
        #expect(!result.catalogIsComplete)
        #expect(result.bodyText.contains("第一段测试文字。"))
        #expect(result.bodyText.contains("第四段测试文字。"))
        #expect(!result.bodyText.contains("第1/2页"))
        #expect(result.nextChapterURL?.absoluteString == "https://www.qidiy.com/book/100/2.html")

        var startedPages: [Int] = []
        let refreshed = try await coordinator.refreshCatalog(from: catalog1) { pageNumber in
            startedPages.append(pageNumber)
        }
        #expect(refreshed.chapters.map(\.sortIndex) == [1, 2, 3, 4])
        #expect(startedPages == [1, 2])
    }

    @Test
    func catalogFailureDoesNotDiscardLoadedChapter() async throws {
        let chapter = try #require(URL(string: "https://www.qidiy.com/book/100/1.html"))
        let loader = MockHTMLLoader(documents: [
            chapter: """
            <a href="/book/100/">测试小说</a>
            <h1 class="title">第1章 起点</h1>
            <div id="content">已经成功取得的当前章节正文。</div>
            <a href="/book/100/">章节列表</a>
            <a href="/book/100/2.html">下一章</a>
            """
        ])
        let coordinator = NovelImportCoordinator(loader: loader)

        let result = try await coordinator.importNovel(from: chapter)

        #expect(result.bookTitle == "测试小说")
        #expect(result.bodyText == "已经成功取得的当前章节正文。")
        #expect(result.catalog.map(\.url) == [chapter])
        #expect(!result.catalogIsComplete)
    }

    @Test
    func importsAReadableChapterWithoutCatalog() async throws {
        let chapter = try #require(URL(string: "https://www.qidiy.com/book/100/1.html"))
        let loader = MockHTMLLoader(documents: [
            chapter: """
            <a href="/book/100/">没有目录的测试小说</a>
            <h1 class="title">第1章 独立阅读</h1>
            <div id="content">没有目录时也应保留这段可阅读的测试正文。</div>
            <a href="/book/100/2.html">下一章</a>
            """
        ])
        let coordinator = NovelImportCoordinator(loader: loader)

        let result = try await coordinator.importNovel(from: chapter)

        #expect(!result.hasCatalog)
        #expect(result.catalogURL == chapter)
        #expect(result.catalog.map(\.url) == [chapter])
        #expect(result.bodyText == "没有目录时也应保留这段可阅读的测试正文。")
    }

    @Test
    func readableChapterWithSidebarLinksIsNotImportedAsCatalog() async throws {
        let chapter = try #require(URL(string: "https://example.com/serial/bright-moon/3.html"))
        let loader = MockHTMLLoader(documents: [
            chapter: """
            <h1>第3章 正文优先</h1>
            <article>这是高置信度章节正文，用来验证即使页面侧栏列出了多个章节链接，也不会将当前章节误判成目录。这里继续补充自造段落，使正文长度明显高于目录探测的阈值。读者应该始终看到当前章节内容，而不是被跳转到侧栏中排列的第一章。为了覆盖较长正文的情形，再补充几句完全虚构的文字，说明章节页和目录页必须以正文质量区分。最后一段继续强调，这些文本不来自任何第三方小说。继续补充一段完整的自造正文，描述读者在夜色中翻开这一章、逐段阅读并保留进度的场景。这个额外段落只用于让 fixture 的正文长度跨过高置信度阈值，避免测试依赖某个恰好接近阈值的字符串长度。</article>
            <aside class="chapter-list">
                <a href="/serial/bright-moon/1.html">第1章 侧栏章节</a>
                <a href="/serial/bright-moon/2.html">第2章 侧栏章节</a>
                <a href="/serial/bright-moon/4.html">第4章 侧栏章节</a>
            </aside>
            """
        ])
        let coordinator = NovelImportCoordinator(loader: loader)

        let result = try await coordinator.importNovel(from: chapter)

        #expect(!result.hasCatalog)
        #expect(result.chapterURL == chapter)
        #expect(result.chapterTitle == "第3章 正文优先")
        #expect(result.bodyText.contains("高置信度章节正文"))
    }

    @Test
    func importsFromAGenericCatalogPageAndLoadsItsFirstChapter() async throws {
        let catalog = try #require(URL(string: "https://www.longwangxs.com/book/552/"))
        let chapter = try #require(URL(string: "https://www.longwangxs.com/book/552/prologue.html"))
        let firstNumberedChapter = try #require(URL(string: "https://www.longwangxs.com/book/552/1.html"))
        let secondChapter = try #require(URL(string: "https://www.longwangxs.com/book/552/2.html"))
        let loader = MockHTMLLoader(documents: [
            catalog: """
            <meta name="author" content="测试作者">
            <h1>目录页测试小说</h1><p>作者：测试作者</p>
            <article>这是一段目录页简介，而不是章节正文。它故意写得足够长，用于确认目录探测会优先识别章节列表，而不会把书籍简介误作第一个章节。继续补充自造内容，确保正文密度评分也会认为这里是一个看似可读的内容区域。</article>
            <section class="chapter-list">
                <a href="/book/552/prologue.html">前传 测试楔子</a>
                <a href="/book/552/1.html">第1章 起始章节</a>
                <a href="/book/552/2.html">第2章 后续章节</a>
            </section>
            """,
            chapter: """
            <title>第1章 起始章节_目录页测试小说</title>
            <h1>第1章 起始章节</h1>
            <article>这是从目录页导入后自动读取的第一段测试正文，长度足以通过通用正文识别。这里继续补充第二句话，以确认不是目录中的导航文字。最后补充第三句话，使测试正文保持自造且完整。为了覆盖通用解析器的正文密度阈值，再补充第四句关于阅读进度恢复的说明。继续补充第五句，确保这段自造文字明显长于导航、标题和目录链接的组合内容。</article>
            <a href="/book/552/">目录</a>
            <a href="/book/552/2.html">下一章</a>
            """
        ])
        let coordinator = NovelImportCoordinator(loader: loader)

        let result = try await coordinator.importNovel(from: catalog)

        #expect(result.bookTitle == "目录页测试小说")
        #expect(result.author == "测试作者")
        #expect(result.catalogURL == catalog)
        #expect(result.catalog.map(\.url) == [chapter, firstNumberedChapter, secondChapter])
        #expect(result.chapterURL == chapter)
        #expect(result.bodyText.contains("自动读取的第一段测试正文"))
    }

    @Test
    func retriesStaticHTMLParsingWithRenderedDOM() async throws {
        let chapter = try #require(URL(string: "https://www.qidiy.com/book/100/1.html"))
        let loader = RenderedDOMFallbackLoader(
            staticDocuments: [chapter: "<h1>正在加载正文</h1>"],
            renderedDocuments: [
                chapter: """
                <a href="/book/100/">动态测试小说</a>
                <h1 class="title">第1章 渲染正文</h1>
                <div id="content">由渲染 DOM 提供的可阅读测试正文。</div>
                <a href="/book/100/">章节列表</a>
                """
            ]
        )
        let coordinator = NovelImportCoordinator(loader: loader)

        let result = try await coordinator.loadChapterContent(from: chapter)

        #expect(result.bodyText == "由渲染 DOM 提供的可阅读测试正文。")
        #expect(loader.staticURLs == [chapter])
        #expect(loader.renderedURLs == [chapter])
        #expect(loader.promotedURLs == [chapter])
    }

    @Test
    func failedRenderedDOMDoesNotPromoteHost() async throws {
        let chapter = try #require(URL(string: "https://www.qidiy.com/book/100/1.html"))
        let loader = RenderedDOMFallbackLoader(
            staticDocuments: [chapter: "<h1>静态加载页</h1>"],
            renderedDocuments: [chapter: "<h1>渲染后仍无正文</h1>"]
        )
        let coordinator = NovelImportCoordinator(loader: loader)

        await #expect(throws: NovelParsingError.self) {
            try await coordinator.loadChapterContent(from: chapter)
        }

        #expect(loader.promotedURLs.isEmpty)
    }

    @Test
    func fullCatalogAssignsGlobalOrderWhenExtrasRestartChapterNumbers() async throws {
        let catalog1 = try #require(URL(string: "https://www.qidiy.com/book/200/"))
        let catalog2 = try #require(URL(string: "https://www.qidiy.com/book/200_2/"))
        let loader = MockHTMLLoader(documents: [
            catalog1: """
                <h1>长篇测试</h1><p>作者：测试作者</p>
                <ul class="section-list">
                    <li><a href="/book/200/1.html">第1章 正文一</a></li>
                    <li><a href="/book/200/2.html">第2章 正文二</a></li>
                </ul>
                <a href="/book/200_2/">下一页</a>
                """,
            catalog2: """
                <h1>长篇测试</h1><p>作者：测试作者</p>
                <ul class="section-list">
                    <li><a href="/book/200/3.html">第3章 正文三</a></li>
                    <li><a href="/book/200/extra-1.html">第1章 番外一</a></li>
                    <li><a href="/book/200/extra-2.html">第2章 番外二</a></li>
                </ul>
                """
        ])
        let coordinator = NovelImportCoordinator(loader: loader)

        let catalog = try await coordinator.refreshCatalog(from: catalog1)

        #expect(catalog.chapters.map(\.title) == [
            "第1章 正文一", "第2章 正文二", "第3章 正文三", "第1章 番外一", "第2章 番外二"
        ])
        #expect(catalog.chapters.map(\.sortIndex) == [1, 2, 3, 4, 5])
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

    @Test
    func catalogRefreshStopsAfterOverallDeadline() async throws {
        let catalog = try #require(URL(string: "https://www.qidiy.com/book/400/"))
        let loader = MockHTMLLoader(
            documents: [
                catalog: """
                    <h1>超时测试</h1><p>作者：测试作者</p>
                    <ul class="section-list">
                        <li><a href="/book/400/1.html">第1章 测试</a></li>
                    </ul>
                    """
            ],
            delay: .milliseconds(30)
        )
        let coordinator = NovelImportCoordinator(
            loader: loader,
            catalogRefreshTimeout: .milliseconds(10)
        )

        do {
            _ = try await coordinator.refreshCatalog(from: catalog)
            Issue.record("目录刷新超过截止时间后应抛出超时错误")
        } catch NovelParsingError.catalogRefreshTimedOut {
            // Expected.
        } catch {
            Issue.record("收到非预期错误：\(error)")
        }
    }
}

@MainActor
private final class RenderedDOMFallbackLoader: RenderedDOMFallbackLoading {
    private let staticDocuments: [URL: String]
    private let renderedDocuments: [URL: String]
    private(set) var staticURLs: [URL] = []
    private(set) var renderedURLs: [URL] = []
    private(set) var promotedURLs: [URL] = []

    init(staticDocuments: [URL: String], renderedDocuments: [URL: String]) {
        self.staticDocuments = staticDocuments
        self.renderedDocuments = renderedDocuments
    }

    func load(_ url: URL) async throws -> LoadedHTML {
        staticURLs.append(url)
        guard let html = staticDocuments[url] else { throw HTMLLoadError.httpStatus(404) }
        return LoadedHTML(requestedURL: url, finalURL: url, html: html, retrievalKind: .urlSession)
    }

    func loadRenderedDOM(_ url: URL) async throws -> LoadedHTML {
        renderedURLs.append(url)
        guard let html = renderedDocuments[url] else { throw HTMLLoadError.httpStatus(404) }
        return LoadedHTML(requestedURL: url, finalURL: url, html: html, retrievalKind: .webKit)
    }

    func promoteRenderedDOMHost(for url: URL) {
        promotedURLs.append(url)
    }
}
