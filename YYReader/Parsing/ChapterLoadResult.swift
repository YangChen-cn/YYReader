import Foundation

struct ChapterLoadResult: Sendable {
    let title: String
    let bookTitle: String?
    let catalogURL: URL?
    let chapterURL: URL
    let bodyText: String
    let previousChapterURL: URL?
    let nextChapterURL: URL?
}
