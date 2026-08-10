import Foundation

enum ReaderScrollTarget: Hashable, Sendable {
    case chapterHeader(UUID)
    case paragraph(chapterID: UUID, index: Int)
    case chapterFooter(UUID)

    var chapterID: UUID {
        switch self {
        case let .chapterHeader(chapterID), let .chapterFooter(chapterID):
            chapterID
        case let .paragraph(chapterID, _):
            chapterID
        }
    }
}
