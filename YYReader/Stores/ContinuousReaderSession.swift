import Foundation
import Observation

@MainActor
@Observable
final class ContinuousReaderSession {
    // Reclaim in large batches so ordinary chapter transitions never mutate the
    // LazyVStack above the viewport. The visible chapter keeps a deep back buffer.
    static let maximumRetainedEntryCount = 30
    static let targetRetainedEntryCount = 20
    static let retainedEntriesBeforeVisibleChapter = 18
    static let minimumDistanceFromOldestEntry = 24

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

    @discardableResult
    func reclaimDistantEntries(around visibleChapterID: UUID) -> Bool {
        guard entries.count > Self.maximumRetainedEntryCount,
              let visibleIndex = entries.firstIndex(where: { $0.id == visibleChapterID }),
              visibleIndex >= Self.minimumDistanceFromOldestEntry else {
            return false
        }

        let countAllowedByVisibleDistance = visibleIndex - Self.retainedEntriesBeforeVisibleChapter
        let countNeededForTarget = entries.count - Self.targetRetainedEntryCount
        let removalCount = min(countAllowedByVisibleDistance, countNeededForTarget)
        guard removalCount > 0 else { return false }
        entries.removeFirst(removalCount)
        return true
    }

}
