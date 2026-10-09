import Foundation

struct MobileReadingPage: Identifiable, Sendable {
    struct Fragment: Identifiable, Sendable {
        let paragraphIndex: Int
        let utf16Offset: Int
        let text: String

        var id: String { "\(paragraphIndex):\(utf16Offset)" }
    }

    let id: Int
    let fragments: [Fragment]

    static func pageID(containingParagraph index: Int, utf16Offset: Int = 0, in pages: [Self]) -> Int? {
        // Pick the last page starting at/before the anchor, including continuations
        // of a long paragraph. Font/viewport changes can move the same text to another page.
        pages.last { page in
            guard let first = page.fragments.first else { return false }
            return first.paragraphIndex < index
                || (first.paragraphIndex == index && first.utf16Offset <= utf16Offset)
        }?.id ?? pages.first?.id
    }
}
