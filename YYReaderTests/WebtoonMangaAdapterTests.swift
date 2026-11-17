import Foundation
import Testing
@testable import YYReader

struct WebtoonMangaAdapterTests {
    private let base = "https://www.webtoons.com/zh-hant/thriller/sample"

    @Test func importsViewerWithOrderedReaderImagesAndNeighbors() async throws {
        let url = try #require(URL(string: base + "/sample/viewer?title_no=42&episode_no=10"))
        let document = LoadedHTML(requestedURL: url, finalURL: url, html: """
            <div class="subj_info"><a class="subj" href="../../sample/list?title_no=42">測試漫畫</a></div>
            <h1 class="subj_episode">第8話</h1>
            <a class="_prevEpisode" href="viewer?title_no=42&episode_no=9">上一集</a>
            <a class="_nextEpisode" href="viewer?title_no=42&episode_no=11">下一集</a>
            <img class="_images" data-url="https://example.com/thumbnail.png">
            <div id="_imageList">
              <img class="_images" src="https://example.com/bg_transparency.png" data-url="https://example.com/p2.png?type=opti">
              <img class="_images" data-url="https://example.com/p2.png?type=opti">
              <img class="_images" src="https://example.com/p1.png">
              <img class="_images" src="https://example.com/bg_transparency.png">
            </div>
            """, retrievalKind: .urlSession)
        let registry = NovelParserRegistry()
        for mode in [BookContentType.auto, .manga] {
            let page = try await registry.parseChapterPage(document, contentType: mode)
            #expect(page.title == "第8話")
            #expect(page.bookTitle == "測試漫畫")
            #expect(page.catalogURL?.lastPathComponent == "list")
            #expect(page.imageURLs.map(\.absoluteString) == ["https://example.com/p2.png?type=opti", "https://example.com/p1.png"])
            #expect(page.previousChapterURL?.query?.contains("episode_no=9") == true)
            #expect(page.nextChapterURL?.query?.contains("episode_no=11") == true)
            #expect(page.nextPageURL == nil)
        }
    }

    @Test func followsAdjacentCatalogPageInsteadOfJumpingPageGroup() throws {
        let url = try #require(URL(string: base + "/list?title_no=42"))
        let document = LoadedHTML(requestedURL: url, finalURL: url, html: """
            <h1 class="subj">測試漫畫</h1>
            <div class="author_area">作者甲<button>作家資訊</button></div>
            <ul id="_listUl">
              <li class="_episodeItem"><a href="b/viewer?title_no=42&episode_no=3"><span class="subj">第3話</span></a></li>
              <li class="_episodeItem"><a href="b/viewer?title_no=42&episode_no=2"><span class="subj">第2話</span></a></li>
              <li class="_episodeItem"><a href="b/viewer?title_no=42&episode_no=1"><span class="subj">第1話</span></a></li>
              <li class="_episodeItem"><a href="b/viewer?title_no=43&episode_no=99"><span class="subj">其他漫畫</span></a></li>
            </ul>
            <div class="paginate">
              <a class="pg_next" href="list?title_no=42&page=11">下一頁</a>
              <a class="pg_page" href="list?title_no=42&page=2">2</a>
            </div>
            """, retrievalKind: .urlSession)
        let catalog = try WebtoonMangaAdapter().parseCatalogPage(document)
        #expect(catalog.author == "作者甲")
        #expect(catalog.inReadingOrder().chapters.map(\.title) == ["第1話", "第2話", "第3話"])
        #expect(catalog.nextPageURL?.query?.contains("page=2") == true)
    }
}
