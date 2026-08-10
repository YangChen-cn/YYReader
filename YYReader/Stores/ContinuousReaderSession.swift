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

    func updateVisibleChapter(_ chapterID: UUID) {
        visibleChapterID = chapterID
    }

    func updateFocusedParagraph(_ focus: ReaderParagraphFocus) {
        focusedParagraph = focus
    }

    func includeCachedNeighborhood(around chapter: Chapter?, in chapters: [Chapter]) {
        guard let chapter,
              let currentIndex = chapters.firstIndex(where: { $0.id == chapter.id }) else {
            return
        }

        let retainedIDs = Set(entries.map(\.chapter.id))
        let neighborhood = (max(chapters.startIndex, currentIndex - 1)...min(chapters.index(before: chapters.endIndex), currentIndex + 1))
        let candidateIndices = chapters.indices.filter { index in
            retainedIDs.contains(chapters[index].id) || neighborhood.contains(index)
        }

        var retained = candidateIndices.filter { chapters[$0].isCached }
        let visibleIndex = visibleChapterID.flatMap { visibleID in
            chapters.firstIndex(where: { $0.id == visibleID })
        } ?? currentIndex

        // Keep a small overlap while the viewport advances. The oldest chapter is
        // only removed after the reader has moved far enough to grow beyond five.
        while retained.count > 5 {
            guard let farthestIndex = retained.max(by: { lhs, rhs in
                let lhsDistance = abs(lhs - visibleIndex)
                let rhsDistance = abs(rhs - visibleIndex)
                if lhsDistance == rhsDistance { return lhs < rhs }
                return lhsDistance < rhsDistance
            }) else {
                break
            }
            retained.removeAll { $0 == farthestIndex }
        }

        entries = retained.map { Entry(chapter: chapters[$0], paragraphs: chapters[$0].paragraphs) }
    }
}
