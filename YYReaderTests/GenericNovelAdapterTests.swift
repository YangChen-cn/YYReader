import Foundation
import Testing
@testable import YYReader

struct GenericNovelAdapterTests {
    @Test
    func extractsSemanticArticleAndNavigation() throws {
        let url = try #require(URL(string: "https://example.com/book/3.html"))
        let document = LoadedHTML(
            requestedURL: url,
            finalURL: url,
            html: try TestFixture.html("generic_chapter"),
            retrievalKind: .urlSession
        )

        let result = try GenericNovelAdapter().parseChapterPage(document)

        #expect(result.title == "第三章 雨夜")
        #expect(result.author == "某作者")
        #expect(result.paragraphs.count == 3)
        #expect(result.previousChapterURL?.absoluteString == "https://example.com/book/2.html")
        #expect(result.nextChapterURL?.absoluteString == "https://example.com/book/4.html")
    }

    @Test
    func semanticArticleWinsOverLargeSidebarCatalog() throws {
        let url = try #require(URL(string: "https://example.com/book/3.html"))
        let sidebar = (1...10).map {
            "<a href='/book/\($0).html'>第\($0)章 侧栏章节</a>"
        }.joined()
        let document = LoadedHTML(
            requestedURL: url,
            finalURL: url,
            html: """
            <h1>第3章 正文优先</h1>
            <article>
              <p>这是正常小说正文的第一段，长度足以通过既有正文评分阈值，不应受到页面侧栏目录数量影响。</p>
              <p>这是正常小说正文的第二段，继续提供稳定可读的虚构内容，并保持现有评分门槛不变。</p>
            </article>
            <aside class="chapter-list">\(sidebar)</aside>
            """,
            retrievalKind: .urlSession
        )

        let chapter = try GenericNovelAdapter().parseChapterPage(document)

        #expect(chapter.title == "第3章 正文优先")
        #expect(chapter.paragraphs.count == 2)
        #expect(!chapter.paragraphs.joined().contains("侧栏章节"))
    }

    @Test
    func extractsNovelOpenGraphAndStructuralChapterNavigation() throws {
        let url = try #require(URL(string: "https://reader.example/novel/pagea/story-author_2.html"))
        let document = LoadedHTML(
            requestedURL: url,
            finalURL: url,
            html: """
            <head>
              <title>⚡ 《示例小说》 第一幕 开始 - 小说站</title>
              <meta name="og:title" content="《示例小说》 第一幕 开始 - 小说站">
            </head>
            <div class="bread_crumbs">
              <a href="/novel/chapters/story-author">《示例小说》</a>
            </div>
            <div class="prev_page"><a href="story-author_1.html">序幕</a></div>
            <div class="title"><h1>第一幕 开始</h1></div>
            <div class="content">
              <p>这是正文第一段，包含足够多的文字来确认它是小说内容，而不是页面菜单或者站点导航。</p>
              <p>这是正文第二段，同样只保留适合原生阅读器显示的干净文本内容。</p>
            </div>
            <div class="next_page_links">
              <a href="story-author_3.html" title="第二幕 后续">第二幕 后续</a>
            </div>
            """,
            retrievalKind: .urlSession
        )

        let result = try GenericNovelAdapter().parseChapterPage(document)

        #expect(result.title == "第一幕 开始")
        #expect(result.bookTitle == "示例小说")
        #expect(result.catalogURL?.absoluteString == "https://reader.example/novel/chapters/story-author")
        #expect(result.previousChapterURL?.absoluteString == "https://reader.example/novel/pagea/story-author_1.html")
        #expect(result.nextChapterURL?.absoluteString == "https://reader.example/novel/pagea/story-author_3.html")
    }

