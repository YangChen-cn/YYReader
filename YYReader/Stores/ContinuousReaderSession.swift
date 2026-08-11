import Foundation
import Observation

@MainActor
@Observable
final class ContinuousReaderSession {
    struct Entry: Identifiable {
        let chapter: Chapter

        var id: UUID { chapter.id }
        // Keep the rendered identity stable without retaining another paragraph array
        // for every chapter visited during a long continuous-reading session.
        var paragraphs: [String] { chapter.paragraphs }
    }

    private(set) var entries: [Entry] = []
    private(set) var visibleChapterID: UUID?

    func reset(around chapter: Chapter?) {
        guard let chapter, chapter.isCached else {
            entries = []
            visibleChapterID = nil
            return
        }

        entries = [Entry(chapter: chapter)]
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
        entries.append(Entry(chapter: chapter))
    }

}
