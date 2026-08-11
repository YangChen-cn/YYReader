import Foundation
import SwiftData
import Testing
@testable import YYReader

@MainActor
struct LibraryStoreTests {
    @Test
    func cataloglessChaptersFromTheSameSourceBookShareOneBook() async throws {
        let first = try #require(URL(string: "https://example.com/serial/stable-book/1.html"))
        let second = try #require(URL(string: "https://example.com/serial/stable-book/2.html"))
        let loader = MockHTMLLoader(documents: [
            first: genericCataloglessChapter(title: "第1章 开始", body: "第一章"),
            second: genericCataloglessChapter(title: "第2章 继续", body: "第二章")
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Book.self, Chapter.self, configurations: configuration)
        let store = LibraryStore(
            modelContext: container.mainContext,
            coordinator: NovelImportCoordinator(loader: loader)
        )

        store.startImportURL(first.absoluteString)
        try await waitForImport(store)
        store.startImportURL(second.absoluteString)
        try await waitForImport(store)

        #expect(store.books.count == 1)
        let book = try #require(store.books.first)
        #expect(!book.hasCatalog)
        #expect(book.sourceBookURL == "https://example.com/serial/stable-book/")
        #expect(book.author == "测试作者")
        #expect(book.chapters.count == 2)
    }

    @Test
    func cataloglessGenericPathUsesSyntheticBookIdentity() async throws {
        let first = try #require(URL(string: "https://example.com/read/first.html"))
        let second = try #require(URL(string: "https://example.com/read/second.html"))
        let loader = MockHTMLLoader(documents: [
            first: genericCataloglessChapter(
                title: "第1章 开始",
                bookTitle: "泛用路径测试小说",
                body: "第一章"
            ),
            second: genericCataloglessChapter(
                title: "第2章 继续",
                bookTitle: "泛用路径测试小说",
                body: "第二章"
            )
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Book.self, Chapter.self, configurations: configuration)
        let store = LibraryStore(
            modelContext: container.mainContext,
            coordinator: NovelImportCoordinator(loader: loader)
        )

        store.startImportURL(first.absoluteString)
        try await waitForImport(store)
        store.startImportURL(second.absoluteString)
        try await waitForImport(store)

        let book = try #require(store.books.first)
        let identityURL = try #require(URL(string: book.sourceBookURL))
        #expect(store.books.count == 1)
        #expect(identityURL.scheme == "yyreader-book")
        #expect(identityURL.host == "example.com")
        #expect(identityURL.path == "/泛用路径测试小说/测试作者")
    }

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
    func selectingBookDoesNotRefreshAnExpiredCatalog() async throws {
        let catalogURL = try #require(URL(string: "https://example.com/book/slow-catalog/"))
        let loader = MockHTMLLoader(documents: [
            catalogURL: """
            <h1>测试小说</h1>
            <ul>
              <li><a href="/book/slow-catalog/1.html">第1章 开始</a></li>
              <li><a href="/book/slow-catalog/2.html">第2章 继续</a></li>
            </ul>
            """
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Book.self, Chapter.self, configurations: configuration)
        let context = container.mainContext
        let firstBook = Book(
            title: "已选书籍",
            author: "测试作者",
            sourceHost: "example.com",
            catalogURL: "https://example.com/book/current/",
            catalogFetchedAt: .now
        )
        let expiredBook = Book(
            title: "大目录书籍",
            author: "测试作者",
            sourceHost: "example.com",
            catalogURL: catalogURL.absoluteString,
            catalogFetchedAt: .distantPast
        )
        context.insert(firstBook)
        context.insert(expiredBook)
        try context.save()

        let store = LibraryStore(
            modelContext: context,
            coordinator: NovelImportCoordinator(loader: loader)
        )
        store.restoreSelection(bookID: firstBook.id, chapterID: nil)
        store.selectBook(expiredBook.id)
        try await Task.sleep(for: .milliseconds(50))

        #expect(store.selectedBook?.id == expiredBook.id)
        #expect(loader.requestedURLs.isEmpty)
        #expect(!store.isLoading)
        #expect(!store.canCancelLoading)
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

    @Test
    func continuousPrefetchCachesNextChapterWithoutChangingRenderedEntries() async throws {
        let nextURL = try #require(URL(string: "https://example.com/book/continuous/2.html"))
        let thirdURL = try #require(URL(string: "https://example.com/book/continuous/3.html"))
        let loader = MockHTMLLoader(documents: [
            nextURL: genericCataloglessChapter(title: "第2章 继续", body: "连续阅读的第二章"),
            thirdURL: genericCataloglessChapter(title: "第3章 后续", body: "连续阅读的第三章")
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Book.self, Chapter.self, configurations: configuration)
        let context = container.mainContext
        let book = Book(
            title: "连续阅读测试",
            author: "测试作者",
            sourceHost: "example.com",
            catalogURL: "https://example.com/book/continuous/"
        )
        let first = Chapter(
            sourceURL: "https://example.com/book/continuous/1.html",
            title: "第1章 开始",
            sortIndex: 1,
            bodyText: "第一段\n第二段\n第三段",
            nextURL: nextURL.absoluteString,
            cachedAt: .now,
            book: book
        )
        let second = Chapter(
            sourceURL: nextURL.absoluteString,
            title: "第2章 继续",
            sortIndex: 2,
            book: book
        )
        let third = Chapter(
            sourceURL: thirdURL.absoluteString,
            title: "第3章 后续",
            sortIndex: 3,
            book: book
        )
        book.chapters = [first, second, third]
        book.currentChapterID = first.id
        context.insert(book)
        context.insert(first)
        context.insert(second)
        context.insert(third)
        try context.save()

        let store = LibraryStore(modelContext: context, coordinator: NovelImportCoordinator(loader: loader))
        store.restoreSelection(bookID: book.id, chapterID: first.id)
        #expect(!store.continuousReadingEnabled)
        store.configureContinuousReading(true)
        store.prepareContinuousReading()
        try await waitForCache(of: second)

        // Enabling continuous reading starts a one-chapter lookahead without attaching it.
        #expect(loader.requestedURLs == [nextURL])
        #expect(store.readerSession.entries.map(\.chapter.id) == [first.id])

        // Re-prefetching an already cached chapter must remain a cache-only operation.
        store.prefetchContinuousChapter(after: first.id)
        #expect(store.readerSession.entries.map(\.chapter.id) == [first.id])

        store.prepareContinuousChapterAttachment(after: first.id)
        #expect(store.readerSession.entries.map(\.chapter.id) == [first.id, second.id])

        store.beginReaderScrollTransaction()
        store.updateVisibleReaderPosition(chapterID: second.id, paragraphIndex: 0, total: 1)
        try await waitForCache(of: third)

        // Committing the newly visible chapter advances lookahead, but does not attach it.
        #expect(store.selectedChapterID == second.id)
        #expect(loader.requestedURLs == [nextURL, thirdURL])
        #expect(store.readerSession.entries.map(\.chapter.id) == [first.id, second.id])
    }

    @Test
    func continuousReaderCommitsOneChapterPerScrollTransaction() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Book.self, Chapter.self, configurations: configuration)
        let context = container.mainContext
        let book = Book(
            title: "稳定连续阅读",
            author: "测试作者",
            sourceHost: "example.com",
            catalogURL: "https://example.com/book/stable/"
        )
        let chapters = (1...20).map { index in
            Chapter(
                sourceURL: "https://example.com/book/stable/\(index).html",
                title: "第\(index)章",
                sortIndex: index,
                bodyText: "第\(index)章的缓存测试正文。",
                cachedAt: .now,
                book: book
            )
        }
        book.chapters = chapters
        book.currentChapterID = chapters[0].id
        context.insert(book)
        for chapter in chapters { context.insert(chapter) }
        try context.save()

        let store = LibraryStore(modelContext: context, coordinator: NovelImportCoordinator(loader: MockHTMLLoader(documents: [:])))
        store.restoreSelection(bookID: book.id, chapterID: chapters[0].id)
        store.configureContinuousReading(true)
        store.prepareContinuousReading()
        #expect(store.readerSession.entries.map(\.chapter.id) == [chapters[0].id])

        store.beginReaderScrollTransaction()
        store.prepareContinuousChapterAttachment(after: chapters[0].id)
        #expect(store.readerSession.entries.map(\.chapter.id) == [chapters[0].id])
        store.endReaderScrollTransaction(topVisibleChapterID: chapters[0].id)
        #expect(store.readerSession.entries.map(\.chapter.id) == [chapters[0].id, chapters[1].id])

        store.beginReaderScrollTransaction()
        store.updateVisibleReaderPosition(chapterID: chapters[1].id, paragraphIndex: 0, total: 1)
        try await Task.sleep(for: .milliseconds(260))
        #expect(store.selectedChapterID == chapters[1].id)
        // Committing chapter 2 must not rebuild the viewport or attach chapter 3.
        #expect(store.readerSession.entries.map(\.chapter.id) == [chapters[0].id, chapters[1].id])
        store.updateVisibleReaderPosition(chapterID: chapters[2].id, paragraphIndex: 0, total: 1)
        try await Task.sleep(for: .milliseconds(260))
        #expect(store.selectedChapterID == chapters[1].id)
        store.prepareContinuousChapterAttachment(after: chapters[1].id)
        #expect(store.readerSession.entries.map(\.chapter.id) == [chapters[0].id, chapters[1].id])

        store.endReaderScrollTransaction(topVisibleChapterID: chapters[1].id)
        try await Task.sleep(for: .milliseconds(300))
        #expect(store.readerSession.entries.map(\.chapter.id) == [chapters[0].id, chapters[1].id])
        store.beginReaderScrollTransaction()
        store.prepareContinuousChapterAttachment(after: chapters[1].id)
        #expect(store.readerSession.entries.map(\.chapter.id) == [chapters[0].id, chapters[1].id])
        store.endReaderScrollTransaction(topVisibleChapterID: chapters[1].id)
        #expect(store.readerSession.entries.map(\.chapter.id) == [chapters[0].id, chapters[1].id, chapters[2].id])

        store.beginReaderScrollTransaction()
        store.updateVisibleReaderPosition(chapterID: chapters[2].id, paragraphIndex: 0, total: 1)
        try await Task.sleep(for: .milliseconds(260))
        #expect(store.selectedChapterID == chapters[2].id)
        #expect(store.readerSession.entries.map(\.chapter.id) == [chapters[0].id, chapters[1].id, chapters[2].id])

        for index in 2..<5 {
            store.endReaderScrollTransaction(topVisibleChapterID: chapters[index].id)
            store.beginReaderScrollTransaction()
            store.prepareContinuousChapterAttachment(after: chapters[index].id)
            store.endReaderScrollTransaction(topVisibleChapterID: chapters[index].id)
            store.beginReaderScrollTransaction()
            store.updateVisibleReaderPosition(chapterID: chapters[index + 1].id, paragraphIndex: 0, total: 1)
            try await Task.sleep(for: .milliseconds(260))
            #expect(store.selectedChapterID == chapters[index + 1].id)
        }
    }

    @Test
    func endingScrollTransactionNeverRemovesRenderedChaptersAboveViewport() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Book.self, Chapter.self, configurations: configuration)
        let context = container.mainContext
        let book = Book(
            title: "连续阅读回收测试",
            author: "测试作者",
            sourceHost: "example.com",
            catalogURL: "https://example.com/book/reclaim/"
        )
        let chapters = (0..<32).map { index in
            Chapter(
                sourceURL: "https://example.com/book/reclaim/\(index).html",
                title: "第\(index + 1)章",
                sortIndex: index,
                bodyText: "缓存正文",
                cachedAt: .now,
                book: book
            )
        }
        book.chapters = chapters
        book.currentChapterID = chapters[0].id
        context.insert(book)
        for chapter in chapters { context.insert(chapter) }
        try context.save()

        let store = LibraryStore(
            modelContext: context,
            coordinator: NovelImportCoordinator(loader: MockHTMLLoader(documents: [:]))
        )
        store.restoreSelection(bookID: book.id, chapterID: chapters[0].id)
        store.configureContinuousReading(true)
        for chapter in chapters.dropFirst() {
            store.readerSession.attachNext(chapter)
        }

        store.beginReaderScrollTransaction()
        #expect(store.readerSession.entries.count == 32)

        store.endReaderScrollTransaction(topVisibleChapterID: chapters[30].id)
        #expect(store.readerSession.entries.map(\.id) == chapters.map(\.id))

        store.resetContinuousReaderWindow()
        #expect(store.readerSession.entries.map(\.id) == [chapters[0].id])
    }

    @Test
    func offlineDownloadSkipsCachedChaptersAndPreservesCurrentCacheOnClear() async throws {
        let secondURL = try #require(URL(string: "https://example.com/book/offline/2.html"))
        let thirdURL = try #require(URL(string: "https://example.com/book/offline/3.html"))
        let loader = MockHTMLLoader(documents: [
            secondURL: genericCataloglessChapter(title: "第2章 下载", body: "第二章离线正文"),
            thirdURL: genericCataloglessChapter(title: "第3章 下载", body: "第三章离线正文")
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Book.self, Chapter.self, configurations: configuration)
        let context = container.mainContext
        let book = Book(
            title: "离线测试",
            author: "测试作者",
            sourceHost: "example.com",
            catalogURL: "https://example.com/book/offline/"
        )
        let first = Chapter(
            sourceURL: "https://example.com/book/offline/1.html",
            title: "第1章 当前",
            sortIndex: 1,
            bodyText: "当前章节缓存",
            cachedAt: .now,
            book: book
        )
        let second = Chapter(sourceURL: secondURL.absoluteString, title: "第2章 下载", sortIndex: 2, book: book)
        let third = Chapter(sourceURL: thirdURL.absoluteString, title: "第3章 下载", sortIndex: 3, book: book)
        book.chapters = [first, second, third]
        book.currentChapterID = first.id
        context.insert(book)
        context.insert(first)
        context.insert(second)
        context.insert(third)
        try context.save()

        let store = LibraryStore(modelContext: context, coordinator: NovelImportCoordinator(loader: loader))
        store.restoreSelection(bookID: book.id, chapterID: first.id)
        store.downloadFollowingChapters()
        try await waitForOfflineDownload(store)

        #expect(loader.requestedURLs == [secondURL, thirdURL])
        #expect(second.isCached)
        #expect(third.isCached)

        store.deleteOfflineCache()
        #expect(first.isCached)
        #expect(!second.isCached)
        #expect(!third.isCached)
    }
}

@MainActor
private func waitForImport(_ store: LibraryStore) async throws {
    await Task.yield()
    while store.isLoading || store.canCancelLoading {
        try await Task.sleep(for: .milliseconds(10))
    }
}

@MainActor
private func waitForCache(of chapter: Chapter) async throws {
    for _ in 0..<100 {
        if chapter.isCached { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("等待章节缓存超时")
}

@MainActor
private func waitForOfflineDownload(_ store: LibraryStore) async throws {
    for _ in 0..<100 {
        if !store.offlineDownloads.isDownloading { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("等待离线下载超时")
}

private func genericCataloglessChapter(
    title: String,
    bookTitle: String = "",
    body: String
) -> String {
    """
    <meta name="author" content="测试作者">
    <title>\(title)_\(bookTitle)</title>
    <h1>\(title)</h1>
    <article><p>\(body)的自造测试正文用于验证无目录书籍身份。这里继续补充足够的内容，使通用解析器可以确认这是章节而不是导航区域。所有文字均为测试用途，不包含第三方小说内容。</p><p>第二段继续说明，这两个章节地址共享同一个书籍级父路径，因此导入协调器必须产生完全一致的 sourceBookURL。这样既不会使用当前章节地址作为身份，也不会在第二次导入时创建重复书籍。</p></article>
    """
}
