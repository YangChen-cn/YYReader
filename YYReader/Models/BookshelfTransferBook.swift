import Foundation

struct BookshelfTransferBook: Codable, Equatable, Sendable {
    var sourceURL: String
    var title: String
    var author: String
    var currentChapterURL: String?
    var paragraphIndex: Int?
    var progress: Double?

    @MainActor
    init(book: Book) {
        let chapter = book.currentChapterID.flatMap { chapterID in
            book.chapters.first { $0.id == chapterID }
        }
        sourceURL = URLCanonicalizer.canonicalString(book.sourceBookURL)
        title = book.title
        author = book.author
        currentChapterURL = chapter.map { URLCanonicalizer.canonicalChapterString($0.sourceURL) }
        paragraphIndex = chapter?.topParagraphIndex
        progress = chapter?.readingProgress
    }

    init(
        sourceURL: String,
        title: String,
        author: String,
        currentChapterURL: String? = nil,
        paragraphIndex: Int? = nil,
        progress: Double? = nil
    ) {
        self.sourceURL = sourceURL
        self.title = title
        self.author = author
        self.currentChapterURL = currentChapterURL
        self.paragraphIndex = paragraphIndex
        self.progress = progress
    }
}
