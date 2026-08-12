import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class OfflineDownloadManager {
    private let modelContext: ModelContext
    private let coordinator: NovelImportCoordinator
    private let persistence: OfflineChapterPersistence
    private var task: Task<Void, Never>?

    private(set) var completedCount = 0
    private(set) var totalCount = 0
    private(set) var failedCount = 0
    private(set) var failureMessage: String?

    init(modelContext: ModelContext, coordinator: NovelImportCoordinator) {
        self.modelContext = modelContext
        self.coordinator = coordinator
        self.persistence = OfflineChapterPersistence(modelContainer: modelContext.container)
    }

    var isDownloading: Bool { task != nil }

    var progressMessage: String {
        "正在下载 \(completedCount) / \(totalCount)"
    }

    func start(book: Book, currentChapter: Chapter, scope: OfflineDownloadScope) {
        guard task == nil else { return }
        let items = plannedItems(book: book, currentChapter: currentChapter, scope: scope)
        guard !items.isEmpty else { return }
        completedCount = 0
        totalCount = items.count
        failedCount = 0
        failureMessage = nil

        task = Task { [weak self] in
            guard let self else { return }
            await download(items)
            task = nil
        }
    }

    func cancel() {
        task?.cancel()
    }

    func dismissFailure() {
        guard !isDownloading else { return }
        failureMessage = nil
    }

    private func plannedItems(
        book: Book,
        currentChapter: Chapter,
        scope: OfflineDownloadScope
    ) -> [OfflineDownloadItem] {
        let ordered = book.chapters.sorted { $0.sortIndex < $1.sortIndex }
        let chapters: [Chapter]
        switch scope {
        case .currentChapter:
            chapters = [currentChapter]
        case let .followingChapters(count):
            guard let index = ordered.firstIndex(where: { $0.id == currentChapter.id }) else {
                return [makeItem(currentChapter, currentChapterID: currentChapter.id)]
            }
            let end = min(ordered.count, index + count + 1)
            chapters = Array(ordered[index..<end])
        case .entireBook:
            chapters = ordered
        }
        return chapters.map { makeItem($0, currentChapterID: currentChapter.id) }
    }

    private func makeItem(_ chapter: Chapter, currentChapterID: UUID) -> OfflineDownloadItem {
        OfflineDownloadItem(
            chapterID: chapter.id,
            sourceURL: URL(string: chapter.sourceURL),
            isCached: chapter.isAvailableOffline,
            isCurrentChapter: chapter.id == currentChapterID
        )
    }

    private func download(_ items: [OfflineDownloadItem]) async {
        var failures: [String] = []
        for item in items {
            guard !Task.isCancelled else { return }
            defer { completedCount += 1 }
            guard !item.isCached else { continue }
            guard let url = item.sourceURL else {
                failedCount += 1
                failures.append("章节地址无效")
                continue
            }

            do {
                let result = try await coordinator.loadChapterContent(from: url)
                try Task.checkCancellation()
                let cachedAt = Date.now
                if item.isCurrentChapter {
                    try persistCurrentChapter(result, chapterID: item.chapterID, cachedAt: cachedAt)
                } else {
                    try await persistence.persist(result, chapterID: item.chapterID, cachedAt: cachedAt)
                    try updateOfflineMetadata(result, chapterID: item.chapterID, cachedAt: cachedAt)
                }
            } catch is CancellationError {
                return
            } catch HTMLLoadError.cancelled {
                return
            } catch {
                failedCount += 1
                failures.append(error.localizedDescription)
            }
        }
        if failedCount > 0 {
            let firstFailure = failures.first ?? "未知错误"
            failureMessage = "下载完成，\(failedCount) 章失败。首个错误：\(firstFailure)"
        }
    }

    private func persistCurrentChapter(
        _ result: ChapterLoadResult,
        chapterID: UUID,
        cachedAt: Date
    ) throws {
        let descriptor = FetchDescriptor<Chapter>(predicate: #Predicate { $0.id == chapterID })
        guard let chapter = try modelContext.fetch(descriptor).first else { return }
        chapter.title = result.title
        chapter.replaceBodyText(result.bodyText)
        chapter.previousURL = result.previousChapterURL?.absoluteString
        chapter.nextURL = result.nextChapterURL?.absoluteString
        chapter.cachedAt = cachedAt
        try modelContext.save()
    }

    func loadPersistedBody(chapterID: UUID) async throws -> String? {
        try await persistence.bodyText(chapterID: chapterID)
    }

    func clearPersistedBodies(chapterIDs: [UUID]) async throws {
        try await persistence.clearBodyText(chapterIDs: chapterIDs)
    }

    private func updateOfflineMetadata(
        _ result: ChapterLoadResult,
        chapterID: UUID,
        cachedAt: Date
    ) throws {
        let descriptor = FetchDescriptor<Chapter>(predicate: #Predicate { $0.id == chapterID })
        guard let chapter = try modelContext.fetch(descriptor).first else { return }
        chapter.title = result.title
        chapter.previousURL = result.previousChapterURL?.absoluteString
        chapter.nextURL = result.nextChapterURL?.absoluteString
        chapter.cachedAt = cachedAt
        try modelContext.save()
    }
}
