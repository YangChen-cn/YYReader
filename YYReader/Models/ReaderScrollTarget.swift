import Foundation

enum ReaderScrollTarget: Hashable, Sendable {
    case chapterHeader(UUID)
    case paragraph(chapterID: UUID, index: Int)
    case chapterFooter(UUID)

    static func restoredParagraph(chapterID: UUID, savedIndex: Int, paragraphCount: Int) -> Self {
        .paragraph(
            chapterID: chapterID,
            index: min(max(savedIndex, 0), max(paragraphCount - 1, 0))
        )
    }

    var chapterID: UUID {
        switch self {
        case let .chapterHeader(chapterID), let .chapterFooter(chapterID):
            chapterID
        case let .paragraph(chapterID, _):
            chapterID
        }
    }

    var positionWithinChapter: Int {
        switch self {
        case .chapterHeader:
            Int.min
        case let .paragraph(_, index):
            index
        case .chapterFooter:
            Int.max
        }
    }
}
