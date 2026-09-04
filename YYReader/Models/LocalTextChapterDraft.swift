import Foundation

struct LocalTextChapterDraft: Equatable, Sendable {
    let title: String
    let bodyText: String
    let sortIndex: Int
    let sourceURL: String
    let previousURL: String?
    let nextURL: String?
}
