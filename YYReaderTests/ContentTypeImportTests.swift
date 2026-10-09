import Foundation
import CryptoKit
import SwiftData
import Testing
@testable import YYReader

@MainActor
struct ContentTypeImportTests {
    private let first = URL(string: "https://example.com/comic/test/1.html")!
    private let second = URL(string: "https://example.com/comic/test/2.html")!
    private let catalog = URL(string: "https://example.com/comic/test/")!
    private let text = String(repeating: "这是一段自造的测试正文，用来验证文本解析和类型选择，不含真实作品内容。", count: 4)

    private func document(_ html: String, at url: URL? = nil) -> LoadedHTML {
        let url = url ?? first
        return LoadedHTML(requestedURL: url, finalURL: url, html: html, retrievalKind: .urlSession)
    }
    private func chapter(_ number: Int) -> String {
        """
        <h1>第\(number)话 测试</h1><meta property="og:book_name" content="测试漫画">
        <div class="reading-content"><img data-src="/pages/\(number)-1.png" src="/loading.gif">
        <img data-original="//cdn.example.com/\(number)-2.jpg"><img src="/pages/\(number)-1.png"></div>
        <a href="/comic/test/">目录</a>
        """
    }
    private var catalogHTML: String {
        """
        <h1>测试漫画</h1><div class="chapter-list"><a href="1.html">第1话 开始</a>
        <a href="2.html">第1话 新卷</a><a href="1.html">重复第1话</a></div>
        """
    }

    @Test func genericMangaKeepsLazyImageOrderAndFiltersNoise() throws {
        let html = """
        <h1>第1话 测试</h1><img src="/outside.jpg"><div class="comic-content"><img src="/loading.gif" data-src="/pages/a.jpg">
        <img data-original="//cdn.example.com/b.jpg#duplicate"><img src="//cdn.example.com/b.jpg"><img src="/logo.png">
        <img class="cover" src="/large.jpg"><img width="100" height="140" src="/small.jpg">
        <div class="ads"><img src="/advertising.jpg"></div><img src="data:image/png,xxx"></div>
        """
        let page = try GenericMangaAdapter().parseChapterPage(document(html))
        #expect(page.imageURLs.count == 2)
        #expect(page.imageURLs.map(\.absoluteString) == ["https://example.com/pages/a.jpg", "https://cdn.example.com/b.jpg"])
        #expect(!page.imageURLs.contains { $0.path.contains("logo") || $0.path.contains("outside") || $0.path.contains("small") })
        #expect(page.paragraphs.isEmpty)
    }

    @Test func genericMangaRejectsGalleryAdsAndAmbiguousSingleImage() throws {
        for html in ["<h1>新闻</h1><img src='/1.jpg'><img src='/2.jpg'>",
                     "<h1>第1话</h1><div id='reader'><img src='/1.jpg'></div>",
                     "<article><h1>第1章</h1><p>\(text)</p><img src='/1.jpg'><img src='/2.jpg'><img src='/3.jpg'></article>"] {
            #expect(throws: NovelParsingError.noMangaImages) { try GenericMangaAdapter().parseChapterPage(document(html)) }
        }
        let large = "<h1>第1话</h1><div id='reader'><img width='800' height='1200' src='/page.jpg'></div>"
        #expect(try GenericMangaAdapter().parseChapterPage(document(large)).imageURLs.count == 1)
    }

    @Test func requestedModesChooseTextOrImagesWhileAutomaticRemainsText() async throws {
        let mixed = chapter(1) + "<div id='content'><p>\(text)</p></div>"
        let registry = NovelParserRegistry()
        let novel = try await registry.parseChapterPage(document(mixed), contentType: .novel)
        let manga = try await registry.parseChapterPage(document(mixed), contentType: .manga)
        let automatic = try await registry.parseChapterPage(document(mixed))
        #expect(novel.imageURLs.isEmpty && !novel.paragraphs.isEmpty)
        #expect(manga.paragraphs.isEmpty && manga.imageURLs.count == 2)
        #expect(automatic.imageURLs.isEmpty && automatic.paragraphs == novel.paragraphs)
        #expect(await registry.dataURL(for: URL(string: "https://manhua.zaimanhua.com/view/test/7/22")!, contentType: .novel) == nil)
    }