    @Test
    func prefersNarrowBodyAndExtractsMetadataFromDescription() throws {
        let url = try #require(URL(string: "https://example.com/book/75012/3.html"))
        let document = LoadedHTML(
            requestedURL: url,
            finalURL: url,
            html: """
            <head>
              <title>示例小说 第3章 卡塞尔之门（第1页/共2页）-小说站</title>
              <meta name="description" content="小说站提供了示例作者创作的《示例小说》第3章在线阅读。">
            </head>
            <header><h1><a href="/">小说站</a></h1></header>
            <div class="reader-main">
              <div class="reader-fun">字体 大 中 小 背景颜色 护眼模式</div>
              <h1 class="title">第3章 卡塞尔之门（第1页/共2页）</h1>
              <a id="index_url" href="/book/75012/">章节目录</a>
              <a id="next_url" href="3_2.html">下一页</a>
              <div id="content">
                <p>路上发生了许多事情，这是正文第一段，长度足够用于通用正文候选判断。</p>
                <p>人物继续向前，这是正文第二段，页面上的阅读设置不应被混入这里。</p>
              </div>
            </div>
            """,
            retrievalKind: .urlSession
        )

        let result = try GenericNovelAdapter().parseChapterPage(document)

        #expect(result.title == "第3章 卡塞尔之门")
        #expect(result.bookTitle == "示例小说")
        #expect(result.author == "示例作者")
        #expect(result.paragraphs.count == 2)
        #expect(!result.paragraphs.joined().contains("字体 大 中 小"))
        #expect(result.nextPageURL?.absoluteString == "https://example.com/book/75012/3_2.html")
    }

    @Test
    func extractsBookTitleFromQuotedOpenGraphAndDescriptionMetadata() throws {
        let url = try #require(URL(string: "https://example.com/book/3.html"))
        let openGraphDocument = LoadedHTML(
            requestedURL: url,
            finalURL: url,
            html: """
            <head>
              <meta property="og:title" content="《测试小说》第3章">
            </head>
            <h1>第3章 测试</h1>
            <article>这是用于验证元数据提取顺序的虚构正文，内容长度足以通过当前解析阈值，并且不会依赖普通描述文字猜测书名。这里继续补充完全自造的句子，确保正文评分稳定超过六十分。</article>
            """,
            retrievalKind: .urlSession
        )
        let descriptionDocument = LoadedHTML(
            requestedURL: url,
            finalURL: url,
            html: """
            <head>
              <meta name="description" content="小说站提供《测试小说》第3章在线阅读。">
            </head>
            <h1>第3章 测试</h1>
            <article>这是用于验证明确书名括号提取的另一段虚构正文，普通描述句子本身不会被任意猜测成书名。这里继续补充完全自造的句子，确保正文评分稳定超过六十分。</article>
            """,
            retrievalKind: .urlSession
        )
        let ordinaryDescriptionDocument = LoadedHTML(
            requestedURL: url,
            finalURL: url,
            html: """
            <head>
              <meta name="description" content="测试小说 第3章在线阅读">
            </head>
            <h1>第3章 测试</h1>
            <article>这是用于验证普通章节描述不会被猜成书名的虚构正文。这里继续补充完全自造的句子，确保正文评分稳定超过六十分，同时不提供其他书名元数据。</article>
            """,
            retrievalKind: .urlSession
        )

        let openGraphChapter = try GenericNovelAdapter().parseChapterPage(openGraphDocument)
        let descriptionChapter = try GenericNovelAdapter().parseChapterPage(descriptionDocument)
        let ordinaryDescriptionChapter = try GenericNovelAdapter().parseChapterPage(ordinaryDescriptionDocument)

        #expect(openGraphChapter.bookTitle == "测试小说")
        #expect(descriptionChapter.bookTitle == "测试小说")
        #expect(ordinaryDescriptionChapter.bookTitle == nil)
    }

