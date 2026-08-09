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
}
