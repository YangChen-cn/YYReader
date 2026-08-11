import Foundation
import Observation

@MainActor
@Observable
final class ContinuousReaderSession {
    struct Entry: Identifiable {
        let chapter: Chapter
        fileprivate let paragraphCache: ChapterParagraphCache

        var id: UUID { chapter.id }
        @MainActor var paragraphs: [String] { paragraphCache.paragraphs(for: chapter) }
    }

    private let paragraphCache: ChapterParagraphCache
    private(set) var entries: [Entry] = []
    private(set) var visibleChapterID: UUID?

    init(paragraphCacheCapacity: Int = 8) {
        paragraphCache = ChapterParagraphCache(capacity: paragraphCacheCapacity)
    }

    func reset(around chapter: Chapter?) {
        guard let chapter, chapter.isCached else {
            entries = []
            visibleChapterID = nil
            return
        }

        entries = [Entry(chapter: chapter, paragraphCache: paragraphCache)]
        visibleChapterID = chapter.id
    }

    func updateVisibleChapter(_ chapterID: UUID) {
        visibleChapterID = chapterID
    }

    func attachNext(_ chapter: Chapter) {
        guard chapter.isCached,
              !entries.contains(where: { $0.chapter.id == chapter.id }) else {
            return
        }
        entries.append(Entry(chapter: chapter, paragraphCache: paragraphCache))
    }

    func paragraphs(for chapter: Chapter) -> [String] {
        paragraphCache.paragraphs(for: chapter)
    }

    var cachedParagraphChapterCount: Int { paragraphCache.count }

}
