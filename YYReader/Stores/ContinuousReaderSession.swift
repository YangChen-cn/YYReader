import Foundation
import Observation

@MainActor
@Observable
final class ContinuousReaderSession {
    struct Entry: Identifiable {
        let chapter: Chapter
        let paragraphs: [String]

        var id: UUID { chapter.id }
    }

    private(set) var entries: [Entry] = []
    private(set) var visibleChapterID: UUID?

    func reset(around chapter: Chapter?) {
        guard let chapter, chapter.isCached else {
            entries = []
            visibleChapterID = nil
            return
        }

        entries = [Entry(chapter: chapter, paragraphs: chapter.paragraphs)]
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
        entries.append(Entry(chapter: chapter, paragraphs: chapter.paragraphs))
    }

    func trim(toChapterIDs chapterIDs: Set<UUID>) {
        entries.removeAll { !chapterIDs.contains($0.chapter.id) }
    }
}
