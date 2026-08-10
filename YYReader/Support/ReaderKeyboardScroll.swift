import Foundation

enum ReaderKeyboardScroll {
    static func target(
        currentParagraphIndex: Int?,
        fallbackParagraphIndex: Int,
        paragraphCount: Int,
        offset: Int
    ) -> Int? {
        guard paragraphCount > 0 else { return nil }
        let current = currentParagraphIndex ?? fallbackParagraphIndex
        return min(max(current + offset, 0), paragraphCount - 1)
    }
}