    @Test
    func longCatalogIsNotMistakenForChapterContent() throws {
        let url = try #require(URL(string: "https://example.com/read/1490/"))
        let chapters = (1...10).map { "<dd><a href='\($0).html'>第\($0)章 示例章节</a></dd>" }.joined()
        let document = LoadedHTML(
            requestedURL: url,
            finalURL: url,
            html: """
            <head>
              <meta property="og:novel:book_name" content="目录示例小说">
              <meta property="og:novel:author" content="目录作者">
            </head>
            <div id="content-list">
              <div class="intro">这里是很长的作品简介，不能被当成小说正文。这里是很长的作品简介，不能被当成小说正文。</div>
              <dl>\(chapters)</dl>
            </div>
            """,
            retrievalKind: .urlSession
        )

        let catalog = try GenericNovelAdapter().parseCatalogPage(document)

        #expect(catalog.title == "目录示例小说")
        #expect(catalog.author == "目录作者")
        #expect(catalog.chapters.count == 10)
        #expect(throws: NovelParsingError.self) {
            try GenericNovelAdapter().parseChapterPage(document)
        }
    }

    @Test
    func bookLandingContinuesToCompleteCatalogAndRecognizesPreface() throws {
        let landingURL = try #require(URL(string: "https://reader.example/book/155532/"))
        let landing = LoadedHTML(
            requestedURL: landingURL,
            finalURL: landingURL,
            html: """
            <meta name="author" content="测试作者"><h1>完整目录测试</h1>
            <div class="chapter-list">
              <a href="766.html"><h4>后记</h4><small>VIP</small></a>
              <a href="765.html"><h4>第766章 终章之后</h4><small>免费</small></a>
            </div>
            <div class="chapter-more"><a href="list/">全部章节</a></div>
            """,
            retrievalKind: .urlSession
        )

        let landingCatalog = try GenericNovelAdapter().parseCatalogPage(landing)

        #expect(landingCatalog.chapters.map(\.title) == ["后记", "第766章 终章之后"])
        #expect(landingCatalog.nextPageURL?.absoluteString == "https://reader.example/book/155532/list/")

        let listURL = try #require(landingCatalog.nextPageURL)
        let completeList = LoadedHTML(
            requestedURL: listURL,
            finalURL: listURL,
            html: """
            <meta name="author" content="测试作者"><h1>完整目录测试</h1>
            <div class="chapter-list">
              <a href="preface.html"><h4>序言</h4><small>免费</small></a>
              <a href="1.html"><h4>第1章 开始</h4><small>免费</small></a>
              <a href="765.html"><h4>第766章 终章之后</h4><small>免费</small></a>
              <a href="766.html"><h4>后记</h4><small>VIP</small></a>
            </div>
            """,
            retrievalKind: .urlSession
        )

        let completeCatalog = try GenericNovelAdapter().parseCatalogPage(completeList)
        #expect(completeCatalog.chapters.map(\.title) == ["序言", "第1章 开始", "第766章 终章之后", "后记"])
    }

    @Test
    func extractsBookLandingMetadataAndExcludesReaderControls() throws {
        let catalogURL = try #require(URL(string: "https://example.com/series/volume/"))
        let catalogDocument = LoadedHTML(
            requestedURL: catalogURL,
            finalURL: catalogURL,
            html: """
            <header><h1 id="logo">小说站</h1></header>
            <div class="book-describe">
              <h1>示例小说 第三部 下</h1>
              <p>作者：示例作者</p>
            </div>
            <div class="book-list">
              <a href="1.html">楔子</a>
              <a href="2.html">第一章 开始 · 一</a>
            </div>
            """,
            retrievalKind: .urlSession
        )
        let catalog = try GenericNovelAdapter().parseCatalogPage(catalogDocument)
        #expect(catalog.title == "示例小说 第三部 下")
        #expect(catalog.author == "示例作者")

        let chapterURL = try #require(URL(string: "https://example.com/series/2.html"))
        let chapterDocument = LoadedHTML(
            requestedURL: chapterURL,
            finalURL: chapterURL,
            html: """
            <header><h1 id="logo">小说站</h1></header>
            <nav class="bcrumb"><a href="volume/" rel="category tag">示例小说 第三部 下</a></nav>
            <article class="post">
              <h1 id="nr_title">第一章 开始 · 一</h1>
              <div class="nr_set">关灯 护眼 小 中 大 繁 直达底部</div>
              <a href="1.html" rel="prev">上一章</a>
              <a href="3.html" rel="next">下一章</a>
              <div id="nr1">
                <p>正文第一段有足够多的内容，设置选项不应该跟随正文进入原生阅读界面。</p>
                <p>🍐 落`霞-读`书-l u o x i a d u s h u . c o m-</p>
                <p>正文第二段继续讲述故事，并保持为一个独立、干净且稳定的段落。<a href="/">落霞</a></p>
              </div>
            </article>
            """,
            retrievalKind: .urlSession
        )

        let chapter = try GenericNovelAdapter().parseChapterPage(chapterDocument)
        #expect(chapter.title == "第一章 开始 · 一")
        #expect(chapter.bookTitle == "示例小说 第三部 下")
        #expect(chapter.paragraphs.count == 2)
        #expect(!chapter.paragraphs.joined().contains("关灯"))
        #expect(!chapter.paragraphs.joined().contains("落`霞"))
        #expect(!chapter.paragraphs.joined().hasSuffix("落霞"))
        #expect(chapter.nextChapterURL?.absoluteString == "https://example.com/series/3.html")
    }

    @Test
    func excludesNavigationLinksEmbeddedInsideContentContainer() throws {
        let url = try #require(URL(string: "https://reader.example/douluodalu2/29797.html"))
        let document = LoadedHTML(
            requestedURL: url,
            finalURL: url,
            html: """
            <head><title>第二章 苏醒_斗罗大陆Ⅱ绝世唐门</title></head>
            <h1>第二章 苏醒</h1>
            <div id="content">
              <p>上一章：引子 神界！唐三一家</p>
              <p>下一章：第一章 灵眸少年（二）</p>
              <p>如果被/浏/览/器/强/制进入它们的阅/读/模/式了，阅读体/验极/差请退出转/码阅读。</p>
              <p>清晨的阳光落在窗前，少年缓缓睁开眼睛，回想起昨夜发生的事情。</p>
              <div class="chapter-nav">
                <a href="29796.html">上一章</a> | <a href="index.html">章节目录</a> | <a href="29798.html">下一章</a>
              </div>
              <p>他起身推开房门，远处的钟声响起，崭新的一天就这样开始了。</p>
              <p>故事里曾经提到上一章留下的疑问，但这是一句正常正文，不能被误删。</p>
            </div>
            """,
            retrievalKind: .urlSession
        )

        let chapter = try GenericNovelAdapter().parseChapterPage(document)

        #expect(chapter.paragraphs.count == 3)
        #expect(!chapter.paragraphs.contains { $0.hasPrefix("上一章：") })
        #expect(!chapter.paragraphs.contains { $0.hasPrefix("下一章：") })
        #expect(!chapter.paragraphs.contains { $0.contains("转/码阅读") })
        #expect(!chapter.paragraphs.contains { $0 == "上一章 | 章节目录 | 下一章" })
        #expect(chapter.paragraphs.contains { $0.contains("上一章留下的疑问") })
        #expect(chapter.previousChapterURL?.absoluteString == "https://reader.example/douluodalu2/29796.html")
        #expect(chapter.nextChapterURL?.absoluteString == "https://reader.example/douluodalu2/29798.html")
    }

    @Test
    func recognizesCloudflareChallenge() {
        #expect(HTMLChallengeDetector.isChallenge("<title>Just a moment...</title><div class='cf-chl-test'></div>"))
        #expect(!HTMLChallengeDetector.isChallenge("<html><article>普通正文</article></html>"))
    }

    @Test
    func catalogPreservesDOMOrderWhenChapterNumbersRestart() throws {
        let url = try #require(URL(string: "https://example.com/book/"))
        let document = LoadedHTML(
            requestedURL: url,
            finalURL: url,
            html: """
            <h1>顺序测试</h1>
            <nav class="chapters">
                <a href="main-1.html">第1章 正文一</a>
                <a href="main-2.html">第2章 正文二</a>
                <a href="extra-1.html">第1章 番外一</a>
                <a href="extra-2.html">第2章 番外二</a>
            </nav>
            """,
            retrievalKind: .urlSession
        )

        let result = try GenericNovelAdapter().parseCatalogPage(document)

        #expect(result.chapters.map(\.title) == [
            "第1章 正文一", "第2章 正文二", "第1章 番外一", "第2章 番外二"
        ])
        #expect(result.chapters.map(\.sortIndex) == [1, 2, 3, 4])
    }

    @Test
    func catalogCombinesSiblingVolumesInDOMOrder() throws {
        let url = try #require(URL(string: "https://example.com/book/"))
        let document = LoadedHTML(
            requestedURL: url,
            finalURL: url,
            html: """
            <h1>多卷测试</h1>
            <section class="volume-list">
                <h2>第一卷</h2>
                <ul>
                    <li><a href="v1-1.html">第1章 第一卷一</a></li>
                    <li><a href="v1-2.html">第2章 第一卷二</a></li>
                </ul>
            </section>
            <section class="volume-list">
                <h2>第二卷</h2>
                <ul>
                    <li><a href="v2-1.html">第1章 第二卷一</a></li>
                    <li><a href="v2-2.html">第2章 第二卷二</a></li>
                </ul>
            </section>
            """,
            retrievalKind: .urlSession
        )

        let result = try GenericNovelAdapter().parseCatalogPage(document)

        #expect(result.chapters.map(\.title) == [
            "第1章 第一卷一", "第2章 第一卷二", "第1章 第二卷一", "第2章 第二卷二"
        ])
        #expect(result.chapters.map(\.sortIndex) == [1, 2, 3, 4])
    }
}
