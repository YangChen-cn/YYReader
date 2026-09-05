import Testing
@testable import YYReader

struct AcademicPaperPlannerTests {
    @Test
    func planIsDeterministicAndPreservesEveryParagraph() {
        let paragraphs = (0..<60).map { "原文段落 \($0)" }
        let first = AcademicPaperPlanner.makePlan(
            bookIdentity: "https://example.com/book/",
            chapterIdentity: "https://example.com/book/3.html",
            chapterPosition: 2,
            paragraphs: paragraphs
        )
        let second = AcademicPaperPlanner.makePlan(
            bookIdentity: "https://example.com/book/",
            chapterIdentity: "https://example.com/book/3.html",
            chapterPosition: 2,
            paragraphs: paragraphs
        )

        #expect(first == second)
        #expect(first.paragraphs.map(\.text) == paragraphs)
        #expect(first.paragraphs.map(\.index) == Array(paragraphs.indices))
        #expect(first.sectionTitle == "3. Results and Discussion")
        #expect(first.paperTitle == "Contextual Dynamics in Long-Form Textual Corpora")
        #expect(first.paragraphs.filter { !$0.citations.isEmpty }.map(\.index) == [5, 10, 15, 20, 23, 28, 31, 36, 39, 44, 47, 50, 55, 59])
        #expect(first.supplements.map(\.beforeParagraphIndex) == [10, 21, 38, 55])
        #expect(first.supplements.map(\.kind) == [.figure, .equation, .figure, .table])

        let citationIndices = first.paragraphs.filter { !$0.citations.isEmpty }.map(\.index)
        for pair in zip(citationIndices, citationIndices.dropFirst()) {
            #expect((3...5).contains(pair.1 - pair.0))
        }
        let supplementIndices = first.supplements.map(\.beforeParagraphIndex)
        for pair in zip(supplementIndices, supplementIndices.dropFirst()) {
            #expect((10...18).contains(pair.1 - pair.0))
        }
    }

    @Test
    func chapterSectionMappingIsStable() {
        let expected = [
            "1. Introduction",
            "2. Methodology",
            "3. Results and Discussion",
            "3.1 Extended Analysis",
            "3.2 Extended Analysis"
        ]
        let actual = (0..<5).map {
            AcademicPaperPlanner.makePlan(
                bookIdentity: "yyreader-local://txt/" + String(repeating: "a", count: 64),
                chapterIdentity: "chapter-\($0)",
                chapterPosition: $0,
                paragraphs: ["正文"]
            ).sectionTitle
        }
        #expect(actual == expected)
    }
}
