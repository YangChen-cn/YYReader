import Foundation

struct BookshelfTransferDocument: Codable, Equatable, Sendable {
    var format: String
    var version: Int
    var exportedAt: Date
    var books: [BookshelfTransferBook]

    init(
        format: String = BookshelfTransferCodec.currentFormat,
        version: Int = BookshelfTransferCodec.currentVersion,
        exportedAt: Date = .now,
        books: [BookshelfTransferBook]
    ) {
        self.format = format
        self.version = version
        self.exportedAt = exportedAt
        self.books = books
    }
}
