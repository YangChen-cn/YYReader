import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class LibraryStore {
    private let modelContext: ModelContext
    private let coordinator: NovelImportCoordinator
    private let progressSaveDelay: Duration
    private var prefetchTask: Task<Void, Never>?
    private var importTask: Task<Void, Never>?
    private var catalogRefreshTask: Task<Void, Never>?
    private var progressSaveTask: Task<Void, Never>?
    private var continuousLoadTasks: [UUID: Task<Void, Never>] = [:]
    private var continuousLoadFailures: Set<UUID> = []
    private var visibleChapterDebounceTask: Task<Void, Never>?
    private var stableTrimTask: Task<Void, Never>?
    private var visibilityGate = ContinuousReaderVisibilityGate()
    private var pendingContinuousAttachmentChapterID: UUID?
    private var isReaderScrolling = false
    private var hasPendingProgressChanges = false

    let readerSession = ContinuousReaderSession()
    let offlineDownloads: OfflineDownloadManager
    private(set) var books: [Book] = []
    private(set) var sortedChapters: [Chapter] = []
    private(set) var chapterNavigationSnapshot = ReaderChapterNavigationSnapshot.empty
    private(set) var readerScrollRequest: ReaderScrollRequest?
    private(set) var continuousReadingEnabled = false
    private(set) var candidateVisibleChapterID: UUID?
    var selectedBookID: UUID?
    var selectedChapterID: UUID?
    private(set) var isLoading = false
    private(set) var loadingMessage = ""
    var presentedError: PresentedError?

    init(
        modelContext: ModelContext,
        coordinator: NovelImportCoordinator,
        progressSaveDelay: Duration = .milliseconds(600)
    ) {
        self.modelContext = modelContext
        self.coordinator = coordinator
        self.progressSaveDelay = progressSaveDelay
        self.offlineDownloads = OfflineDownloadManager(modelContext: modelContext, coordinator: coordinator)
        refreshBooks()
    }

    var selectedBook: Book? {
        books.first { $0.id == selectedBookID }
    }

    var selectedChapter: Chapter? {
        selectedBook?.chapters.first { $0.id == selectedChapterID }
    }

    var canCancelLoading: Bool { importTask != nil || catalogRefreshTask != nil }
    var canRefreshSelectedCatalog: Bool { selectedBook?.hasCatalog == true }
    var canDownloadEntireBook: Bool { selectedBook?.hasCatalog == true }
    var readerProgressText: String {
        let position = chapterNavigationSnapshot.positionText
        let percentage = Int((selectedChapter?.readingProgress ?? 0) * 100)
        return "\(position)　\(percentage)%"
    }

    func restoreSelection(bookID: UUID?, chapterID: UUID?) {
        selectedBookID = books.contains { $0.id == bookID } ? bookID : books.first?.id
        rebuildSelectedBookChapters()
        selectInitialChapter(preferredID: chapterID)
        refreshReaderSession()
        requestReaderScroll(.restore)
    }

    func selectBook(_ id: UUID?) {
        applyBookSelection(id, restoringOnFailure: selectedBookID)
    }

    func reconcileBookSelection(_ id: UUID?, previousID: UUID?) {
        applyBookSelection(id, restoringOnFailure: previousID)
    }

    private func applyBookSelection(_ id: UUID?, restoringOnFailure previousID: UUID?) {
        guard flushPendingProgress() else {
            selectedBookID = previousID
            return
        }
        selectedBookID = id
        rebuildSelectedBookChapters()
        selectInitialChapter(preferredID: nil)
        refreshReaderSession()
    }

    func selectChapter(_ id: UUID?, scrollIntent: ReaderScrollIntent? = nil) {
        applyChapterSelection(id, scrollIntent: scrollIntent, restoringOnFailure: selectedChapterID)
    }

    func reconcileChapterSelection(
        _ id: UUID?,
        previousID: UUID?,
        scrollIntent: ReaderScrollIntent? = nil
    ) {
        applyChapterSelection(id, scrollIntent: scrollIntent, restoringOnFailure: previousID)
    }

    private func applyChapterSelection(
        _ id: UUID?,
        scrollIntent: ReaderScrollIntent?,
        restoringOnFailure previousID: UUID?
    ) {
        guard flushPendingProgress() else {
            selectedChapterID = previousID
            return
        }
        prefetchTask?.cancel()
        prefetchTask = nil
        selectedChapterID = id
        guard let chapter = selectedChapter else {
            updateChapterNavigationSnapshot()
            return
        }
        selectedBook?.currentChapterID = chapter.id
        updateChapterNavigationSnapshot()
        refreshReaderSession()
        if let scrollIntent {
            requestReaderScroll(scrollIntent)
        }
        saveChanges(failureMessage: "保存当前章节失败")
    }

    func requestReaderScroll(_ intent: ReaderScrollIntent) {
        guard let chapterID = selectedChapterID else { return }
        readerScrollRequest = ReaderScrollRequest(chapterID: chapterID, intent: intent)
    }

    func consumeReaderScrollRequest(_ requestID: UUID) {
        guard readerScrollRequest?.id == requestID else { return }
        readerScrollRequest = nil
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
        catalogRefreshTask?.cancel()
        catalogRefreshTask = nil
    }

    func cancelOfflineDownload() {
        offlineDownloads.cancel()
    }

    func downloadCurrentChapter() {
        startOfflineDownload(.currentChapter)
    }

    func downloadFollowingChapters() {
        startOfflineDownload(.followingChapters(20))
    }

    func downloadEntireBook() {
        startOfflineDownload(.entireBook)
    }

    func deleteOfflineCache() {
        guard let book = selectedBook else { return }
        let retainedChapterID = selectedChapterID
        for chapter in book.chapters where chapter.id != retainedChapterID {
            chapter.bodyText = nil
            chapter.cachedAt = nil
        }
        saveChanges(failureMessage: "删除离线缓存失败")
        refreshReaderSession()
    }

    func configureContinuousReading(_ isEnabled: Bool) {
        guard continuousReadingEnabled != isEnabled else { return }
        continuousReadingEnabled = isEnabled
        candidateVisibleChapterID = nil
        visibleChapterDebounceTask?.cancel()
        stableTrimTask?.cancel()
        pendingContinuousAttachmentChapterID = nil
        refreshReaderSession()
    }

    func prepareContinuousReading() {
        refreshReaderSession()
    }

    func prefetchContinuousChapter(after chapterID: UUID) {
        guard let chapter = selectedBook?.chapters.first(where: { $0.id == chapterID }),
              let next = neighbor(of: chapter, offset: 1) else {
            return
        }
        guard !next.isCached else { return }
        startContinuousLoad(for: next)
    }

    func prepareContinuousChapterAttachment(after chapterID: UUID) {
        guard continuousReadingEnabled,
              chapterID == selectedChapterID,
              let chapter = selectedBook?.chapters.first(where: { $0.id == chapterID }),
              let next = neighbor(of: chapter, offset: 1) else {
            return
        }

        prefetchContinuousChapter(after: chapterID)
        guard !visibilityGate.hasCommittedInCurrentTransaction else { return }
        if next.isCached {
            readerSession.attachNext(next)
        } else {
            pendingContinuousAttachmentChapterID = chapterID
        }
    }

    func retryContinuousChapter(after chapterID: UUID) {
        guard let chapter = selectedBook?.chapters.first(where: { $0.id == chapterID }),
              let next = neighbor(of: chapter, offset: 1) else {
            return
        }
        continuousLoadFailures.remove(next.id)
        startContinuousLoad(for: next)
    }

    func continuationStatus(after chapterID: UUID) -> ReaderContinuationStatus {
        guard let chapter = selectedBook?.chapters.first(where: { $0.id == chapterID }),
              let next = neighbor(of: chapter, offset: 1) else {
            return .unavailable
        }
        if next.isCached { return .ready }
        if continuousLoadFailures.contains(next.id) { return .failed }
        return continuousLoadTasks[next.id] == nil ? .idle : .loading
    }

    func updateVisibleReaderPosition(chapterID: UUID, paragraphIndex: Int, total: Int) {
        guard let chapter = selectedBook?.chapters.first(where: { $0.id == chapterID }) else { return }
        updateProgress(
            chapterID: chapterID,
            paragraphIndex: paragraphIndex,
            total: total,
            updatesCurrentChapter: !continuousReadingEnabled
        )
        guard continuousReadingEnabled else {
            commitVisibleChapter(chapter)
            return
        }
        scheduleVisibleChapterCommit(for: chapter)
    }

    func beginReaderScrollTransaction() {
        isReaderScrolling = true
        stableTrimTask?.cancel()
        visibilityGate.beginTransaction()
    }

    func endReaderScrollTransaction(topVisibleChapterID: UUID?) {
        isReaderScrolling = false
        attachPendingContinuousChapterIfSafe()
        scheduleStableTrim(topVisibleChapterID: topVisibleChapterID)
    }

    private func scheduleVisibleChapterCommit(for chapter: Chapter) {
        guard chapter.id != selectedChapterID else {
            candidateVisibleChapterID = nil
            visibleChapterDebounceTask?.cancel()
            return
        }
        guard readerSession.entries.contains(where: { $0.chapter.id == chapter.id }) else { return }
        candidateVisibleChapterID = chapter.id
        visibleChapterDebounceTask?.cancel()
        visibleChapterDebounceTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(200))
            } catch is CancellationError {
                return
            } catch {
                return
            }
            guard let self,
                  self.candidateVisibleChapterID == chapter.id else {
                return
            }
            self.commitCandidateVisibleChapter(chapter.id)
        }
    }

    private func commitCandidateVisibleChapter(_ chapterID: UUID) {
        guard let chapter = selectedBook?.chapters.first(where: { $0.id == chapterID }),
              visibilityGate.accepts(
                candidateID: chapterID,
                currentID: selectedChapterID,
                orderedChapterIDs: sortedChapters.map(\.id)
              ) else {
            return
        }
        candidateVisibleChapterID = nil
        visibilityGate.recordCommit()
        commitVisibleChapter(chapter)
    }

    private func commitVisibleChapter(_ chapter: Chapter) {
        readerSession.updateVisibleChapter(chapter.id)
        guard selectedChapterID != chapter.id else { return }
        selectedChapterID = chapter.id
        chapter.book?.currentChapterID = chapter.id
        updateChapterNavigationSnapshot()
        scheduleProgressSave()
    }

    private func scheduleStableTrim(topVisibleChapterID: UUID?) {
        guard continuousReadingEnabled,
              let topVisibleChapterID else {
            return
        }
        stableTrimTask?.cancel()
        stableTrimTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch is CancellationError {
                return
            } catch {
                return
            }
            guard let self,
                  !self.isReaderScrolling,
                  self.selectedChapterID == topVisibleChapterID,
                  let index = self.sortedChapters.firstIndex(where: { $0.id == topVisibleChapterID }) else {
                return
            }
            let lowerBound = max(self.sortedChapters.startIndex, index - 1)
            let upperBound = min(self.sortedChapters.index(before: self.sortedChapters.endIndex), index + 1)
            self.readerSession.trim(toChapterIDs: Set(self.sortedChapters[lowerBound...upperBound].map(\.id)))
        }
    }

    private func importURL(_ input: String) async {
        guard let url = normalizedURL(from: input) else {
            presentedError = PresentedError(message: NovelParsingError.unsupportedURL.localizedDescription)
            return
        }
        await performLoading("正在下载并识别小说…") {
            let result = try await coordinator.importNovel(from: url)
            guard flushPendingProgress() else { return }
            let chapter = try upsert(result)
            refreshBooks()
            selectedBookID = chapter.book?.id
            rebuildSelectedBookChapters()
            selectedChapterID = chapter.id
            updateChapterNavigationSnapshot()
            requestReaderScroll(.chapterTop)
        }
    }

    func refreshSelectedCatalog() async {
        guard let book = selectedBook,
              book.hasCatalog,
              let url = URL(string: book.catalogURL) else {
            return
        }
        await performLoading("正在刷新目录…") {
            let catalog = try await coordinator.refreshCatalog(from: url) { [weak self] pageNumber in
                self?.loadingMessage = "正在刷新目录…（第 \(pageNumber) 页）"
            }
            upsertCatalog(catalog, into: book)
            book.title = catalog.title
            book.author = catalog.author
            book.catalogFetchedAt = .now
            book.updatedAt = .now
            try modelContext.save()
            refreshBooks()
            rebuildSelectedBookChapters()
            updateChapterNavigationSnapshot()
        }
    }

    func startRefreshSelectedCatalog() {
        guard !isLoading else { return }
        catalogRefreshTask = Task { [weak self] in
            guard let self else { return }
            await refreshSelectedCatalog()
            catalogRefreshTask = nil
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

    func updateProgress(chapterID: UUID, paragraphIndex: Int, total: Int) {
        updateProgress(
            chapterID: chapterID,
            paragraphIndex: paragraphIndex,
            total: total,
            updatesCurrentChapter: true
        )
    }

    private func updateProgress(
        chapterID: UUID,
        paragraphIndex: Int,
        total: Int,
        updatesCurrentChapter: Bool
    ) {
        guard paragraphIndex >= 0,
              let chapter = selectedBook?.chapters.first(where: { $0.id == chapterID }) else { return }
        chapter.topParagraphIndex = max(0, paragraphIndex)
        chapter.readingProgress = total > 1
            ? min(max(Double(paragraphIndex) / Double(total - 1), 0), 1)
            : 0
        chapter.lastReadAt = .now
        if updatesCurrentChapter {
            chapter.book?.currentChapterID = chapter.id
        }
        scheduleProgressSave()
    }

    @discardableResult
    func flushPendingProgress() -> Bool {
        progressSaveTask?.cancel()
        progressSaveTask = nil
        return persistPendingProgress()
    }

    @discardableResult
    func deleteSelectedBook() -> Bool {
        guard let book = selectedBook else { return false }
        guard flushPendingProgress() else { return false }
        readerScrollRequest = nil
        modelContext.delete(book)
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            presentedError = PresentedError(message: "删除小说失败：\(error.localizedDescription)")
            return false
        }
        refreshBooks()
        selectedBookID = books.first?.id
        rebuildSelectedBookChapters()
        selectInitialChapter(preferredID: nil)
        return true
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
            updateChapterNavigationSnapshot()
            refreshReaderSession()
            schedulePrefetch(after: chapter)
        }
    }

    private func startOfflineDownload(_ scope: OfflineDownloadScope) {
        guard let book = selectedBook, let chapter = selectedChapter else { return }
        if !book.hasCatalog {
            guard case .currentChapter = scope else { return }
        }
        offlineDownloads.start(book: book, currentChapter: chapter, scope: scope)
    }

    private func startContinuousLoad(for chapter: Chapter) {
        guard !chapter.isCached,
              continuousLoadTasks[chapter.id] == nil,
              let url = URL(string: chapter.sourceURL) else {
            return
        }

        continuousLoadTasks[chapter.id] = Task { [weak self] in
            guard let self else { return }
            defer { continuousLoadTasks[chapter.id] = nil }
            do {
                let result = try await coordinator.loadChapterContent(from: url)
                guard !Task.isCancelled else { return }
                apply(result, to: chapter)
                try modelContext.save()
                continuousLoadFailures.remove(chapter.id)
                attachPendingContinuousChapterIfSafe()
            } catch is CancellationError {
                return
            } catch HTMLLoadError.cancelled {
                return
            } catch {
                continuousLoadFailures.insert(chapter.id)
            }
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
            guard !Task.isCancelled, let self else { return }
            self.startContinuousLoad(for: next)
        }
    }

    private func navigate(to urlString: String?, fallbackOffset: Int) {
        if let chapter = chapterForURL(urlString) {
            selectChapter(chapter.id, scrollIntent: .chapterTop)
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
            rebuildSelectedBookChapters()
            saveChanges(failureMessage: "保存章节失败")
            selectChapter(chapter.id, scrollIntent: .chapterTop)
            return
        }
        let chapters = sortedChapters
        guard let selectedChapter,
              let index = chapters.firstIndex(where: { $0.id == selectedChapter.id }) else { return }
        let nextIndex = index + fallbackOffset
        guard chapters.indices.contains(nextIndex) else { return }
        selectChapter(chapters[nextIndex].id, scrollIntent: .chapterTop)
    }

    private func chapterForURL(_ urlString: String?) -> Chapter? {
        guard let urlString else { return nil }
        return selectedBook?.chapters.first { chapter in
            chapter.sourceURL == urlString || canonicalURLString(chapter.sourceURL) == canonicalURLString(urlString)
        }
    }

    private func neighbor(of chapter: Chapter, offset: Int) -> Chapter? {
        guard let index = sortedChapters.firstIndex(where: { $0.id == chapter.id }) else {
            return nil
        }
        let targetIndex = index + offset
        if sortedChapters.indices.contains(targetIndex) {
            return sortedChapters[targetIndex]
        }

        let linkedURL = offset > 0 ? chapter.nextURL : chapter.previousURL
        guard let linkedURL, let book = selectedBook else { return nil }
        if let existing = chapterForURL(linkedURL) { return existing }

        let generated = Chapter(
            sourceURL: linkedURL,
            title: offset > 0 ? "下一章" : "上一章",
            sortIndex: chapter.sortIndex + offset,
            book: nil
        )
        modelContext.insert(generated)
        book.chapters.append(generated)
        generated.book = book
        rebuildSelectedBookChapters()
        saveChanges(failureMessage: "保存章节失败")
        return generated
    }

    private func upsert(_ result: NovelImportResult) throws -> Chapter {
        let sourceBookURL = result.sourceBookURL.absoluteString
        let descriptor = FetchDescriptor<Book>(predicate: #Predicate { $0.catalogURL == sourceBookURL })
        let book = try modelContext.fetch(descriptor).first ?? Book(
            title: result.bookTitle,
            author: result.author,
            sourceHost: result.sourceBookURL.host ?? "",
            catalogURL: sourceBookURL
        )
        if book.modelContext == nil { modelContext.insert(book) }

        book.title = result.bookTitle
        book.author = result.author
        book.hasCatalog = result.hasCatalog
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
            updateChapterNavigationSnapshot()
            return
        }
        let preferred = preferredID.flatMap { id in book.chapters.first { $0.id == id } }
        let current = book.currentChapterID.flatMap { id in book.chapters.first { $0.id == id } }
        selectedChapterID = (preferred ?? current ?? sortedChapters.first)?.id
        updateChapterNavigationSnapshot()
    }

    private func rebuildSelectedBookChapters() {
        sortedChapters = selectedBook?.chapters.sorted { lhs, rhs in
            if lhs.sortIndex == rhs.sortIndex { return lhs.title < rhs.title }
            return lhs.sortIndex < rhs.sortIndex
        } ?? []
    }

    private func attachPendingContinuousChapterIfSafe() {
        guard continuousReadingEnabled,
              pendingContinuousAttachmentChapterID != nil,
              !isReaderScrolling,
              !visibilityGate.hasCommittedInCurrentTransaction,
              let pendingChapterID = pendingContinuousAttachmentChapterID,
              pendingChapterID == selectedChapterID,
              let pendingChapter = selectedBook?.chapters.first(where: { $0.id == pendingChapterID }),
              let next = neighbor(of: pendingChapter, offset: 1),
              next.isCached else {
            return
        }
        pendingContinuousAttachmentChapterID = nil
        readerSession.attachNext(next)
    }

    private func refreshReaderSession() {
        readerSession.reset(around: selectedChapter)
    }

    private func updateChapterNavigationSnapshot() {
        guard let chapter = selectedChapter else {
            chapterNavigationSnapshot = ReaderChapterNavigationSnapshot(
                chapterID: nil,
                index: nil,
                totalCount: sortedChapters.count,
                hasPrevious: false,
                hasNext: false
            )
            return
        }

        let index = sortedChapters.firstIndex { $0.id == chapter.id }
        chapterNavigationSnapshot = ReaderChapterNavigationSnapshot(
            chapterID: chapter.id,
            index: index,
            totalCount: sortedChapters.count,
            hasPrevious: chapter.previousURL != nil || (index ?? 0) > 0,
            hasNext: chapter.nextURL != nil || index.map { $0 + 1 < sortedChapters.count } == true
        )
    }

    private func scheduleProgressSave() {
        hasPendingProgressChanges = true
        progressSaveTask?.cancel()
        let delay = progressSaveDelay
        progressSaveTask = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch is CancellationError {
                return
            } catch {
                self?.presentedError = PresentedError(message: "安排阅读进度保存失败：\(error.localizedDescription)")
                return
            }
            guard let self else { return }
            self.progressSaveTask = nil
            _ = self.persistPendingProgress()
        }
    }

    private func persistPendingProgress() -> Bool {
        guard hasPendingProgressChanges else { return true }
        do {
            try modelContext.save()
            hasPendingProgressChanges = false
            return true
        } catch {
            presentedError = PresentedError(message: "保存阅读进度失败：\(error.localizedDescription)")
            return false
        }
    }

    private func saveChanges(failureMessage: String) {
        do {
            try modelContext.save()
        } catch {
            presentedError = PresentedError(message: "\(failureMessage)：\(error.localizedDescription)")
        }
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
