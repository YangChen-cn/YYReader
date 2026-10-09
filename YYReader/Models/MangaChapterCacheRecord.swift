import Foundation

struct MangaChapterCacheRecord: Sendable {
    let id: UUID
    let imageURLs: [URL]
    let lastReadAt: Date?
}
