import Foundation

struct ParsedBookCatalog: Sendable {
    let title: String
    let author: String
    let chapters: [ChapterSeed]
    let nextPageURL: URL?
}
