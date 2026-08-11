import Foundation

struct SyncSnapshot: Codable, Equatable, Sendable {
    static let currentFormat = "yyreader-sync"
    static let currentVersion = 2

    var format: String
    var version: Int
    var device: SyncDevice
    var updatedAt: Date
    var books: [SyncBookRecord]

    init(device: SyncDevice, updatedAt: Date = .now, books: [SyncBookRecord]) {
        format = Self.currentFormat
        version = Self.currentVersion
        self.device = device
        self.updatedAt = updatedAt
        self.books = books
    }
}
