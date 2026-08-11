import Foundation

struct SyncBookRecord: Codable, Equatable, Sendable {
    var sourceURL: String
    var title: String
    var author: String
    var currentChapterURL: String?
    var paragraphIndex: Int?
    var progress: Double?
    var lastReadAt: Date?
    var updatedAt: Date
    var deletedAt: Date?

    init(
        transfer: BookshelfTransferBook,
        lastReadAt: Date?,
        updatedAt: Date,
        deletedAt: Date? = nil
    ) {
        sourceURL = transfer.sourceURL
        title = transfer.title
        author = transfer.author
        currentChapterURL = transfer.currentChapterURL
        paragraphIndex = transfer.paragraphIndex
        progress = transfer.progress
        self.lastReadAt = lastReadAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    init(
        sourceURL: String,
        title: String,
        author: String,
        currentChapterURL: String? = nil,
        paragraphIndex: Int? = nil,
        progress: Double? = nil,
        lastReadAt: Date? = nil,
        updatedAt: Date,
        deletedAt: Date? = nil
    ) {
        self.sourceURL = sourceURL
        self.title = title
        self.author = author
        self.currentChapterURL = currentChapterURL
        self.paragraphIndex = paragraphIndex
        self.progress = progress
        self.lastReadAt = lastReadAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    var canonicalSourceURL: String {
        URLCanonicalizer.canonicalString(sourceURL)
    }

    var isDeleted: Bool {
        guard let deletedAt else { return false }
        return deletedAt >= updatedAt
    }
}
