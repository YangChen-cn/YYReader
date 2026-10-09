import Foundation

struct MobilePaginationRequest: Hashable {
    let chapterID: UUID
    let layout: MobilePaginationLayout
    let contentRevision: Int
}
