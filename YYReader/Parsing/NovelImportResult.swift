import Foundation

struct NovelImportResult: Sendable {
    let bookTitle: String
    let author: String
    let catalogURL: URL
    let catalog: [ChapterSeed]
    let chapterTitle: String
    let chapterURL: URL
    let bodyText: String
    let previousChapterURL: URL?
    let nextChapterURL: URL?
}
