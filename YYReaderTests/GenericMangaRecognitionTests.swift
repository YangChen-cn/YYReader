import Foundation
import Testing
@testable import YYReader

struct GenericMangaRecognitionTests {
    @Test func dingCatalogDetectsDescendingOrderWithoutSortingExtras() throws {
        let url = URL(string: "https://www.dingmanhua.com/comic/1919.html/")!
        for (titles, expected) in [
            (["总697·新话", "临时公告", "总696·上", "总696·下", "总695·旧话"], ["总695·旧话", "总696·下", "总696·上", "临时公告", "总697·新话"]),
            (["总695·旧话", "公告", "总696·上", "总697·新话"], ["总695·旧话", "公告", "总696·上", "总697·新话"])
        ] {
            let links = titles.enumerated().map { "<a href='/chapter/1919-\($0.offset).html'>\($0.element)</a>" }.joined()
            let html = "<h1>测试漫画</h1><div class='chapters-grid'>\(links)</div>"
            let document = LoadedHTML(requestedURL: url, finalURL: url, html: html, retrievalKind: .urlSession)
            let catalog = try GenericMangaAdapter().parseCatalogPage(document).inReadingOrder()
            #expect(catalog.chapters.map(\.title) == expected)
            #expect(catalog.chapters.map(\.sortIndex) == Array(1...titles.count))
        }
    }


    private let url = URL(string: "https://example.com/episodes/12")!
    private let navigation = "<a href='/episodes/13'>下一话</a><a href='/series/test'>目录</a>"
    private func loaded(_ html: String) -> LoadedHTML {
        LoadedHTML(requestedURL: url, finalURL: url, html: html, retrievalKind: .urlSession)
    }
    private func sequence(_ count: Int, sized: Bool = true, wrappers: Bool = false) -> String {
        (1...count).map { index in
            let image = "<img \(sized ? "width='800' height='1200'" : "") data-src='/pages/\(index).webp' src='/loading.gif'>"
            return wrappers ? "<figure><picture>\(image)</picture></figure>" : image
        }.joined()
    }