    @Test func catalogImportAndRefreshKeepRequestedMangaModeAndDOMOrder() async throws {
        let loader = MockHTMLLoader(documents: [catalog: catalogHTML, first: chapter(1), second: chapter(2)])
        let coordinator = NovelImportCoordinator(loader: loader)
        let result = try await coordinator.importNovel(from: catalog, contentType: .manga)
        #expect(result.contentType == .manga && result.imageURLs.count == 2 && result.bodyText.isEmpty)
        #expect(result.catalog.map(\.url) == [first, second])
        let refreshed = try await coordinator.refreshCatalog(from: catalog, contentType: result.contentType)
        #expect(refreshed.chapters.map(\.title) == ["第1话 开始", "第1话 新卷"])
        let next = try await coordinator.loadChapterContent(from: second, contentType: result.contentType)
        #expect(next.imageURLs.first?.path == "/pages/2-1.png")
    }

    @Test func mangaPaginationDeduplicatesImagesAndInsufficientEvidenceFails() async throws {
        let pagination = URL(string: "https://example.com/comic/test/1-2.html")!
        let loader = MockHTMLLoader(documents: [first: chapter(1) + "<a href='1-2.html'>下一页</a>", pagination: chapter(1)])
        let result = try await NovelImportCoordinator(loader: loader).loadChapterContent(from: first, contentType: .manga)
        #expect(result.imageURLs.count == 2)
        #expect(loader.requestedURLs == [first, pagination])
        let bad = NovelImportCoordinator(loader: MockHTMLLoader(documents: [first: "<img src='/logo.jpg'>"]))
        await #expect(throws: NovelParsingError.noMangaImages) { try await bad.importNovel(from: first, contentType: .manga) }
        await #expect(throws: NovelParsingError.noReadableContent) {
            try await NovelProcessingWorker().aggregateChapterPages([
                ParsedChapterPage(title: "空章节", bookTitle: nil, author: nil, paragraphs: [], catalogURL: nil,
                                  previousChapterURL: nil, nextChapterURL: nil, nextPageURL: nil)
            ], sourceURL: first)
        }
    }

    @Test func manhuazhanUsesCompletePublicListRatherThanLazyViewportImages() async throws {
        let url = URL(string: "https://www.manhuazhan.com/chapter/12-34.html")!
        let html = """
        <h1>第01话</h1><div class="bread-crumbs"><a href="/comic/12">测试漫画</a></div>
        <div id="ChapterContent"><img src="/lazyload.gif"><img src="https://cdn.example.com/2.jpg"></div>
        <script id="yyreader-manga-images" type="application/json">{"imageURLs":["https://cdn.example.com/1.jpg","https://cdn.example.com/2.jpg","https://cdn.example.com/3.jpg","https://cdn.example.com/2.jpg"]}</script>
        """
        let page = try await NovelParserRegistry().parseChapterPage(document(html, at: url), contentType: .manga)
        #expect(page.imageURLs.map(\.lastPathComponent) == ["1.jpg", "2.jpg", "3.jpg"])
        #expect(page.catalogURL?.path == "/comic/12" && page.bookTitle == "测试漫画")
        let catalog = try ManhuazhanMangaAdapter().parseCatalogPage(document("<h1>测试漫画</h1><ul id='playlist'><li><a href='/chapter/12-34.html'>第01话</a></li><li><a href='/chapter/12-35.html'>第02话</a></li></ul>", at: URL(string: "https://www.manhuazhan.com/comic/12")!))
        #expect(catalog.chapters.count == 2)
    }

    @Test func preferencesPersistAndEmptyOrIncompatibleChaptersAreNotCached() throws {
        let directory = URL.temporaryDirectory.appending(path: "ContentTypes-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let configuration = ModelConfiguration(url: directory.appending(path: "library.store"))
        var id: UUID!
        do {
            let container = try ModelContainer(for: Book.self, Chapter.self, configurations: configuration)
            let book = Book(title: "类型持久化", author: "测试", sourceHost: "example.com", catalogURL: catalog.absoluteString)
            #expect(book.preferredContentType == .auto)
            book.importContentType = "manga"; book.resolvedContentType = "manga"
            let empty = Chapter(sourceURL: first.absoluteString, title: "未加载", sortIndex: 1, cachedAt: .now)
            book.chapters = [empty]; empty.book = book
            container.mainContext.insert(book)
            #expect(!empty.isCached && !empty.isAvailableOffline)
            empty.replaceBodyText(text)
            #expect(!empty.isCached && !empty.isAvailableOffline)
            empty.replaceImages([URL(string: "https://cdn.example.com/page.png")!])
            #expect(empty.isCached && !empty.isAvailableOffline)
            empty.imagesCachedAt = .now
            #expect(empty.isAvailableOffline)
            book.importContentType = "novel"
            #expect(!empty.isCached && !empty.isAvailableOffline)
            book.importContentType = "manga"
            id = book.id
            try container.mainContext.save()
        }
        let reopened = try ModelContainer(for: Book.self, Chapter.self, configurations: configuration)
        let book = try #require(reopened.mainContext.fetch(FetchDescriptor<Book>()).first { $0.id == id })
        #expect(book.preferredContentType == .manga && book.isManga)
        #expect(book.chapters.first?.imageSourceURLs.count == 1)
    }

    @Test func storeUsesPersistedPreferenceForUncachedChapterAndCatalogRefresh() async throws {
        let container = try ModelContainer(for: Book.self, Chapter.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let loader = MockHTMLLoader(documents: [catalog: catalogHTML, first: chapter(1), second: chapter(2)])
        let store = LibraryStore(modelContext: container.mainContext, coordinator: NovelImportCoordinator(loader: loader))
        store.startImportURL(catalog.absoluteString, contentType: .manga)
        while store.canCancelLoading || store.isLoading { try await Task.sleep(for: .milliseconds(10)) }
        let book = try #require(store.selectedBook)
        #expect(book.preferredContentType == .manga && book.isManga)
        let next = try #require(book.chapters.first { $0.sourceURL == second.absoluteString })
        store.selectChapter(next.id)
        await store.ensureSelectedChapterLoaded()
        #expect(next.isManga && next.isCached)
        await store.refreshSelectedCatalog()
        #expect(store.presentedError == nil && book.preferredContentType == .manga)
    }

    @Test func offlineDownloadsUseSavedMangaPreferenceWithoutLiveImageRequests() async throws {
        let directory = URL.temporaryDirectory.appending(path: "TypedDownload-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bytes = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAIAAAADCAIAAAA2iEnWAAAAEElEQVR4nGMomLAAiBhQKABlVQnBJBo8DwAAAABJRU5ErkJggg==")!
        for address in ["https://example.com/pages/1-1.png", "https://cdn.example.com/1-2.jpg"] {
            let name = SHA256.hash(data: Data(address.utf8)).map { String(format: "%02x", $0) }.joined()
            try bytes.write(to: directory.appending(path: name))
        }
        let container = try ModelContainer(for: Book.self, Chapter.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let book = Book(title: "下载测试", author: "测试", sourceHost: "example.com", catalogURL: catalog.absoluteString)
        book.importContentType = "manga"
        let chapter = Chapter(sourceURL: first.absoluteString, title: "第1话", sortIndex: 1)
        book.chapters = [chapter]; chapter.book = book
        container.mainContext.insert(book)
        let downloads = OfflineDownloadManager(modelContext: container.mainContext,
            coordinator: NovelImportCoordinator(loader: MockHTMLLoader(documents: [first: self.chapter(1)])),
            imageCache: MangaImageCache(directory: directory))
        downloads.start(book: book, currentChapter: chapter, scope: .currentChapter)
        while downloads.isDownloading { try await Task.sleep(for: .milliseconds(10)) }
        #expect(downloads.failedCount == 0)
        #expect(chapter.imageSourceURLs.count == 2 && chapter.isAvailableOffline)
        #expect(book.preferredContentType == .manga && book.isManga)
    }

    @Test func explicitNextChapterWinsOverDescendingComicCatalogOrder() async throws {
        let descending = "<h1>测试漫画</h1><div class='chapter-list'><a href='2.html'>第2话</a><a href='1.html'>第1话</a></div>"
        let loader = MockHTMLLoader(documents: [first: chapter(1) + "<a href='2.html'>下一话</a>", catalog: descending, second: chapter(2)])
        let container = try ModelContainer(for: Book.self, Chapter.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = LibraryStore(modelContext: container.mainContext, coordinator: NovelImportCoordinator(loader: loader))
        store.startImportURL(first.absoluteString, contentType: .manga)
        while store.canCancelLoading || store.isLoading { try await Task.sleep(for: .milliseconds(10)) }
        #expect(store.selectedChapter?.sourceURL == first.absoluteString)
        store.goToNextChapter()
        #expect(store.selectedChapter?.sourceURL == second.absoluteString)
    }

    @Test func comicNextPageLinkToAnotherChapterDoesNotMergeChapters() async throws {
        let loader = MockHTMLLoader(documents: [first: chapter(1) + "<a href='2.html'>下一页</a>", second: chapter(2)])
        let result = try await NovelImportCoordinator(loader: loader).loadChapterContent(from: first, contentType: .manga)
        #expect(result.imageURLs.count == 2 && result.nextChapterURL == second)
    }
}
