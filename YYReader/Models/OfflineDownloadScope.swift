import Foundation

enum OfflineDownloadScope: Sendable {
    case currentChapter
    case followingChapters(Int)
    case entireBook
}
