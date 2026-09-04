import Foundation

struct AcademicPaperPlan: Equatable, Sendable {
    struct Paragraph: Equatable, Sendable {
        let index: Int
        let text: String
        let citations: [Int]
    }

    enum SupplementKind: String, Equatable, Sendable {
        case equation
        case table
        case figure
    }

    struct Supplement: Equatable, Sendable {
        let beforeParagraphIndex: Int
        let kind: SupplementKind
        let number: Int
    }

    let paperTitle: String
    let abstract: String
    let keywords: String
    let sectionTitle: String
    let paragraphs: [Paragraph]
    let supplements: [Supplement]
}
