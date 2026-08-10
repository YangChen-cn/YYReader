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
