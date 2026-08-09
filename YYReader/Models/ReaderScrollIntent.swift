import Foundation

enum ReaderScrollIntent: Equatable, Sendable {
    case restore
    case chapterTop
}

struct ReaderScrollRequest: Equatable, Identifiable, Sendable {
    let id = UUID()
    let chapterID: UUID
    let intent: ReaderScrollIntent
}
