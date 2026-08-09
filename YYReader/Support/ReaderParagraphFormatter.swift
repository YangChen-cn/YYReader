import Foundation

enum ReaderParagraphFormatter {
    private static let twoIdeographicSpaces = "　　"

    static func format(_ paragraph: String, usesFirstLineIndent: Bool) -> String {
        guard usesFirstLineIndent, !paragraph.isEmpty else { return paragraph }
        guard paragraph.first?.isWhitespace != true else { return paragraph }
        return twoIdeographicSpaces + paragraph
    }
}
