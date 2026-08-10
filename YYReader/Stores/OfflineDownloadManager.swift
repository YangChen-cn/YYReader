import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class OfflineDownloadManager {
    private let modelContext: ModelContext
    private let coordinator: NovelImportCoordinator
    private var task: Task<Void, Never>?

    private(set) var completedCount = 0
    private(set) var totalCount = 0
    private(set) var failureMessage: String?

    init(modelContext: ModelContext, coordinator: NovelImportCoordinator) {
        self.modelContext = modelContext
        self.coordinator = coordinator
    }

    var isDownloading: Bool { task != nil }

    var progressMessage: String {
        "正在下载 \(completedCount) / \(totalCount)"
    }

    func start(book: Book, currentChapter: Chapter, scope: OfflineDownloadScope) {
        guard task == nil else { return }
        let chapters = plannedChapters(book: book, currentChapter: currentChapter, scope: scope)
        guard !chapters.isEmpty else { return }
        completedCount = 0
        totalCount = chapters.count
        failureMessage = nil

        task = Task { [weak self] in
            guard let self else { return }
            await download(chapters)
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

    private func plannedChapters(
        book: Book,
        currentChapter: Chapter,
        scope: OfflineDownloadScope
    ) -> [Chapter] {
        let ordered = book.chapters.sorted { $0.sortIndex < $1.sortIndex }
        switch scope {
        case .currentChapter:
            return [currentChapter]
        case let .followingChapters(count):
            guard let index = ordered.firstIndex(where: { $0.id == currentChapter.id }) else {
                return [currentChapter]
            }
            let end = min(ordered.count, index + count + 1)
            return Array(ordered[index..<end])
        case .entireBook:
            return ordered
        }
    }

    private func download(_ chapters: [Chapter]) async {
        for chapter in chapters {
            guard !Task.isCancelled else { return }
            defer { completedCount += 1 }
            guard !chapter.isCached, let url = URL(string: chapter.sourceURL) else { continue }

            do {
                let result = try await coordinator.loadChapterContent(from: url)
                chapter.title = result.title
                chapter.bodyText = result.bodyText
                chapter.previousURL = result.previousChapterURL?.absoluteString
                chapter.nextURL = result.nextChapterURL?.absoluteString
                chapter.cachedAt = .now
                try modelContext.save()
            } catch is CancellationError {
                return
            } catch HTMLLoadError.cancelled {
                return
            } catch let error as HTMLLoadError {
                failureMessage = "下载已停止：\(error.localizedDescription)"
                return
            } catch {
                failureMessage = "下载已停止：\(error.localizedDescription)"
                return
            }
        }
    }
}
