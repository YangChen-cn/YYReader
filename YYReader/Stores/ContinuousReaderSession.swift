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
    private(set) var focusedParagraph: ReaderParagraphFocus?

    func reset(around chapter: Chapter?, in chapters: [Chapter]) {
        guard let chapter,
              let index = chapters.firstIndex(where: { $0.id == chapter.id }) else {
            entries = []
            visibleChapterID = nil
            focusedParagraph = nil
            return
        }

        let lowerBound = max(chapters.startIndex, index - 1)
        let upperBound = min(chapters.index(before: chapters.endIndex), index + 1)
        entries = chapters[lowerBound...upperBound]
            .filter(\.isCached)
            .map { Entry(chapter: $0, paragraphs: $0.paragraphs) }
        visibleChapterID = chapter.id

        if let focusedParagraph,
           !entries.contains(where: { $0.chapter.id == focusedParagraph.chapterID }) {
            self.focusedParagraph = nil
        }
    }

    func updateVisibleChapter(_ chapterID: UUID, paragraphIndex: Int) {
        visibleChapterID = chapterID
        focusedParagraph = ReaderParagraphFocus(chapterID: chapterID, paragraphIndex: paragraphIndex)
    }
}
