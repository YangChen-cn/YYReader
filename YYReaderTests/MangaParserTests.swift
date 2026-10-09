import CryptoKit
import Foundation
import SwiftData
import Testing
#if os(macOS)
import AppKit
import SwiftUI

// Hosted tests cannot activate the app. Model a key window while using the
// real NSHostingView, event bridge and NSWindow responder dispatch.
@MainActor
private final class MangaKeyboardTestWindow: NSWindow {
    override var isKeyWindow: Bool { true }
}
#endif
@testable import YYReader

@MainActor
struct MangaParserTests {
    private let chapterURL = URL(string: "https://www.guazimanhua.com/chapter.php?id=101")!
    private let catalogURL = URL(string: "https://www.guazimanhua.com/comic.php?id=12")!
    private let chapterHTML = #"""
    <script type="application/ld+json">{"@graph":[{"@type":"Article","name":"第2话 自造故事","author":{"name":"自造作者"},"isPartOf":{"name":"测试漫画","url":"/comic.php?id=12"}}]}</script>
    <img src="https://example.com/ad.png">
    <div data-reader-images><img src="//images.example.com/2.webp"><img src="/pages/3.jpg"><img src="/pages/3.jpg"><img src="javascript:bad"></div>
    <a href="/chapter.php?id=100">上一话</a><a href="/chapter.php?id=102">下一话</a>
    """#
    private let catalogHTML = #"""
    <script type="application/ld+json">{"@graph":[{"@type":"ComicStory","name":"测试漫画","author":{"name":"自造作者"}},{"@type":"ItemList","itemListElement":[{"name":"第1话 开始","url":"/chapter.php?id=100"},{"name":"番外","url":"/chapter.php?id=101"},{"name":"第1话 新卷","url":"/chapter.php?id=102"},{"name":"重复","url":"/chapter.php?id=101"}]}]}</script>
    """#

    @Test func imageOnlyChapterImportsWithoutTextAndKeepsQueryIDs() async throws {
        let loader = MockHTMLLoader(documents: [chapterURL: chapterHTML, catalogURL: catalogHTML])
        let result = try await NovelImportCoordinator(loader: loader).importNovel(from: chapterURL)
        #expect(result.bookTitle == "测试漫画")
        #expect(result.author == "自造作者")
        #expect(result.bodyText.isEmpty)
        #expect(result.imageURLs.map(\.absoluteString) == ["https://images.example.com/2.webp", "https://www.guazimanhua.com/pages/3.jpg"])
        #expect(result.catalog.map(\.sortIndex) == [1, 2, 3])
        #expect(result.catalog.map(\.title) == ["第1话 开始", "番外", "第1话 新卷"])
        #expect(result.previousChapterURL?.query == "id=100")
        #expect(result.nextChapterURL?.query == "id=102")
        #expect(loader.requestedURLs == [chapterURL, catalogURL])
        let chapter = Chapter(sourceURL: chapterURL.absoluteString, title: result.chapterTitle, sortIndex: 2)
        chapter.replaceImages(result.imageURLs)
        #expect(chapter.isManga && chapter.isCached)
        #expect(!chapter.isAvailableOffline)
        chapter.imagesCachedAt = .now
        #expect(chapter.isAvailableOffline)
        chapter.replaceImages([])
        #expect(!chapter.isCached && !chapter.isAvailableOffline)
    }

    @Test func guaziUsesCompleteGridInsteadOfStructuredPreview() async throws {
        let html = catalogHTML.replacingOccurrences(of: #",{"name":"番外","url":"/chapter.php?id=101"},{"name":"第1话 新卷","url":"/chapter.php?id=102"},{"name":"重复","url":"/chapter.php?id=101"}"#, with: "") + #"""
        <div data-chapter-list><a href="/chapter.php?id=102">第1话 新卷</a><a href="/chapter.php?id=101">番外</a><a href="/chapter.php?id=100">第1话 开始</a></div>
        """#
        let catalog = try GuaziMangaAdapter().parseCatalogPage(LoadedHTML(requestedURL: catalogURL, finalURL: catalogURL,
                                                                         html: html, retrievalKind: .urlSession))
        #expect(catalog.chapters.map(\.title) == ["第1话 开始", "番外", "第1话 新卷"])
        #expect(catalog.chapters.map(\.sortIndex) == [1, 2, 3])
    }

    @Test func zaiUsesPublicAPIAndPreservesVolumeGroupsAndExtras() async throws {
        let url = URL(string: "https://manhua.zaimanhua.com/view/test/7/22")!
        let catalog = URL(string: "https://manhua.zaimanhua.com/test/")!
        let api = try #require(ZaiMangaAdapter.dataURL(for: url))
        let catalogAPI = try #require(ZaiMangaAdapter.dataURL(for: catalog))
        let loader = MockHTMLLoader(documents: [api: #"{"errno":0,"data":{"chapterInfo":{"title":"第2话","page_url":["https://images.example.com/page.jpg","blob:bad"]}}}"#,
            catalogAPI: #"{"errno":0,"data":{"comicInfo":{"id":7,"comicPy":"test","title":"API漫画","canRead":true,"authorsTagList":[{"tagName":"作者甲"}],"chapterList":[{"data":[{"chapter_id":23,"chapter_title":"番外","chapter_order":30},{"chapter_id":22,"chapter_title":"第2话","chapter_order":20},{"chapter_id":21,"chapter_title":"第1话","chapter_order":10}]},{"data":[{"chapter_id":31,"chapter_title":"第1卷","chapter_order":10}]}]}}}"#])
        let result = try await NovelImportCoordinator(loader: loader).importNovel(from: url)
        #expect(result.chapterURL == url)
        #expect(result.sourceBookURL == catalog)
        #expect(result.imageURLs.count == 1)
        #expect(result.author == "作者甲")
        #expect(result.catalog.map(\.title) == ["第1话", "第2话", "番外", "第1卷"])
        #expect(loader.requestedURLs == [api, catalogAPI])
    }

    @Test func haoduoRenderedImagesExcludeAdsAndBlobURLs() async throws {
        let url = URL(string: "https://www.haoduoman.com/manhua/17/2.html")!
        let html = #"""
        <div class="breadcrumb"><ul><li><a href="/manhua/17">自造漫画</a></li><li><span>第2话</span></li></ul></div>
        <div class="chapter-images"><img src="blob:local"></div><img src="https://example.com/ad.jpg">
        <script id="yyreader-manga-images" type="application/json">{"imageURLs":["https://images.example.com/p1.jpg","https://images.example.com/p2.jpg"]}</script>
        <a class="j-chapter-prev" href="/manhua/17/1.html">上一话</a><a class="j-chapter-next" href="javascript:void(0)">下一话</a>
        """#
        let page = try await NovelParserRegistry().parseChapterPage(LoadedHTML(requestedURL: url, finalURL: url, html: html, retrievalKind: .webKit))
        #expect(page.imageURLs.count == 2)
        #expect(page.title == "第2话")
        #expect(page.bookTitle == "自造漫画")
        #expect(page.previousChapterURL?.path == "/manhua/17/1.html")
        #expect(page.nextChapterURL == nil)
    }

    @Test func haoduoMobileAndDesktopHaveOneBookIdentity() throws {
        let url = URL(string: "https://m.haoduoman.com/manhua/17/2.html")!
        #expect(HaoduoMangaAdapter.canonicalURL(url).absoluteString == "https://www.haoduoman.com/manhua/17/2.html")
        let html = #"""
        <div class="metas-title">漫画甲</div><div class="metas-body"><span class="author">作者：作者甲</span></div>
        <ul class="comic-chapters"><li><a href="/manhua/17/1.html">第1话</a></li><li><a href="/manhua/17/2.html">番外</a></li></ul>
        <a href="/manhua/99/1.html">推荐广告</a>
        """#
        let catalog = try HaoduoMangaAdapter().parseCatalogPage(LoadedHTML(requestedURL: url, finalURL: url, html: html, retrievalKind: .urlSession))
        #expect(catalog.chapters.count == 2)
        #expect(catalog.chapters.allSatisfy { $0.url.host == "www.haoduoman.com" })
        #expect(catalog.author == "作者甲")
    }

    @Test func imageCacheDecodesLocallyAndCanBeRemovedOffline() async throws {
        let directory = URL.temporaryDirectory.appending(path: "YYReaderMangaTest-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = URL(string: "https://invalid.example/pixel.png")!
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4//8/AAX+Av4N70a4AAAAAElFTkSuQmCC")!
        try png.write(to: directory.appending(path: digest))
        let cache = MangaImageCache(directory: directory)
        #expect(await cache.containsAll([url]))
        let image = try await cache.image(at: url, referer: chapterURL)
        #expect(image.aspectRatio == 1)
        #expect(!image.data.isEmpty)
        try await cache.remove([url])
        #expect(!(await cache.containsAll([url])))
    }

    @Test func repeatedDisplayReusesTheDecodedThumbnailAndClearsWithTheCache() async throws {
        let directory = URL.temporaryDirectory.appending(path: "YYReaderMangaThumbTest-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = URL(string: "https://invalid.example/thumb.png")!
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        let file = directory.appending(path: digest)
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4//8/AAX+Av4N70a4AAAAAElFTkSuQmCC")!
        try png.write(to: file)

        let cache = MangaImageCache(directory: directory)
        let first = try await cache.image(at: url, referer: chapterURL)
        #expect(await cache.cachedThumbnailCount == 1)

        // The file is gone, so only the memory cache can serve this page: it must
        // not decode and PNG-encode the same image again on every reappearance.
        try FileManager.default.removeItem(at: file)
        let second = try await cache.image(at: url, referer: chapterURL)
        #expect(second.data == first.data)
        #expect(second.aspectRatio == first.aspectRatio)

        try await cache.remove([url])
        #expect(await cache.cachedThumbnailCount == 0)

        // A cache with no room must still return the page, just without keeping it.
        try png.write(to: file)
        let bounded = MangaImageCache(directory: directory, thumbnailByteLimit: 0)
        _ = try await bounded.image(at: url, referer: chapterURL)
        #expect(await bounded.cachedThumbnailCount == 0)
        try await bounded.removeAll()
        #expect(await bounded.cachedThumbnailCount == 0)
    }

    @Test func prefetchWindowIsTenImagesAcrossChaptersAndDoesNotMarkThemRead() async throws {
        let container = try ModelContainer(for: Book.self, Chapter.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let book = Book(title: "预取漫画", author: "作者", sourceHost: "www.guazimanhua.com", catalogURL: catalogURL.absoluteString)
        let current = Chapter(sourceURL: chapterURL.absoluteString, title: "第1话", sortIndex: 1)
        current.replaceImages([URL(string: "https://images.example.com/current1.jpg")!, URL(string: "https://images.example.com/current2.jpg")!])
        let nextURL = URL(string: "https://www.guazimanhua.com/chapter.php?id=102")!
        let next = Chapter(sourceURL: nextURL.absoluteString, title: "第2话", sortIndex: 2)
        book.chapters = [current, next]
        current.book = book; next.book = book
        container.mainContext.insert(book)
        try container.mainContext.save()
        let html = chapterHTML.replacingOccurrences(of: #"<div data-reader-images>"#, with: #"<div data-reader-images>"# + (1...15).map {
            "<img src=\"https://images.example.com/next\($0).jpg\">"
        }.joined())
        let loader = MockHTMLLoader(documents: [nextURL: html])
        let store = LibraryStore(modelContext: container.mainContext, coordinator: NovelImportCoordinator(loader: loader))
        store.selectBook(book.id)
        let images = try await store.mangaPrefetchImages(after: current, pageIndex: 0)
        #expect(images.count == 10)
        #expect(images.first?.lastPathComponent == "current2.jpg")
        #expect(images.last?.lastPathComponent == "next9.jpg")
        #expect(loader.requestedURLs == [nextURL])
        #expect(next.lastReadAt == nil)
        #expect(!next.isAvailableOffline)
        let sameWindow = try await store.mangaPrefetchImages(after: current, pageIndex: 0)
        #expect(sameWindow == images)
        #expect(loader.requestedURLs.count == 1)
    }

    #if os(macOS)
    @Test func mangaHorizontalReaderRoutesArrowEventsWithoutRequiringImageFocus() async throws {
        let defaults = UserDefaults.standard
        let originalMode = defaults.object(forKey: ReaderPreferenceKeys.pageTurnMode)
        defaults.set(ReaderPageTurnMode.horizontalPages.rawValue, forKey: ReaderPreferenceKeys.pageTurnMode)
        defer {
            if let originalMode { defaults.set(originalMode, forKey: ReaderPreferenceKeys.pageTurnMode) }
            else { defaults.removeObject(forKey: ReaderPreferenceKeys.pageTurnMode) }
        }
        let container = try ModelContainer(for: Book.self, Chapter.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let book = Book(title: "键盘漫画", author: "作者", sourceHost: "www.guazimanhua.com", catalogURL: catalogURL.absoluteString)
        let chapter = Chapter(sourceURL: chapterURL.absoluteString, title: "第1话", sortIndex: 1)
        chapter.replaceImages((0..<3).map { URL(string: "https://invalid.example/keyboard-\($0).png")! })
        book.chapters = [chapter]; chapter.book = book
        container.mainContext.insert(book)
        try container.mainContext.save()
        let store = LibraryStore(modelContext: container.mainContext, coordinator: NovelImportCoordinator(loader: MockHTMLLoader(documents: [:])))
        store.selectBook(book.id)
        let window = MangaKeyboardTestWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 700),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: MangaReaderView(store: store, chapter: chapter))
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        for _ in 0..<50 {
            if window.firstResponder is ReaderKeyboardEventView { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(window.firstResponder is ReaderKeyboardEventView)
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 124))
        window.sendEvent(event)
        for _ in 0..<50 {
            if chapter.topParagraphIndex == 1 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(chapter.topParagraphIndex == 1)
        #expect(chapter.readingProgress == 0.5)
    }
    #endif

    @Test func retentionKeepsCurrentAndUnreadChapterAndRemovesOldReadImages() async throws {
        let directory = URL.temporaryDirectory.appending(path: "YYReaderMangaRetention-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let records = (0..<6).map { index in
            MangaChapterCacheRecord(id: UUID(), imageURLs: [URL(string: "https://images.example.com/\(index).png")!],
                                    lastReadAt: index == 5 ? nil : Date(timeIntervalSince1970: Double(index)))
        }
        for record in records {
            let url = record.imageURLs[0]
            let digest = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
            try Data([1]).write(to: directory.appending(path: digest))
        }
        let cache = MangaImageCache(directory: directory)
        let removed = try await cache.trimReadChapters(records, currentChapterID: records[0].id, maxBytes: 3)
        #expect(Set(removed) == Set(records[1...3].map(\.id)))
        #expect(await cache.containsAll(records[0].imageURLs + records[4].imageURLs + records[5].imageURLs))
        #expect(!(await cache.containsAll(records[1].imageURLs)))
        #expect(try await cache.trimReadChapters(records, currentChapterID: records[0].id, maxBytes: 3).isEmpty)
    }

    @Test func cacheManagementMeasuresAndClearsBooksWithoutDeletingProgressOrTXT() async throws {
        let directory = URL.temporaryDirectory.appending(path: "YYReaderLocalCache-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let imageURL = URL(string: "https://images.example.com/cache-management.png")!
        let digest = SHA256.hash(data: Data(imageURL.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        try Data(repeating: 1, count: 1024).write(to: directory.appending(path: digest))
        let imageCache = MangaImageCache(directory: directory)
        let container = try ModelContainer(for: Book.self, Chapter.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let novel = Book(title: "网页小说", author: "作者", sourceHost: "example.com", catalogURL: "https://example.com/cache-novel/")
        let text = Chapter(sourceURL: "https://example.com/cache-novel/1.html", title: "第1章", sortIndex: 1,
                           bodyText: "自造缓存正文。", cachedAt: .now, topParagraphIndex: 4, readingProgress: 0.4)
        novel.chapters = [text]; text.book = novel; novel.currentChapterID = text.id
        let manga = Book(title: "缓存漫画", author: "作者", sourceHost: "www.guazimanhua.com", catalogURL: catalogURL.absoluteString)
        let page = Chapter(sourceURL: chapterURL.absoluteString, title: "第1话", sortIndex: 1)
        page.replaceImages([imageURL]); page.imagesCachedAt = .now
        manga.chapters = [page]; page.book = manga
        let local = Book(title: "本地TXT", author: "作者", sourceHost: "txt", catalogURL: "yyreader-local://txt/test")
        let original = Chapter(sourceURL: "yyreader-local://txt/test/chapter/1", title: "原始正文", sortIndex: 1, bodyText: "保留本地原始正文", cachedAt: .now)
        local.chapters = [original]; original.book = local
        for book in [novel, manga, local] { container.mainContext.insert(book) }
        try container.mainContext.save()
        let store = LibraryStore(modelContext: container.mainContext, coordinator: NovelImportCoordinator(loader: MockHTMLLoader(documents: [:])))
        store.selectBook(novel.id)
        let summary = try await store.localCacheSummary(imageCache: imageCache)
        #expect(summary.books.count == 2)
        #expect(summary.imageBytes == 1024)
        #expect(summary.totalBytes == 1024 + text.bodyText!.utf8.count)
        try await store.clearLocalCache(bookID: manga.id, imageCache: imageCache)
        #expect(page.imageSourceURLs.isEmpty && !page.isAvailableOffline)
        #expect(text.isCached && original.isCached)
        #expect(store.selectedBookID == novel.id)
        try await store.clearLocalCache(imageCache: imageCache)
        #expect(try await store.localCacheSummary(imageCache: imageCache).totalBytes == 0)
        #expect(store.books.count == 3)
        #expect(store.selectedBookID == nil)
        #expect(!text.isCached && text.topParagraphIndex == 4 && text.readingProgress == 0.4)
        #expect(novel.currentChapterID == text.id)
        #expect(original.bodyText == "保留本地原始正文")
        #expect(store.readerSession.cachedParagraphChapterCount == 0)
    }

    @Test func mangaPagesSurviveSwiftDataAndOfflinePersistence() async throws {
        let container = try ModelContainer(for: Book.self, Chapter.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let chapter = Chapter(sourceURL: chapterURL.absoluteString, title: "漫画", sortIndex: 1)
        container.mainContext.insert(chapter)
        try container.mainContext.save()
        let result = ChapterLoadResult(title: "第2话", bookTitle: nil, author: nil, catalogURL: nil,
                                       chapterURL: chapterURL, bodyText: "", previousChapterURL: nil,
                                       nextChapterURL: nil, imageURLs: [URL(string: "https://images.example.com/p1.jpg")!])
        let persistence = OfflineChapterPersistence(modelContainer: container)
        try await persistence.persist(result, chapterID: chapter.id, cachedAt: .now)
        let context = ModelContext(container)
        let saved = try #require(context.fetch(FetchDescriptor<Chapter>()).first)
        #expect(saved.imageSourceURLs == result.imageURLs.map(\.absoluteString))
        #expect(saved.isCached && saved.isAvailableOffline)
        try await persistence.clearBodyText(chapterIDs: [chapter.id])
        let cleared = try #require(ModelContext(container).fetch(FetchDescriptor<Chapter>()).first)
        #expect(!cleared.isManga && !cleared.isAvailableOffline)
    }
}
