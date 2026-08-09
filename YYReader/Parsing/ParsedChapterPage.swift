import Foundation

struct ParsedChapterPage: Sendable {
    let title: String
    let bookTitle: String?
    let author: String?
    let paragraphs: [String]
    let catalogURL: URL?
    let previousChapterURL: URL?
    let nextChapterURL: URL?
    let nextPageURL: URL?
}