    @Test func unknownContainerWithStrongSequenceIsAutomaticallyRecognized() async throws {
        let html = "<h1>第12话</h1><div class='unfamiliar-xyz'>\(sequence(18))</div>" + navigation
        let detected = try GenericMangaAdapter().recognizeChapter(loaded(html))
        let recognition = try #require(detected)
        #expect(recognition.isHighConfidence && recognition.evidence.score >= 80)
        #expect(recognition.imageURLs.count == 18)
        let page = try await NovelParserRegistry().parseChapterPage(loaded(html))
        #expect(page.imageURLs == recognition.imageURLs && page.paragraphs.isEmpty)
        await #expect(throws: NovelParsingError.noReadableContent) {
            try await NovelParserRegistry().parseChapterPage(loaded(html), contentType: .novel)
        }
    }

    @Test func nestedPageWrappersAndDifferentDimensionsRemainValid() throws {
        let pages = sequence(8, wrappers: true) + "<figure><img width='1600' height='900' src='/spread.jpg'></figure><figure><img data-width='700' data-height='6000' src='/strip.jpg'></figure>"
        let html = "<h1>第12话</h1><section class='unknown'>\(pages)</section>" + navigation
        let page = try GenericMangaAdapter().parseChapterPage(loaded(html), requiringHighConfidence: true)
        #expect(page.imageURLs.count == 10 && page.imageURLs.last?.path == "/strip.jpg")
    }

    @Test func singleLongStripNeedsSizeAndChapterContext() async throws {
        let html = "<h1>第12话</h1><section class='manga-pages'><img width='800' height='12000' src='/strip.jpg'></section>" + navigation
        #expect(try await NovelParserRegistry().parseChapterPage(loaded(html)).imageURLs.count == 1)
        for dimensions in ["", "width='800' height='1200'", "width='120' height='12000'"] {
            let weak = "<h1>第12话</h1><div id='reader'><img \(dimensions) src='/one.jpg'></div>"
            #expect(throws: NovelParsingError.noMangaImages) {
                try GenericMangaAdapter().parseChapterPage(loaded(weak), requiringHighConfidence: true)
            }
        }
    }

    @Test func manualChoiceCanAcceptShortSequenceWithoutAutomaticFalsePositive() async throws {
        let html = "<h1>第12话</h1><div class='reading-content'>\(sequence(2, sized: false))</div>"
        let detected = try GenericMangaAdapter().recognizeChapter(loaded(html))
        let recognition = try #require(detected)
        #expect(!recognition.isHighConfidence)
        #expect(try await NovelParserRegistry().parseChapterPage(loaded(html), contentType: .manga).imageURLs.count == 2)
        await #expect(throws: NovelParsingError.noReadableContent) { try await NovelParserRegistry().parseChapterPage(loaded(html)) }
    }

    @Test func lazyAddressesNoiseDuplicatesAndQueriesPreserveSequence() throws {
        let html = """
        <h1>第12话</h1><div id='reader'>
        <img width='1' height='1' src='/pixel.gif'><img data-lazy-src='/pages/a.jpg?token=1#x' src='/placeholder.svg'>
        <span class='chapter-image loading'><img class='lazyload entered loading' data-original='/pages/b.jpg'></span><img src='/pages/a.jpg?token=1'><img src='/pages/a.jpg?token=2'>
        <span class='ad-block'><img width='800' height='1200' src='/evil.jpg'></span>
        <img alt='封面' src='/cover.jpg'><img src='blob:bad'><img src='javascript:bad'>
        </div>
        """
        let page = try GenericMangaAdapter().parseChapterPage(loaded(html))
        #expect(page.imageURLs.map(\.absoluteString) == ["https://example.com/pages/a.jpg?token=1", "https://example.com/pages/b.jpg", "https://example.com/pages/a.jpg?token=2"])
    }

    @Test func recommendationCardsDoNotBecomeMangaEvenWithLargeImages() throws {
        let cards = (1...18).map { "<div><a href='/books/\($0)'><img width='800' height='1200' src='/books/\($0).jpg'><span>另一本作品 \($0)</span></a></div>" }.joined()
        let html = "<h1>第12话</h1><div class='comic-grid'>\(cards)</div>" + navigation
        #expect(throws: NovelParsingError.noMangaImages) { try GenericMangaAdapter().parseChapterPage(loaded(html)) }
    }

    @Test func proseAndInterleavedCaptionsLowerConfidence() throws {
        let story = String(repeating: "自造文章正文，文字和插图组成普通文章。", count: 30)
        let html = "<h1>第12话</h1><article>\(sequence(18))<p>\(story)</p></article>" + navigation
        #expect(throws: NovelParsingError.noMangaImages) { try GenericMangaAdapter().parseChapterPage(loaded(html)) }
        let gallery = (1...18).map { "<figure><img width='800' height='1200' src='/\($0).jpg'><figcaption>\(String(repeating: "图片介绍内容", count: 6))</figcaption></figure>" }.joined()
        #expect(throws: NovelParsingError.noMangaImages) {
            try GenericMangaAdapter().parseChapterPage(loaded("<h1>第12话</h1><article>\(gallery)</article>" + navigation))
        }
    }

    @Test func neverTreatsBodyCollectionOrUnrelatedPhotoGalleryAsReader() throws {
        for html in ["<h1>第12话</h1>\(sequence(18))" + navigation,
                     "<h1>旅途摄影</h1><section>\(sequence(18))</section><a rel='next' href='/photo/2'>下一页</a>"] {
            #expect(throws: NovelParsingError.noMangaImages) { try GenericMangaAdapter().parseChapterPage(loaded(html)) }
        }
    }

    @Test func validNovelProseWinsOverMangaHints() async throws {
        let prose = String(repeating: "这是自造的小说段落，主角在山间行走并记录旅途见闻。", count: 10)
        let html = "<h1>第12话</h1><div id='content'><p>\(prose)</p></div><section class='reader-images'>\(sequence(18))</section>" + navigation
        let page = try await NovelParserRegistry().parseChapterPage(loaded(html))
        #expect(page.imageURLs.isEmpty && page.paragraphs.joined().contains("自造的小说"))
    }

    @Test func navigationTextIsNotTrustworthyNovelProse() async throws {
        let links = (1...3).map { "<a href='/menu/\($0)'>\(String(repeating: "菜单说明", count: 10))</a>" }.joined()
        let html = "<h1>第12话</h1><div id='content'>\(links)</div><section class='reader-images'>\(sequence(18))</section>" + navigation
        #expect(try await NovelParserRegistry().parseChapterPage(loaded(html)).imageURLs.count == 18)
    }

    @Test func finalNovelFallbackStillRequiresNonLinkProse() async throws {
        let links = (1...3).map { "<a href='/menu/\($0)'>\(String(repeating: "菜单说明", count: 10))</a><br><br><br>" }.joined()
        let html = "<h1>第12章</h1><div id='content'>\(links)</div>"
        #expect(try GenericNovelAdapter().parseChapterPage(loaded(html)).paragraphs.count == 3)
        await #expect(throws: NovelParsingError.noReadableContent) {
            try await NovelParserRegistry().parseChapterPage(loaded(html))
        }
        let prose = String(repeating: "他沿着山路继续前行，远处的灯火在雨中逐渐变得清晰。", count: 8)
        let page = try await NovelParserRegistry().parseChapterPage(loaded(
            "<h1>第12章</h1><div id='content'><p>\(prose)</p>\(links)</div>"))
        #expect(page.imageURLs.isEmpty && page.paragraphs.contains(prose))
    }

    @Test func repeatedImageLoadingControlsAreNotNovelBody() async throws {
        let controls = (1...18).map { _ in "<div><p>100%</p><span>加载失败， 点击重试</span><p>0%</p><span>正在加载图片， 请稍候</span></div>" }.joined()
        let html = "<h1>001</h1><div id='content'>\(controls)</div>" + navigation
        await #expect(throws: NovelParsingError.noReadableContent) {
            try await NovelParserRegistry().parseChapterPage(loaded(html))
        }
        #expect(throws: NovelParsingError.noReadableContent) { try GenericNovelAdapter().parseChapterPage(loaded(html)) }
        let reader = (1...18).map { index in
            "<div><img width='800' height='1200' src='/pages/\(index).jpg'><p>100%</p><span>加载失败，点击重试</span></div>"
        }.joined()
        let manga = try await NovelParserRegistry().parseChapterPage(loaded("<h1>001</h1><div class='chapter-images'>\(reader)</div>" + navigation))
        #expect(manga.imageURLs.count == 18 && manga.paragraphs.isEmpty)
        let prose = String(repeating: "他看见屏幕显示加载失败，点击重试，却依旧没有找到任何线索。", count: 5)
        let novel = try GenericNovelAdapter().parseChapterPage(loaded("<h1>第1章</h1><div id='content'><p>\(prose)</p></div>"))
        #expect(novel.paragraphs == [prose])
    }

    @Test(arguments: ["reader-images", "chapter-images", "comic-content", "viewer", "unfamiliar"])
    func renderedReaderShapesWorkWithoutHostRules(_ identity: String) throws {
        let html = "<h1>001</h1><div class='\(identity)'>\(sequence(18))</div>" + navigation
        #expect(try GenericMangaAdapter().parseChapterPage(loaded(html), requiringHighConfidence: true).imageURLs.count == 18)
    }

    @Test func genericNumericCatalogKeepsDOMOrderAndQueryIdentity() throws {
        let html = "<h1>自造漫画</h1><div class='chapter-list'><a href='/chapter?id=2'>002·下</a><a href='/chapter?id=1'>001</a><a href='/chapter?id=2'>002·下</a></div>"
        let catalog = try GenericMangaAdapter().parseCatalogPage(loaded(html))
        #expect(catalog.chapters.map(\.title) == ["002·下", "001"])
        #expect(catalog.chapters.map { $0.url.query } == ["id=2", "id=1"])
    }

    @Test func largeImageRatioUsesAllCandidatesAndContinuityIsIndependent() throws {
        let full = "<h1>第12话</h1><div class='unknown'>\(sequence(18))</div>" + navigation
        let partial = "<h1>第12话</h1><div class='unknown'><img width='800' height='1200' src='/sized.jpg'>\(sequence(17, sized: false))</div>" + navigation
        let fullResult = try GenericMangaAdapter().recognizeChapter(loaded(full))
        let partialResult = try GenericMangaAdapter().recognizeChapter(loaded(partial))
        let strong = try #require(fullResult)
        let weak = try #require(partialResult)
        #expect(strong.evidence.imageQuality > weak.evidence.imageQuality)
        #expect(strong.evidence.structure == weak.evidence.structure)
        #expect(!weak.isHighConfidence)
        let interleaved = (1...8).map { "<img width='800' height='1200' src='/\($0).jpg'><span>\(String(repeating: "说明文字", count: 8))</span>" }.joined()
        #expect(throws: NovelParsingError.noMangaImages) {
            try GenericMangaAdapter().parseChapterPage(loaded("<h1>第12话</h1><div>\(interleaved)</div>" + navigation), requiringHighConfidence: true)
        }
    }

    @Test func naturalImageDimensionsOverrideScaledHTMLPresentation() throws {
        let pages = (1...23).map { "<div class='chapter-image loading'><img class='lazyload entered loading' width='200' height='300' src='https://cdn.example.com/pages/\($0).jpg' data-yyreader-width='800' data-yyreader-height='1200'></div>" }.joined()
        let html = "<h1>001</h1><div class='chapter-images'>\(pages)</div>" + navigation
        let page = try GenericMangaAdapter().parseChapterPage(loaded(html), requiringHighConfidence: true)
        #expect(page.title == "001" && page.imageURLs.count == 23)
        #expect(page.imageURLs.first?.path == "/pages/1.jpg" && page.imageURLs.last?.path == "/pages/23.jpg")
    }

    @Test func equallyStrongDisjointRegionsAreAmbiguousRatherThanMerged() throws {
        let first = sequence(8)
        let second = sequence(8).replacingOccurrences(of: "/pages/", with: "/other/")
        let html = "<h1>第12话</h1><main><section>\(first)</section><section>\(second)</section></main>" + navigation
        #expect(throws: NovelParsingError.noMangaImages) { try GenericMangaAdapter().parseChapterPage(loaded(html)) }
    }

    @Test func automaticComicCatalogIncludesNumericAndNamedEpisodes() async throws {
        let html = "<title>自造漫画在线阅读</title><h1>自造漫画</h1><div class='chapter-list'><a href='/chapter/a'>001</a><a href='/chapter/b'>特别篇</a><a href='/chapter/c'>第3话</a></div>"
        let catalog = try await NovelParserRegistry().parseCatalogPage(loaded(html))
        #expect(catalog.chapters.map(\.title) == ["001", "特别篇", "第3话"])
    }

    @Test func unfinishedComicCatalogIsNotMarkedComplete() throws {
        let list = "<h1>自造漫画</h1><div class='chapters-grid'><a href='/chapter/a'>001</a><a href='/chapter/b'>002</a></div>"
        #expect(throws: NovelParsingError.catalogNeedsExpansion) {
            try GenericMangaAdapter().parseCatalogPage(loaded(list + "<button type='button'>加载更多章节</button>"))
        }
        let done = try GenericMangaAdapter().parseCatalogPage(loaded(list + "<button style='display: none'>加载更多章节</button>"))
        #expect(done.chapters.count == 2)
    }

    @Test func automaticImportUsesGenericMangaChapterAndSavedAutomaticPreference() async throws {
        let chapterHTML = "<h1>第12话</h1><div class='unfamiliar'>\(sequence(18))</div>" + navigation
        let catalogURL = URL(string: "https://example.com/series/test")!
        let catalogHTML = "<h1>自造漫画</h1><div class='chapter-list'><a href='/episodes/12'>第12话</a><a href='/episodes/13'>第13话</a></div>"
        let result = try await NovelImportCoordinator(loader: MockHTMLLoader(documents: [url: chapterHTML, catalogURL: catalogHTML])).importNovel(from: url)
        #expect(result.contentType == .auto && result.imageURLs.count == 18 && result.bodyText.isEmpty)
        #expect(result.catalog.count == 2 && result.chapterURL == url)
    }
}
