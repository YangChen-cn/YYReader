import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class LibraryStore {
    private let modelContext: ModelContext
    private let coordinator: NovelImportCoordinator
    private var prefetchTask: Task<Void, Never>?
    private var importTask: Task<Void, Never>?

    private(set) var books: [Book] = []
    var selectedBookID: UUID?
    var selectedChapterID: UUID?
    private(set) var isLoading = false
    private(set) var loadingMessage = ""
    var presentedError: PresentedError?

    init(modelContext: ModelContext, coordinator: NovelImportCoordinator) {
        self.modelContext = modelContext
        self.coordinator = coordinator
        refreshBooks()
    }

    var selectedBook: Book? {
        books.first { $0.id == selectedBookID }
    }

    var selectedChapter: Chapter? {
        selectedBook?.chapters.first { $0.id == selectedChapterID }
    }

    var sortedChapters: [Chapter] {
        selectedBook?.chapters.sorted { lhs, rhs in
            if lhs.sortIndex == rhs.sortIndex { lhs.title < rhs.title }
            else { lhs.sortIndex < rhs.sortIndex }
        } ?? []
    }

    var canCancelLoading: Bool { importTask != nil }

    func restoreSelection(bookID: UUID?, chapterID: UUID?) {
        selectedBookID = books.contains { $0.id == bookID } ? bookID : books.first?.id
        selectInitialChapter(preferredID: chapterID)
    }

    func selectBook(_ id: UUID?) {
        selectedBookID = id
        selectInitialChapter(preferredID: nil)
        if let book = selectedBook,
           book.catalogFetchedAt.map({ Date.now.timeIntervalSince($0) > 21_600 }) ?? true {
            Task { await refreshSelectedCatalog() }
        }
    }

    func selectChapter(_ id: UUID?) {
        prefetchTask?.cancel()
        prefetchTask = nil
        selectedChapterID = id
        guard let chapter = selectedChapter else { return }
        selectedBook?.currentChapterID = chapter.id
        try? modelContext.save()
    }

    func startImportURL(_ input: String) {
        guard !isLoading else { return }
        importTask = Task { [weak self] in
            guard let self else { return }
            await importURL(input)
            importTask = nil
        }
    }

    func cancelLoading() {
        importTask?.cancel()
        importTask = nil
    }

    private func importURL(_ input: String) async {
        guard let url = normalizedURL(from: input) else {
            presentedError = PresentedError(message: NovelParsingError.unsupportedURL.localizedDescription)
            return
        }
        await performLoading("正在下载并识别小说…") {
            let result = try await coordinator.importNovel(from: url)
            let chapter = try upsert(result)
            refreshBooks()
            selectedBookID = chapter.book?.id
            selectedChapterID = chapter.id
        }
    }

    func refreshSelectedCatalog() async {
        guard let book = selectedBook, let url = URL(string: book.catalogURL) else { return }
        await performLoading("正在刷新目录…") {
            let catalog = try await coordinator.refreshCatalog(from: url)
            upsertCatalog(catalog, into: book)
            book.title = catalog.title
            book.author = catalog.author
            book.catalogFetchedAt = .now
            book.updatedAt = .now
            try modelContext.save()
            refreshBooks()
        }
    }

    func ensureSelectedChapterLoaded() async {
        guard let chapter = selectedChapter else { return }
        await ensureChapterLoaded(chapter)
    }

    func goToPreviousChapter() {
        navigate(to: selectedChapter?.previousURL, fallbackOffset: -1)
    }

    func goToNextChapter() {
        navigate(to: selectedChapter?.nextURL, fallbackOffset: 1)
    }

    func updateProgress(paragraphIndex: Int, total: Int) {
        guard let chapter = selectedChapter else { return }
        chapter.topParagraphIndex = max(0, paragraphIndex)
        chapter.readingProgress = total > 1
            ? min(max(Double(paragraphIndex) / Double(total - 1), 0), 1)
            : 0
        chapter.lastReadAt = .now
        chapter.book?.currentChapterID = chapter.id
        try? modelContext.save()
    }

    func deleteSelectedBook() {
        guard let book = selectedBook else { return }
        modelContext.delete(book)
        try? modelContext.save()
        refreshBooks()
        selectedBookID = books.first?.id
        selectInitialChapter(preferredID: nil)
    }

    func dismissError() {
        presentedError = nil
    }

    private func refreshBooks() {
        let descriptor = FetchDescriptor<Book>(sortBy: [SortDescriptor(\Book.updatedAt, order: .reverse)])
        let fetchedBooks = (try? modelContext.fetch(descriptor)) ?? []
        var removedLegacyEntries = false
        for book in fetchedBooks where removeLegacyLatestChapterEntries(from: book) {
            removedLegacyEntries = true
        }
        if removedLegacyEntries { try? modelContext.save() }
        books = fetchedBooks
    }

    private func removeLegacyLatestChapterEntries(from book: Book) -> Bool {
        let ordered = book.chapters.sorted { $0.sortIndex < $1.sortIndex }
        guard ordered.count >= 11, ordered.first?.sortIndex == 1 else { return false }

        var prefixEnd = 1
        for chapter in ordered.dropFirst() {
            guard chapter.sortIndex == prefixEnd + 1 else { break }
            prefixEnd = chapter.sortIndex
        }

        let tail = ordered.filter { $0.sortIndex > prefixEnd }
        guard prefixEnd >= 10,
              (5...20).contains(tail.count),
              let firstTail = tail.first,
              firstTail.sortIndex > prefixEnd + 20,
              tail.allSatisfy({ !$0.isCached && $0.id != book.currentChapterID }) else {
            return false
        }

        let tailIDs = Set(tail.map(\.id))
        book.chapters.removeAll { tailIDs.contains($0.id) }
        for chapter in tail { modelContext.delete(chapter) }
        return true
    }

    private func ensureChapterLoaded(_ chapter: Chapter) async {
        guard !chapter.isCached, let url = URL(string: chapter.sourceURL) else { return }
        await performLoading("正在加载章节…") {
            let result = try await coordinator.loadChapterContent(from: url)
            apply(result, to: chapter)
            try modelContext.save()
            schedulePrefetch(after: chapter)
        }
    }

    private func schedulePrefetch(after chapter: Chapter) {
        prefetchTask?.cancel()
        guard UserDefaults.standard.object(forKey: "reader.prefetchNext") as? Bool ?? true,
              let next = chapterForURL(chapter.nextURL), !next.isCached else {
            return
        }
        prefetchTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self, let url = URL(string: next.sourceURL) else { return }
            do {
                let result = try await self.coordinator.loadChapterContent(from: url)
                self.apply(result, to: next)
                try self.modelContext.save()
            } catch {
                // Prefetch is opportunistic; foreground loading will report errors.
            }
        }
    }

    private func navigate(to urlString: String?, fallbackOffset: Int) {
        if let chapter = chapterForURL(urlString) {
            selectChapter(chapter.id)
            return
        }
        if let urlString, let selectedBook, let selectedChapter {
            let chapter = Chapter(
                sourceURL: urlString,
                title: fallbackOffset < 0 ? "上一章" : "下一章",
                sortIndex: selectedChapter.sortIndex + fallbackOffset,
                book: nil
            )
            modelContext.insert(chapter)
            selectedBook.chapters.append(chapter)
            chapter.book = selectedBook
            try? modelContext.save()
            selectChapter(chapter.id)
            return
        }
        guard let selectedChapter,
              let index = sortedChapters.firstIndex(where: { $0.id == selectedChapter.id }) else { return }
        let nextIndex = index + fallbackOffset
        guard sortedChapters.indices.contains(nextIndex) else { return }
        selectChapter(sortedChapters[nextIndex].id)
    }

    private func chapterForURL(_ urlString: String?) -> Chapter? {
        guard let urlString else { return nil }
        return selectedBook?.chapters.first { chapter in
            chapter.sourceURL == urlString || canonicalURLString(chapter.sourceURL) == canonicalURLString(urlString)
        }
    }

    private func upsert(_ result: NovelImportResult) throws -> Chapter {
        let catalogString = result.catalogURL.absoluteString
        let descriptor = FetchDescriptor<Book>(predicate: #Predicate { $0.catalogURL == catalogString })
        let book = try modelContext.fetch(descriptor).first ?? Book(
            title: result.bookTitle,
            author: result.author,
            sourceHost: result.catalogURL.host ?? "",
            catalogURL: catalogString
        )
        if book.modelContext == nil { modelContext.insert(book) }

        book.title = result.bookTitle
        book.author = result.author
        // The initial catalog page is a successful refresh even when more pages exist.
        // Recording it prevents book selection from immediately downloading the full catalog.
        book.catalogFetchedAt = .now
        book.updatedAt = .now
        upsertCatalog(
            ParsedBookCatalog(title: result.bookTitle, author: result.author, chapters: result.catalog, nextPageURL: nil),
            into: book
        )

        let source = result.chapterURL.absoluteString
        let chapter = book.chapters.first { canonicalURLString($0.sourceURL) == canonicalURLString(source) }
            ?? Chapter(
                sourceURL: source,
                title: result.chapterTitle,
                // A separately imported extra may also be titled "第1章". Until a full
                // catalog refresh supplies its exact position, keep it after known entries.
                sortIndex: (book.chapters.map(\.sortIndex).max() ?? 0) + 1,
                book: nil
            )
        if chapter.modelContext == nil {
            modelContext.insert(chapter)
            book.chapters.append(chapter)
            chapter.book = book
        }
        chapter.title = result.chapterTitle
        chapter.bodyText = result.bodyText
        chapter.previousURL = result.previousChapterURL?.absoluteString
        chapter.nextURL = result.nextChapterURL?.absoluteString
        chapter.cachedAt = .now
        chapter.lastReadAt = .now
        book.currentChapterID = chapter.id
        try modelContext.save()
        return chapter
    }

    private func upsertCatalog(_ catalog: ParsedBookCatalog, into book: Book) {
        var existing = Dictionary(uniqueKeysWithValues: book.chapters.map { (canonicalURLString($0.sourceURL), $0) })
        for seed in catalog.chapters {
            let key = canonicalURLString(seed.url.absoluteString)
            if let chapter = existing[key] {
                chapter.title = seed.title
                chapter.sortIndex = seed.sortIndex
            } else {
                let chapter = Chapter(
                    sourceURL: seed.url.absoluteString,
                    title: seed.title,
                    sortIndex: seed.sortIndex,
                    book: nil
                )
                modelContext.insert(chapter)
                book.chapters.append(chapter)
                chapter.book = book
                existing[key] = chapter
            }
        }
    }

    private func apply(_ result: ChapterLoadResult, to chapter: Chapter) {
        chapter.title = result.title
        chapter.bodyText = result.bodyText
        chapter.previousURL = result.previousChapterURL?.absoluteString
        chapter.nextURL = result.nextChapterURL?.absoluteString
        chapter.cachedAt = .now
    }

    private func selectInitialChapter(preferredID: UUID?) {
        guard let book = selectedBook else {
            selectedChapterID = nil
            return
        }
        let preferred = preferredID.flatMap { id in book.chapters.first { $0.id == id } }
        let current = book.currentChapterID.flatMap { id in book.chapters.first { $0.id == id } }
        selectedChapterID = (preferred ?? current ?? book.chapters.min { $0.sortIndex < $1.sortIndex })?.id
    }

    private func normalizedURL(from input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let value = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            return nil
        }
        return url
    }

    private func canonicalURLString(_ value: String) -> String {
        guard let url = URL(string: value) else { return value }
        let path = HTMLParsingSupport.replacingRegex(
            "/(\\d+)/(\\d+)/(\\d+)\\.html$",
            in: url.path,
            with: "/$1/$2.html"
        )
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return value }
        components.path = path
        components.fragment = nil
        return components.url?.absoluteString ?? value
    }

    private func performLoading(_ message: String, operation: () async throws -> Void) async {
        isLoading = true
        loadingMessage = message
        defer {
            isLoading = false
            loadingMessage = ""
        }
        do {
            try await operation()
        } catch is CancellationError {
            return
        } catch HTMLLoadError.cancelled {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            presentedError = PresentedError(message: error.localizedDescription)
        }
    }
}
