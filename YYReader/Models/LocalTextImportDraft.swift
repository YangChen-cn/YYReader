import Foundation

struct LocalTextImportDraft: Codable, Equatable, Identifiable, Sendable {
    let sourceBookURL: String
    let suggestedTitle: String
    let detectedEncoding: String
    let byteCount: Int
    let chapters: [LocalTextChapterDraft]

    var id: String { sourceBookURL }
    var isTavernExport: Bool {
        chapters.filter { $0.title.range(of: #"^第[0-9]+楼$"#, options: .regularExpression) != nil }.count >= 2
    }
}
