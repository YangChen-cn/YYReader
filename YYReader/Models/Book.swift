import Foundation
import SwiftData

@Model
final class Book {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var catalogURL: String
    var title: String
    var author: String
    var sourceHost: String
    var createdAt: Date
    var updatedAt: Date
    var hasCatalog: Bool = true
    var catalogFetchedAt: Date?
    var currentChapterID: UUID?

    @Relationship(deleteRule: .cascade, inverse: \Chapter.book)
    var chapters: [Chapter]

    /// `catalogURL` is also the persisted book identity for catalog-less sources.
    /// `hasCatalog` distinguishes an actual catalog URL from a derived source-book URL.
    var sourceBookURL: String { catalogURL }

    init(
        id: UUID = UUID(),
        title: String,
        author: String,
        sourceHost: String,
        catalogURL: String,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        hasCatalog: Bool = true,
        catalogFetchedAt: Date? = nil,
        currentChapterID: UUID? = nil,
        chapters: [Chapter] = []
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.sourceHost = sourceHost
        self.catalogURL = catalogURL
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.hasCatalog = hasCatalog
        self.catalogFetchedAt = catalogFetchedAt
        self.currentChapterID = currentChapterID
        self.chapters = chapters
    }
}
