import Foundation
import SwiftData

@Model
final class Chapter {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var sourceURL: String
    var title: String
    var sortIndex: Int
    var bodyText: String?
    @Transient var contentRevision: Int = 0
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
        self.bodyText = bodyText.map(Self.normalizedBodyText)
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
            .map(String.init)
    }

    func replaceBodyText(_ bodyText: String?) {
        self.bodyText = bodyText.map(Self.normalizedBodyText)
        contentRevision &+= 1
    }

    var isCached: Bool {
        guard let bodyText else { return false }
        return !bodyText.isEmpty
    }

    var isAvailableOffline: Bool {
        cachedAt != nil
    }

    private static func normalizedBodyText(_ bodyText: String) -> String {
        bodyText
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }
}
