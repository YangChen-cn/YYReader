import Foundation

enum ReaderScrollTarget: Hashable {
    case chapterHeader(UUID)
    case paragraph(chapterID: UUID, index: Int)
    case chapterFooter(UUID)
}

struct ReaderParagraphFocus: Equatable {
    let chapterID: UUID
    let paragraphIndex: Int
}

enum ReaderParagraphFocusStyle {
    static func opacity(
        chapterID: UUID,
        paragraphIndex: Int,
        focus: ReaderParagraphFocus?
    ) -> Double {
        guard let focus else { return 1 }
        guard focus.chapterID == chapterID else { return 0.78 }

        switch abs(focus.paragraphIndex - paragraphIndex) {
        case 0: return 1
        case 1: return 0.90
        case 2: return 0.82
        default: return 0.78
        }
    }
}
