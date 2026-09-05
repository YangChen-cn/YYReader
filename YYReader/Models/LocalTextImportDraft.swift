import Foundation

struct LocalTextImportDraft: Equatable, Identifiable, Sendable {
    let sourceBookURL: String
    let suggestedTitle: String
    let detectedEncoding: String
    let byteCount: Int
    let chapters: [LocalTextChapterDraft]

    var id: String { sourceBookURL }
}
