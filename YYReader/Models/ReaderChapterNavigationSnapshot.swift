import Foundation

struct ReaderChapterNavigationSnapshot: Equatable, Sendable {
    let chapterID: UUID?
    let index: Int?
    let totalCount: Int
    let hasPrevious: Bool
    let hasNext: Bool

    static let empty = ReaderChapterNavigationSnapshot(
        chapterID: nil,
        index: nil,
        totalCount: 0,
        hasPrevious: false,
        hasNext: false
    )

    var positionText: String {
        guard let index else { return "共 \(totalCount) 章" }
        return "第 \(index + 1) / \(totalCount) 章"
    }
}
