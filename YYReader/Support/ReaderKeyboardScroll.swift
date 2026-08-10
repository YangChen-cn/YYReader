import Foundation

enum ReaderKeyboardScroll {
    static func target(
        currentParagraphIndex: Int?,
        fallbackParagraphIndex: Int,
        paragraphCount: Int,
        offset: Int
    ) -> Int? {
        guard paragraphCount > 0 else { return nil }
        let current = currentParagraphIndex ?? fallbackParagraphIndex
        return min(max(current + offset, 0), paragraphCount - 1)
    }

    static func paragraphTargets(entries: [(chapterID: UUID, paragraphs: [String])]) -> [ReaderScrollTarget] {
        entries.flatMap { entry in
            entry.paragraphs.indices.map { ReaderScrollTarget.paragraph(chapterID: entry.chapterID, index: $0) }
        }
    }

    static func nextTarget(
        visibleTarget: ReaderScrollTarget?,
        selectedChapterID: UUID?,
        fallbackParagraphIndex: Int,
        targets: [ReaderScrollTarget],
        offset: Int
    ) -> ReaderScrollTarget? {
        guard !targets.isEmpty else { return nil }
        let currentIndex = visibleTarget.flatMap { targets.firstIndex(of: $0) }
            ?? targets.firstIndex(of: .paragraph(
                chapterID: selectedChapterID ?? targets[0].chapterID,
                index: fallbackParagraphIndex
            ))
            ?? 0
        let targetIndex = min(max(currentIndex + offset, 0), targets.count - 1)
        return targets[targetIndex]
    }
}

private extension ReaderScrollTarget {
    var chapterID: UUID {
        switch self {
        case let .chapterHeader(chapterID), let .chapterFooter(chapterID):
            return chapterID
        case let .paragraph(chapterID, _):
            return chapterID
        }
    }
}
