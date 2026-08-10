import Foundation

struct NovelImportResult: Sendable {
    let bookTitle: String
    let author: String
    /// A stable book-level URL used to deduplicate imports, even when a catalog is absent.
    let sourceBookURL: URL
    let catalogURL: URL
    let hasCatalog: Bool
    let catalog: [ChapterSeed]
    let catalogIsComplete: Bool
    let chapterTitle: String
    let chapterURL: URL
    let bodyText: String
    let previousChapterURL: URL?
    let nextChapterURL: URL?
}
