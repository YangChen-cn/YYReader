import Foundation

enum ReaderScrollTarget: Hashable {
    case chapterHeader(UUID)
    case paragraph(chapterID: UUID, index: Int)
    case chapterFooter(UUID)
}
