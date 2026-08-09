import Foundation
import SwiftData
import Testing
@testable import YYReader

@MainActor
struct LibraryStoreTests {
    @Test
    func initialCatalogPageDoesNotImmediatelyTriggerFullRefresh() async throws {
        let chapter1 = try #require(URL(string: "https://www.qidiy.com/book/100/1.html"))
        let chapter2 = try #require(URL(string: "https://www.qidiy.com/book/100/1/2.html"))
        let catalog = try #require(URL(string: "https://www.qidiy.com/book/100/"))
        let loader = MockHTMLLoader(documents: [
            chapter1: try TestFixture.html("qidiy_chapter_1"),
            chapter2: try TestFixture.html("qidiy_chapter_2"),
            catalog: try TestFixture.html("qidiy_catalog_1")
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Book.self, Chapter.self, configurations: configuration)
        let store = LibraryStore(
            modelContext: container.mainContext,
            coordinator: NovelImportCoordinator(loader: loader)
        )

        store.startImportURL(chapter1.absoluteString)
        while store.canCancelLoading {
            try await Task.sleep(for: .milliseconds(10))
        }

        let book = try #require(store.books.first)
        #expect(book.catalogFetchedAt != nil)
        #expect(loader.requestedURLs == [chapter1, chapter2, catalog])

        store.selectBook(book.id)
        try await Task.sleep(for: .milliseconds(50))
        #expect(loader.requestedURLs == [chapter1, chapter2, catalog])
        #expect(!store.isLoading)
        _ = container
    }

    @Test
    func nextChapterSelectionStartsOnlyOneForegroundLoad() async throws {
        let nextURL = try #require(URL(string: "https://www.qidiy.com/book/100/2.html"))
        let loader = MockHTMLLoader(
            documents: [
                nextURL: """
                <a href="/book/100/">测试小说</a>
                <h1 class="title">第2章 路上</h1>
                <div id="content">下一章的测试正文。</div>
                <a href="/book/100/1.html">上一章</a>
                <a href="/book/100/">章节列表</a>
                """
            ],
            delay: .milliseconds(50)
        )
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Book.self, Chapter.self, configurations: configuration)
        let context = container.mainContext
        let book = Book(
            title: "测试小说",
            author: "测试作者",
            sourceHost: "www.qidiy.com",
            catalogURL: "https://www.qidiy.com/book/100/",
            catalogFetchedAt: .now
        )
        let first = Chapter(
            sourceURL: "https://www.qidiy.com/book/100/1.html",
            title: "第1章 出发",
            sortIndex: 1,
            bodyText: "第一章正文",
            nextURL: nextURL.absoluteString,
            cachedAt: .now,
            book: book
        )
        let next = Chapter(
            sourceURL: nextURL.absoluteString,
            title: "第2章 路上",
            sortIndex: 2,
            book: book
        )
        book.chapters = [first, next]
        book.currentChapterID = first.id
        context.insert(book)
        context.insert(first)
        context.insert(next)
        try context.save()

        let store = LibraryStore(
            modelContext: context,
            coordinator: NovelImportCoordinator(loader: loader)
        )
        store.restoreSelection(bookID: book.id, chapterID: first.id)
        store.goToNextChapter()
        await store.ensureSelectedChapterLoaded()

        #expect(loader.requestedURLs == [nextURL])
        #expect(store.selectedChapter?.title == "第2章 路上")
        #expect(store.selectedChapter?.bodyText == "下一章的测试正文。")
    }

