import Foundation

struct OfflineDownloadItem: Sendable {
    let chapterID: UUID
    let sourceURL: URL?
    let isCached: Bool
    let isCurrentChapter: Bool
}
