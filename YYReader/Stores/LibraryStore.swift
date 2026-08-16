import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class LibraryStore {
    private static let maximumPrefetchChapterCount = 3

    private let modelContext: ModelContext
    private let coordinator: NovelImportCoordinator
    private let folderSync: FolderSyncController?
    private let progressSaveDelay: Duration
    private var prefetchTask: Task<Void, Never>?
    private var prefetchRequestID: UUID?
    private var prefetchOriginChapterID: UUID?
    private var importTask: Task<Void, Never>?
    private var catalogRefreshTask: Task<Void, Never>?
    private var progressSaveTask: Task<Void, Never>?
    private var continuousLoadTasks: [UUID: Task<Void, Never>] = [:]
    private var continuousLoadFailures: Set<UUID> = []
    private var continuousTailProbeTasks: [UUID: Task<Void, Never>] = [:]
    private var continuousTailProbeStates: [UUID: ContinuousReaderTailProbeState] = [:]
    private var visibleChapterDebounceTask: Task<Void, Never>?
    private var visibilityGate = ContinuousReaderVisibilityGate()
    private var pendingContinuousAttachmentChapterID: UUID?
    private var isReaderScrolling = false
    private var hasPendingProgressChanges = false
    private var isReaderPresented = false
    private var deferredRemoteTombstones: [String: SyncBookRecord] = [:]
    private var cachedSyncChapterRanks: SyncMerger.ChapterRanksByBook?
    private let continuousTailProbeTTL: TimeInterval

    let readerSession = ContinuousReaderSession()
    let offlineDownloads: OfflineDownloadManager
    private(set) var books: [Book] = []
    private(set) var sortedChapters: [Chapter] = []
    private(set) var chapterByID: [UUID: Chapter] = [:]
    private(set) var chapterIndexByID: [UUID: Int] = [:]
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
        folderSync: FolderSyncController? = nil,
        progressSaveDelay: Duration = .milliseconds(600),
        continuousTailProbeTTL: TimeInterval = 45
    ) {
        self.modelContext = modelContext
        self.coordinator = coordinator
        self.folderSync = folderSync
        self.progressSaveDelay = progressSaveDelay
        self.continuousTailProbeTTL = continuousTailProbeTTL
        self.offlineDownloads = OfflineDownloadManager(modelContext: modelContext, coordinator: coordinator)
        refreshBooks()
    }

    var selectedBook: Book? {
        books.first { $0.id == selectedBookID }
    }

    var selectedChapter: Chapter? {
        selectedChapterID.flatMap { chapterByID[$0] }
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
        prefetchNextContinuousChapterIfNeeded()
        requestReaderScroll(.restore)
    }

    func beginReaderPresentation() {
        isReaderPresented = true
    }

    func endReaderPresentation() {
        isReaderPresented = false
        guard !deferredRemoteTombstones.isEmpty else { return }
        let records = Array(deferredRemoteTombstones.values)
        deferredRemoteTombstones.removeAll()
        do {
            try applySyncRecords(records)
        } catch {
            for record in records {
                deferredRemoteTombstones[record.canonicalSourceURL] = record
            }
            presentedError = PresentedError(message: "应用延迟的同步删除失败：\(error.localizedDescription)")
        }
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
        cancelContinuousTailProbes()
        selectedBookID = id
        rebuildSelectedBookChapters()
        selectInitialChapter(preferredID: nil)
        refreshReaderSession()
        prefetchNextContinuousChapterIfNeeded()
    }

    func selectChapter(_ id: UUID?, scrollIntent: ReaderScrollIntent? = nil) {
        applyChapterSelection(id, scrollIntent: scrollIntent, restoringOnFailure: selectedChapterID)
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
        cancelPrefetch()
        cancelContinuousTailProbes()
        selectedChapterID = id
        guard let chapter = selectedChapter else {
            updateChapterNavigationSnapshot()
            return
        }
        selectedBook?.currentChapterID = chapter.id
        updateChapterNavigationSnapshot()
        refreshReaderSession()
        prefetchNextContinuousChapterIfNeeded()
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
        guard !isLoading,
              !offlineDownloads.isDownloading,
              let book = selectedBook,
              let chapter = selectedChapter,
              book.hasCatalog,
              let catalogURL = URL(string: book.catalogURL) else {
            return
        }
        catalogRefreshTask = Task { [weak self] in
            guard let self else { return }
            await performLoading("正在获取完整目录…") {
                let catalog = try await coordinator.refreshCatalog(from: catalogURL) { [weak self] pageNumber in
                    self?.loadingMessage = "正在获取完整目录…（第 \(pageNumber) 页）"
                }
                try applyRefreshedCatalog(catalog, to: book)
                offlineDownloads.start(book: book, currentChapter: chapter, scope: .entireBook)
            }
            catalogRefreshTask = nil
        }
    }

    func deleteOfflineCache() {
        guard let book = selectedBook else { return }
        let retainedChapterID = selectedChapterID
        let chapters = book.chapters.filter { $0.id != retainedChapterID }
        let chapterIDs = chapters.map(\.id)
        Task { [weak self] in
            guard let self else { return }
            do {
                try await offlineDownloads.clearPersistedBodies(chapterIDs: chapterIDs)
                for chapter in chapters {
                    chapter.replaceBodyText(nil)
                    chapter.cachedAt = nil
                }
                try modelContext.save()
                refreshReaderSession()
            } catch {
                presentedError = PresentedError(message: "删除离线缓存失败：\(error.localizedDescription)")
            }
        }
    }

    func configureContinuousReading(_ isEnabled: Bool) {
        guard continuousReadingEnabled != isEnabled else { return }
        continuousReadingEnabled = isEnabled
        if !isEnabled { cancelPrefetch() }
        cancelContinuousTailProbes()
        candidateVisibleChapterID = nil
        visibleChapterDebounceTask?.cancel()
        pendingContinuousAttachmentChapterID = nil
        refreshReaderSession()
        prefetchNextContinuousChapterIfNeeded()
    }

    func prepareContinuousReading() {
        refreshReaderSession()
        prefetchNextContinuousChapterIfNeeded()
    }

    func resetContinuousReaderWindow() {
        pendingContinuousAttachmentChapterID = nil
        refreshReaderSession()
    }

    func prefetchContinuousChapter(after chapterID: UUID) {
        guard let chapter = chapterByID[chapterID] else { return }
        scheduleSerialPrefetch(after: chapter, delay: nil, respectsPreference: false)
    }

    func prepareContinuousChapterAttachment(after chapterID: UUID) {
        guard continuousReadingEnabled,
              chapterID == selectedChapterID,
              let chapter = chapterByID[chapterID] else {
            return
        }

        pendingContinuousAttachmentChapterID = chapterID
        guard let next = neighbor(of: chapter, offset: 1) else {
            startContinuousTailProbe(for: chapter)
            return
        }
        prefetchContinuousChapter(after: chapterID)
        guard next.isCached else { return }
        attachPendingContinuousChapterIfSafe()
    }

    func retryContinuousChapter(after chapterID: UUID) {
        guard let chapter = chapterByID[chapterID] else { return }
        if let next = neighbor(of: chapter, offset: 1) {
            continuousLoadFailures.remove(next.id)
            startContinuousLoad(for: next)
        } else {
            continuousTailProbeStates.removeValue(forKey: chapterID)
            startContinuousTailProbe(for: chapter, bypassingTTL: true)
        }
    }

    func continuationStatus(after chapterID: UUID) -> ReaderContinuationStatus {
        guard let chapter = chapterByID[chapterID] else {
            return .unavailable
        }
        guard let next = existingNeighbor(of: chapter, offset: 1) else {
            // A catalog-less chapter may only expose nextURL. The boundary's
            // onAppear action will create and prefetch that chapter outside the
            // SwiftUI body evaluation; this status query must remain read-only.
            if chapter.nextURL != nil { return .idle }
            guard isLocalCatalogTail(chapter) else { return .unavailable }
            switch continuousTailProbeStates[chapterID] {
            case .checking:
                return .checkingLatest
            case let .confirmedLatest(expiresAt) where expiresAt > .now:
                return .confirmedLatest
            case .failed:
                return .failed
            case .confirmedLatest, nil:
                return .idle
            }
        }
        if next.isCached { return .ready }
        if continuousLoadFailures.contains(next.id) { return .failed }
        return continuousLoadTasks[next.id] == nil ? .idle : .loading
    }

    func updateVisibleReaderPosition(chapterID: UUID, paragraphIndex: Int, total: Int) {
        guard let chapter = chapterByID[chapterID] else { return }
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
        visibilityGate.beginTransaction()
    }

    func endReaderScrollTransaction(topVisibleChapterID _: UUID?) {
        isReaderScrolling = false
        attachPendingContinuousChapterIfSafe()
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
        guard let chapter = chapterByID[chapterID],
              visibilityGate.accepts(
                candidateID: chapterID,
                currentID: selectedChapterID,
                chapterIndexByID: chapterIndexByID
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
        prefetchNextContinuousChapterIfNeeded()
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
            folderSync?.scheduleLocalChange()
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
            try applyRefreshedCatalog(catalog, to: book)
        }
    }

    private func applyRefreshedCatalog(_ catalog: ParsedBookCatalog, to book: Book) throws {
        upsertCatalog(catalog, into: book)
        book.title = catalog.title
        book.author = catalog.author
        book.catalogFetchedAt = .now
        book.updatedAt = .now
        try modelContext.save()
        refreshBooks()
        if selectedBookID == book.id {
            rebuildSelectedBookChapters()
            updateChapterNavigationSnapshot()
        }
        folderSync?.scheduleLocalChange()
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
              let chapter = chapterByID[chapterID] else { return }
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
        let deletionRecord = syncRecord(for: book, deletedAt: .now)
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
        folderSync?.recordDeletion(deletionRecord)
        folderSync?.scheduleLocalChange()
        return true
    }

    func syncRecords() -> [SyncBookRecord] {
        books
            .map { syncRecord(for: $0) }
            .sorted { $0.canonicalSourceURL < $1.canonicalSourceURL }
    }

    func syncChapterRanks() -> SyncMerger.ChapterRanksByBook {
        if let cachedSyncChapterRanks { return cachedSyncChapterRanks }
        var result: SyncMerger.ChapterRanksByBook = [:]
        for book in books {
            var ranks: [String: Int] = [:]
            for chapter in book.chapters {
                ranks[URLCanonicalizer.canonicalChapterString(chapter.sourceURL)] = chapter.sortIndex
            }
            result[URLCanonicalizer.canonicalString(book.sourceBookURL)] = ranks
        }
        cachedSyncChapterRanks = result
        return result
    }

    func bookshelfTransferDocument(exportedAt: Date = .now) -> BookshelfTransferDocument {
        BookshelfTransferDocument(
            exportedAt: exportedAt,
            books: books
                .map(BookshelfTransferBook.init(book:))
                .sorted {
                    URLCanonicalizer.canonicalString($0.sourceURL)
                        < URLCanonicalizer.canonicalString($1.sourceURL)
                }
        )
    }

    func previewBookshelfTransfer(_ document: BookshelfTransferDocument) -> BookshelfTransferPreview {
        BookshelfTransferPlanner.preview(
            document: document,
            existingSourceURLs: Set(books.map(\.sourceBookURL))
        )
    }

    func importBookshelfTransfer(
        _ document: BookshelfTransferDocument,
        preview: BookshelfTransferPreview? = nil,
        importedAt: Date = .now
    ) throws -> BookshelfTransferImportSummary {
        guard flushPendingProgress() else {
            throw BookshelfTransferError.invalidDocument("保存当前阅读位置失败，书架尚未导入。")
        }
        let preview = preview ?? previewBookshelfTransfer(document)
        var bookByCanonicalURL: [String: Book] = [:]
        for book in books {
            bookByCanonicalURL[URLCanonicalizer.canonicalString(book.sourceBookURL)] = book
        }

        var succeeded = 0
        var skipped = 0
        var failures: [String] = []
        for entry in preview.entries {
            switch entry.status {
            case .duplicateInFile:
                skipped += 1
            case .invalid:
                let source = entry.book.sourceURL.isEmpty ? "缺少 sourceURL" : entry.book.sourceURL
                failures.append("\(source)：\(entry.error ?? "数据无效。")")
            case .new, .existing:
                applyBookshelfTransferBook(
                    entry.book,
                    to: &bookByCanonicalURL,
                    importedAt: importedAt
                )
                succeeded += 1
            }
        }

        do {
            if modelContext.hasChanges {
                try modelContext.save()
            }
        } catch {
            modelContext.rollback()
            throw error
        }
        refreshBooks()
        rebuildSelectedBookChapters()
        selectInitialChapter(preferredID: selectedChapterID)
        refreshReaderSession()
        folderSync?.scheduleLocalChange()

        return BookshelfTransferImportSummary(
            succeeded: succeeded,
            skipped: skipped,
            failed: failures.count,
            failures: failures
        )
    }

    func applySyncRecords(_ records: [SyncBookRecord]) throws {
        let previousBookID = selectedBookID
        let previousChapterID = selectedChapterID
        let previousBookCurrentChapterID = selectedBook?.currentChapterID
        let previousBookCurrentChapter = previousBookCurrentChapterID.flatMap { chapterID in
            selectedBook?.chapters.first { $0.id == chapterID }
        }
        let previousBookParagraphIndex = previousBookCurrentChapter?.topParagraphIndex
        let previousBookProgress = previousBookCurrentChapter?.readingProgress
        let canPreserveReaderSession = previousChapterID.map { chapterID in
            readerSession.entries.contains { $0.chapter.id == chapterID }
        } ?? false
        let chapterRanksByBook = syncChapterRanks()
        let mergedRecords = SyncMerger.merge(
            syncRecords() + records,
            chapterRanksByBook: chapterRanksByBook
        )
        var bookByCanonicalURL: [String: Book] = [:]
        for book in books {
            bookByCanonicalURL[URLCanonicalizer.canonicalString(book.sourceBookURL)] = book
        }

        for record in mergedRecords {
            let key = record.canonicalSourceURL
            if record.isDeleted {
                if let book = bookByCanonicalURL.removeValue(forKey: key) {
                    if isReaderPresented, book.id == selectedBookID {
                        deferredRemoteTombstones[key] = record
                        bookByCanonicalURL[key] = book
                        continue
                    }
                    modelContext.delete(book)
                }
                continue
            }
            deferredRemoteTombstones.removeValue(forKey: key)

            let book: Book
            if let existing = bookByCanonicalURL[key] {
                book = existing
            } else {
                let sourceURL = URL(string: key)
                book = Book(
                    title: record.title,
                    author: record.author,
                    sourceHost: sourceURL?.host ?? "",
                    catalogURL: key,
                    createdAt: record.updatedAt,
                    updatedAt: record.updatedAt,
                    hasCatalog: false
                )
                modelContext.insert(book)
                bookByCanonicalURL[key] = book
            }

            if record.updatedAt >= book.updatedAt,
               (book.title != record.title
                || book.author != record.author
                || book.updatedAt != record.updatedAt) {
                book.title = record.title
                book.author = record.author
                book.updatedAt = record.updatedAt
            }
            applySyncedReadingPosition(record, to: book)
        }

        guard modelContext.hasChanges else { return }
        try modelContext.save()
        refreshBooks()
        selectedBookID = books.contains { $0.id == previousBookID } ? previousBookID : books.first?.id
        rebuildSelectedBookChapters()
        let synchronizedPositionChanged = selectedBookID == previousBookID
            && selectedBookReadingPositionChanged(
                fromChapterID: previousBookCurrentChapterID,
                paragraphIndex: previousBookParagraphIndex,
                progress: previousBookProgress
            )
        selectInitialChapter(preferredID: synchronizedPositionChanged ? nil : previousChapterID)
        let didPreserveSelection = selectedBookID == previousBookID
            && selectedChapterID == previousChapterID
        if synchronizedPositionChanged {
            refreshReaderSession()
            requestReaderScroll(.restore)
            prefetchNextContinuousChapterIfNeeded()
        } else if !didPreserveSelection || !canPreserveReaderSession {
            refreshReaderSession()
        }
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
        guard !chapter.isCached else { return }
        if chapter.isAvailableOffline,
           let bodyText = try? await offlineDownloads.loadPersistedBody(chapterID: chapter.id),
           !bodyText.isEmpty {
            chapter.replaceBodyText(bodyText)
            refreshReaderSession()
            return
        }
        guard let url = URL(string: chapter.sourceURL) else { return }
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

    @discardableResult
    private func startContinuousLoad(for chapter: Chapter) -> Task<Void, Never>? {
        guard !chapter.isCached else { return nil }
        if let task = continuousLoadTasks[chapter.id] { return task }
        guard let url = URL(string: chapter.sourceURL) else { return nil }

        let task = Task { [weak self] in
            guard let self else { return }
            defer { continuousLoadTasks[chapter.id] = nil }
            do {
                if chapter.isAvailableOffline,
                   let bodyText = try await offlineDownloads.loadPersistedBody(chapterID: chapter.id),
                   !bodyText.isEmpty {
                    chapter.replaceBodyText(bodyText)
                    continuousLoadFailures.remove(chapter.id)
                    attachPendingContinuousChapterIfSafe()
                    return
                }
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
        continuousLoadTasks[chapter.id] = task
        return task
    }

    private func startContinuousTailProbe(for chapter: Chapter, bypassingTTL: Bool = false) {
        guard continuousReadingEnabled,
              chapter.id == selectedChapterID,
              isLocalCatalogTail(chapter),
              chapter.nextURL == nil,
              continuousTailProbeTasks[chapter.id] == nil,
              let url = URL(string: chapter.sourceURL) else {
            return
        }
        if !bypassingTTL,
           case let .confirmedLatest(expiresAt) = continuousTailProbeStates[chapter.id],
           expiresAt > .now {
            return
        }

        continuousTailProbeStates[chapter.id] = .checking
        continuousTailProbeTasks[chapter.id] = Task { [weak self] in
            guard let self else { return }
            defer { continuousTailProbeTasks[chapter.id] = nil }
            do {
                let result = try await coordinator.loadChapterContent(from: url)
                guard !Task.isCancelled else { return }
                chapter.title = result.title
                chapter.previousURL = result.previousChapterURL?.absoluteString
                chapter.nextURL = result.nextChapterURL?.absoluteString
                chapter.cachedAt = chapter.cachedAt ?? .now
                try modelContext.save()

                guard result.nextChapterURL != nil else {
                    continuousTailProbeStates[chapter.id] = .confirmedLatest(
                        expiresAt: Date.now.addingTimeInterval(continuousTailProbeTTL)
                    )
                    return
                }
                continuousTailProbeStates.removeValue(forKey: chapter.id)
                guard let next = neighbor(of: chapter, offset: 1) else { return }
                startContinuousLoad(for: next)
                if next.isCached { attachPendingContinuousChapterIfSafe() }
            } catch is CancellationError {
                return
            } catch HTMLLoadError.cancelled {
                return
            } catch {
                continuousTailProbeStates[chapter.id] = .failed
            }
        }
    }

    private func cancelContinuousTailProbes() {
        for task in continuousTailProbeTasks.values { task.cancel() }
        continuousTailProbeTasks.removeAll()
        continuousTailProbeStates.removeAll()
    }

    private func isLocalCatalogTail(_ chapter: Chapter) -> Bool {
        sortedChapters.last?.id == chapter.id
    }

    private func schedulePrefetch(after chapter: Chapter) {
        scheduleSerialPrefetch(after: chapter, delay: .seconds(1), respectsPreference: true)
    }

    private func scheduleSerialPrefetch(
        after chapter: Chapter,
        delay: Duration?,
        respectsPreference: Bool
    ) {
        guard prefetchTask == nil || prefetchOriginChapterID != chapter.id else { return }
        cancelPrefetch()
        if respectsPreference {
            guard UserDefaults.standard.object(forKey: ReaderPreferenceKeys.prefetchNext) as? Bool ?? true else {
                return
            }
        }

        let requestID = UUID()
        prefetchRequestID = requestID
        prefetchOriginChapterID = chapter.id
        prefetchTask = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            if let delay {
                do {
                    try await Task.sleep(for: delay)
                } catch {
                    finishPrefetch(requestID: requestID)
                    return
                }
            }
            guard !Task.isCancelled else {
                finishPrefetch(requestID: requestID)
                return
            }
            await prefetchFollowingChapters(after: chapter.id)
            finishPrefetch(requestID: requestID)
        }
    }

    private func prefetchFollowingChapters(after chapterID: UUID) async {
        guard var cursor = chapterByID[chapterID] else { return }

        for _ in 0..<Self.maximumPrefetchChapterCount {
            guard !Task.isCancelled,
                  let next = neighbor(of: cursor, offset: 1) else {
                return
            }
            cursor = next
            if next.isCached { continue }

            let existingTask = continuousLoadTasks[next.id]
            guard let loadTask = startContinuousLoad(for: next) else { continue }
            if existingTask == nil {
                await withTaskCancellationHandler {
                    await loadTask.value
                } onCancel: {
                    loadTask.cancel()
                }
            } else {
                await loadTask.value
            }

            guard next.isCached else { return }
        }
    }

    private func cancelPrefetch() {
        prefetchTask?.cancel()
        prefetchTask = nil
        prefetchRequestID = nil
        prefetchOriginChapterID = nil
    }

    private func finishPrefetch(requestID: UUID) {
        guard prefetchRequestID == requestID else { return }
        prefetchTask = nil
        prefetchRequestID = nil
        prefetchOriginChapterID = nil
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
              let index = chapterIndexByID[selectedChapter.id] else { return }
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
        if let existing = existingNeighbor(of: chapter, offset: offset) {
            return existing
        }

        let linkedURL = offset > 0 ? chapter.nextURL : chapter.previousURL
        guard let linkedURL, let book = selectedBook else { return nil }

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

    private func existingNeighbor(of chapter: Chapter, offset: Int) -> Chapter? {
        guard let index = chapterIndexByID[chapter.id] else {
            return nil
        }
        let targetIndex = index + offset
        if sortedChapters.indices.contains(targetIndex) {
            return sortedChapters[targetIndex]
        }

        let linkedURL = offset > 0 ? chapter.nextURL : chapter.previousURL
        guard let linkedURL else { return nil }
        return chapterForURL(linkedURL)
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
        chapter.replaceBodyText(result.bodyText)
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
        chapter.replaceBodyText(result.bodyText)
        chapter.previousURL = result.previousChapterURL?.absoluteString
        chapter.nextURL = result.nextChapterURL?.absoluteString
        chapter.cachedAt = .now
        promoteCatalogIfSafe(from: result, for: chapter)
    }

    private func promoteCatalogIfSafe(from result: ChapterLoadResult, for chapter: Chapter) {
        guard let book = chapter.book,
              !book.hasCatalog,
              let catalogURL = result.catalogURL,
              let identityURL = URL(string: book.sourceBookURL),
              ["http", "https"].contains(identityURL.scheme?.lowercased() ?? ""),
              URLCanonicalizer.canonicalString(book.sourceBookURL)
                == URLCanonicalizer.canonicalString(catalogURL.absoluteString) else {
            return
        }
        book.catalogURL = catalogURL.absoluteString
        book.hasCatalog = true
        book.updatedAt = .now
    }

    private func selectInitialChapter(preferredID: UUID?) {
        guard let book = selectedBook else {
            selectedChapterID = nil
            updateChapterNavigationSnapshot()
            return
        }
        let preferred = preferredID.flatMap { chapterByID[$0] }
        let current = book.currentChapterID.flatMap { chapterByID[$0] }
        selectedChapterID = (preferred ?? current ?? sortedChapters.first)?.id
        updateChapterNavigationSnapshot()
    }

    private func rebuildSelectedBookChapters() {
        cachedSyncChapterRanks = nil
        sortedChapters = selectedBook?.chapters.sorted { lhs, rhs in
            if lhs.sortIndex == rhs.sortIndex { return lhs.title < rhs.title }
            return lhs.sortIndex < rhs.sortIndex
        } ?? []
        chapterByID = Dictionary(uniqueKeysWithValues: sortedChapters.map { ($0.id, $0) })
        chapterIndexByID = Dictionary(uniqueKeysWithValues: sortedChapters.enumerated().map { ($0.element.id, $0.offset) })
    }

    private func prefetchNextContinuousChapterIfNeeded() {
        guard continuousReadingEnabled, let chapterID = selectedChapterID else { return }
        prefetchContinuousChapter(after: chapterID)
    }

    private func attachPendingContinuousChapterIfSafe() {
        guard continuousReadingEnabled,
              pendingContinuousAttachmentChapterID != nil,
              !isReaderScrolling,
              !visibilityGate.hasCommittedInCurrentTransaction,
              let pendingChapterID = pendingContinuousAttachmentChapterID,
              pendingChapterID == selectedChapterID,
              let pendingChapter = chapterByID[pendingChapterID],
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

    private func selectedBookReadingPositionChanged(
        fromChapterID previousChapterID: UUID?,
        paragraphIndex previousParagraphIndex: Int?,
        progress previousProgress: Double?
    ) -> Bool {
        guard let book = selectedBook else { return previousChapterID != nil }
        let currentChapterID = book.currentChapterID
        guard currentChapterID == previousChapterID else { return true }
        guard let currentChapterID,
              let chapter = chapterByID[currentChapterID] else {
            return previousParagraphIndex != nil || previousProgress != nil
        }
        return chapter.topParagraphIndex != previousParagraphIndex
            || chapter.readingProgress != previousProgress
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

        let index = chapterIndexByID[chapter.id]
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
            folderSync?.progressDidPersist()
            return true
        } catch {
            presentedError = PresentedError(message: "保存阅读进度失败：\(error.localizedDescription)")
            return false
        }
    }

    private func saveChanges(failureMessage: String) {
        do {
            try modelContext.save()
            folderSync?.scheduleLocalChange()
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
        URLCanonicalizer.canonicalChapterString(value)
    }

    private func syncRecord(for book: Book, deletedAt: Date? = nil) -> SyncBookRecord {
        let transfer = BookshelfTransferBook(book: book)
        let chapter = book.currentChapterID.flatMap { chapterID in
            book.chapters.first { $0.id == chapterID }
        }
        return SyncBookRecord(
            transfer: transfer,
            currentChapterIndex: chapter?.sortIndex,
            lastReadAt: chapter?.lastReadAt,
            updatedAt: book.updatedAt,
            deletedAt: deletedAt
        )
    }

    private func applyBookshelfTransferBook(
        _ transfer: BookshelfTransferBook,
        to bookByCanonicalURL: inout [String: Book],
        importedAt: Date
    ) {
        let key = URLCanonicalizer.canonicalString(transfer.sourceURL)
        let book: Book
        if let existing = bookByCanonicalURL[key] {
            book = existing
        } else {
            let url = URL(string: key)
            book = Book(
                title: transfer.title.trimmingCharacters(in: .whitespacesAndNewlines),
                author: transfer.author.trimmingCharacters(in: .whitespacesAndNewlines),
                sourceHost: url?.host ?? "",
                catalogURL: key,
                createdAt: importedAt,
                updatedAt: importedAt,
                hasCatalog: false
            )
            modelContext.insert(book)
            bookByCanonicalURL[key] = book
        }

        let title = transfer.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let author = transfer.author.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { book.title = title }
        if !author.isEmpty { book.author = author }
        book.updatedAt = importedAt

        guard let currentChapterURL = transfer.currentChapterURL else { return }
        let canonicalChapterURL = URLCanonicalizer.canonicalChapterString(currentChapterURL)
        let chapter = book.chapters.first {
            URLCanonicalizer.canonicalChapterString($0.sourceURL) == canonicalChapterURL
        } ?? {
            let chapter = Chapter(
                sourceURL: canonicalChapterURL,
                title: "当前章节",
                sortIndex: (book.chapters.map(\.sortIndex).max() ?? 0) + 1,
                book: nil
            )
            modelContext.insert(chapter)
            book.chapters.append(chapter)
            chapter.book = book
            return chapter
        }()

        book.currentChapterID = chapter.id
        if transfer.paragraphIndex != nil || transfer.progress != nil {
            chapter.topParagraphIndex = max(transfer.paragraphIndex ?? 0, 0)
            chapter.readingProgress = min(max(transfer.progress ?? 0, 0), 1)
            chapter.lastReadAt = importedAt
        }
    }

    private func applySyncedReadingPosition(_ record: SyncBookRecord, to book: Book) {
        guard let chapterURL = record.currentChapterURL else { return }
        let canonicalChapterURL = URLCanonicalizer.canonicalChapterString(chapterURL)
        let chapter = book.chapters.first {
            URLCanonicalizer.canonicalChapterString($0.sourceURL) == canonicalChapterURL
        } ?? {
            let chapter = Chapter(
                sourceURL: canonicalChapterURL,
                title: "当前章节",
                sortIndex: record.currentChapterIndex
                    ?? (book.chapters.map(\.sortIndex).max() ?? 0) + 1,
                book: nil
            )
            modelContext.insert(chapter)
            book.chapters.append(chapter)
            chapter.book = book
            return chapter
        }()

        if let currentChapter = book.currentChapterID.flatMap({ chapterID in
            book.chapters.first { $0.id == chapterID }
        }) {
            if currentChapter.id == chapter.id {
                let incomingParagraph = max(record.paragraphIndex ?? 0, 0)
                let incomingProgress = min(max(record.progress ?? 0, 0), 1)
                guard incomingParagraph > currentChapter.topParagraphIndex
                        || (incomingParagraph == currentChapter.topParagraphIndex
                            && incomingProgress >= currentChapter.readingProgress) else {
                    return
                }
            } else {
                let incomingIndex = record.currentChapterIndex ?? chapter.sortIndex
                guard incomingIndex > currentChapter.sortIndex else { return }
            }
        }
        let incomingParagraph = max(record.paragraphIndex ?? 0, 0)
        let incomingProgress = min(max(record.progress ?? 0, 0), 1)
        let mergedLastReadAt = [chapter.lastReadAt, record.lastReadAt].compactMap { $0 }.max()
        guard chapter.topParagraphIndex != incomingParagraph
                || chapter.readingProgress != incomingProgress
                || chapter.lastReadAt != mergedLastReadAt
                || book.currentChapterID != chapter.id else {
            return
        }
        chapter.topParagraphIndex = incomingParagraph
        chapter.readingProgress = incomingProgress
        chapter.lastReadAt = mergedLastReadAt
        book.currentChapterID = chapter.id
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
