import Foundation

struct LocalBookCacheEntry: Identifiable, Sendable {
    let id: UUID
    let title: String
    let isManga: Bool
    let textBytes: Int
    let imageURLs: [URL]
    var imageBytes = 0
    var totalBytes: Int { textBytes + imageBytes }
}

struct LocalCacheSummary: Sendable {
    var books: [LocalBookCacheEntry] = []
    var imageBytes = 0
    var totalBytes: Int { books.reduce(imageBytes) { $0 + $1.textBytes } }
}