    @Test
    func removesLegacyLatestChapterTailWithoutDeletingCachedChapters() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Book.self, Chapter.self, configurations: configuration)
        let context = container.mainContext
        let book = Book(
            title: "测试小说",
            author: "测试作者",
            sourceHost: "www.qidiy.com",
            catalogURL: "https://www.qidiy.com/book/100/",
            catalogFetchedAt: .now
        )
        let prefix = (1...20).map { number in
            Chapter(
                sourceURL: "https://www.qidiy.com/book/100/\(number).html",
                title: "第\(number)章 测试",
                sortIndex: number,
                bodyText: number == 1 ? "已缓存正文" : nil,
                cachedAt: number == 1 ? .now : nil,
                book: book
            )
        }
        let pollutedTail = (209...218).map { number in
            Chapter(
                sourceURL: "https://www.qidiy.com/book/100/\(number).html",
                title: "第\(number)章 旧最新章节",
                sortIndex: number,
                book: book
            )
        }
        book.chapters = prefix + pollutedTail
        book.currentChapterID = prefix[0].id
        context.insert(book)
        for chapter in book.chapters { context.insert(chapter) }
        try context.save()

        let store = LibraryStore(
            modelContext: context,
            coordinator: NovelImportCoordinator(loader: MockHTMLLoader(documents: [:]))
        )

        let storedBook = try #require(store.books.first)
        #expect(storedBook.chapters.map(\.sortIndex).sorted() == Array(1...20))
        #expect(storedBook.chapters.first(where: { $0.id == prefix[0].id })?.isCached == true)
    }

    @Test
    func catalogRefreshRepairsPreviouslyInterleavedExtras() async throws {
        let catalogURL = try #require(URL(string: "https://www.qidiy.com/book/300/"))
        let loader = MockHTMLLoader(documents: [
            catalogURL: """
                <h1>顺序测试</h1><p>作者：测试作者</p>
                <ul class="section-list">
                    <li><a href="/book/300/main-1.html">第1章 正文一</a></li>
                    <li><a href="/book/300/main-2.html">第2章 正文二</a></li>
                    <li><a href="/book/300/extra-1.html">第1章 番外一</a></li>
                    <li><a href="/book/300/extra-2.html">第2章 番外二</a></li>
                </ul>
                """
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Book.self, Chapter.self, configurations: configuration)
        let context = container.mainContext
        let book = Book(
            title: "顺序测试",
            author: "测试作者",
            sourceHost: "www.qidiy.com",
            catalogURL: catalogURL.absoluteString,
            catalogFetchedAt: .now
        )
        let main1 = Chapter(
            sourceURL: "https://www.qidiy.com/book/300/main-1.html",
            title: "第1章 正文一",
            sortIndex: 1,
            book: book
        )
        let extra1 = Chapter(
            sourceURL: "https://www.qidiy.com/book/300/extra-1.html",
            title: "第1章 番外一",
            sortIndex: 1,
            book: book
        )
        let main2 = Chapter(
            sourceURL: "https://www.qidiy.com/book/300/main-2.html",
            title: "第2章 正文二",
            sortIndex: 2,
            book: book
        )
        let extra2 = Chapter(
            sourceURL: "https://www.qidiy.com/book/300/extra-2.html",
            title: "第2章 番外二",
            sortIndex: 2,
            book: book
        )
        book.chapters = [main1, extra1, main2, extra2]
        context.insert(book)
        for chapter in book.chapters { context.insert(chapter) }
        try context.save()

        let store = LibraryStore(
            modelContext: context,
            coordinator: NovelImportCoordinator(loader: loader)
        )
        store.selectBook(book.id)
        await store.refreshSelectedCatalog()

        #expect(store.sortedChapters.map(\.title) == [
            "第1章 正文一", "第2章 正文二", "第1章 番外一", "第2章 番外二"
        ])
        #expect(store.sortedChapters.map(\.sortIndex) == [1, 2, 3, 4])
    }

    @Test
    func catalogRefreshCanBeCancelledFromLoadingOverlay() async throws {
        let catalogURL = try #require(URL(string: "https://www.qidiy.com/book/500/"))
        let loader = MockHTMLLoader(
            documents: [
                catalogURL: """
                    <h1>取消测试</h1><p>作者：测试作者</p>
                    <ul class="section-list">
                        <li><a href="/book/500/1.html">第1章 测试</a></li>
                    </ul>
                    """
            ],
            delay: .seconds(5)
        )
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Book.self, Chapter.self, configurations: configuration)
        let context = container.mainContext
        let book = Book(
            title: "取消测试",
            author: "测试作者",
            sourceHost: "www.qidiy.com",
            catalogURL: catalogURL.absoluteString,
            catalogFetchedAt: .now
        )
        context.insert(book)
        try context.save()
        let store = LibraryStore(
            modelContext: context,
            coordinator: NovelImportCoordinator(loader: loader)
        )
        store.selectBook(book.id)

        store.startRefreshSelectedCatalog()
        while !store.isLoading {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(store.canCancelLoading)
        #expect(store.loadingMessage == "正在刷新目录…（第 1 页）")

        store.cancelLoading()
        while store.isLoading {
            try await Task.sleep(for: .milliseconds(5))
        }

        #expect(!store.canCancelLoading)
        #expect(store.presentedError == nil)
        #expect(loader.requestedURLs == [catalogURL])
    }

    @Test
    func progressUpdatesInMemoryAndFlushesBeforeChapterNavigation() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Book.self, Chapter.self, configurations: configuration)
        let context = container.mainContext
        context.autosaveEnabled = false
        let book = Book(
            title: "进度测试",
            author: "测试作者",
            sourceHost: "example.com",
            catalogURL: "https://example.com/book/"
        )
        let first = Chapter(
            sourceURL: "https://example.com/book/1.html",
            title: "第1章",
            sortIndex: 1,
            bodyText: "第一段\n第二段\n第三段",
            nextURL: "https://example.com/book/2.html",
            cachedAt: .now,
            book: book
        )
        let second = Chapter(
            sourceURL: "https://example.com/book/2.html",
            title: "第2章",
            sortIndex: 2,
            bodyText: "下一章",
            previousURL: first.sourceURL,
            cachedAt: .now,
            book: book
        )
        book.chapters = [first, second]
        book.currentChapterID = first.id
        context.insert(book)
        context.insert(first)
        context.insert(second)
        try context.save()

        let store = LibraryStore(
            modelContext: context,
            coordinator: NovelImportCoordinator(loader: MockHTMLLoader(documents: [:])),
            progressSaveDelay: .seconds(30)
        )
        store.restoreSelection(bookID: book.id, chapterID: first.id)
        store.updateProgress(chapterID: first.id, paragraphIndex: 1, total: 3)

        #expect(first.topParagraphIndex == 1)
        #expect(first.readingProgress == 0.5)
        #expect(context.hasChanges)

        let originalSnapshot = store.chapterNavigationSnapshot
        store.goToNextChapter()

        #expect(!context.hasChanges)
        #expect(store.selectedChapterID == second.id)
        #expect(store.readerScrollRequest?.intent == .chapterTop)
        #expect(originalSnapshot.totalCount == store.chapterNavigationSnapshot.totalCount)
    }

    @Test
    func debouncedProgressEventuallyPersists() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Book.self, Chapter.self, configurations: configuration)
        let context = container.mainContext
        context.autosaveEnabled = false
        let book = Book(
            title: "防抖测试",
            author: "测试作者",
            sourceHost: "example.com",
            catalogURL: "https://example.com/debounce/"
        )
        let chapter = Chapter(
            sourceURL: "https://example.com/debounce/1.html",
            title: "第1章",
            sortIndex: 1,
            bodyText: "第一段\n第二段",
            cachedAt: .now,
            book: book
        )
        book.chapters = [chapter]
        book.currentChapterID = chapter.id
        context.insert(book)
        context.insert(chapter)
        try context.save()

        let store = LibraryStore(
            modelContext: context,
            coordinator: NovelImportCoordinator(loader: MockHTMLLoader(documents: [:])),
            progressSaveDelay: .milliseconds(20)
        )
        store.restoreSelection(bookID: book.id, chapterID: chapter.id)
        store.updateProgress(chapterID: chapter.id, paragraphIndex: 1, total: 2)
        #expect(context.hasChanges)

        try await Task.sleep(for: .milliseconds(80))

        #expect(!context.hasChanges)
        #expect(store.presentedError == nil)
    }
}
