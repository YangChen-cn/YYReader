import Foundation
import SwiftData

@Model
final class Chapter {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var sourceURL: String
    var title: String
    var sortIndex: Int
    var bodyText: String?
    var previousURL: String?
    var nextURL: String?
    var cachedAt: Date?
    var lastReadAt: Date?
    var topParagraphIndex: Int
    var readingProgress: Double
    var book: Book?

    init(
        id: UUID = UUID(),
        sourceURL: String,
        title: String,
        sortIndex: Int,
        bodyText: String? = nil,
        previousURL: String? = nil,
        nextURL: String? = nil,
        cachedAt: Date? = nil,
        lastReadAt: Date? = nil,
        topParagraphIndex: Int = 0,
        readingProgress: Double = 0,
        book: Book? = nil
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.title = title
        self.sortIndex = sortIndex
        self.bodyText = bodyText
        self.previousURL = previousURL
        self.nextURL = nextURL
        self.cachedAt = cachedAt
        self.lastReadAt = lastReadAt
        self.topParagraphIndex = topParagraphIndex
        self.readingProgress = readingProgress
        self.book = book
    }

    var paragraphs: [String] {
        guard let bodyText else { return [] }
        return bodyText
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var isCached: Bool {
        guard let bodyText else { return false }
        return !bodyText.isEmpty
    }
}
