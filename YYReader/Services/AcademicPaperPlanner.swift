import CryptoKit
import Foundation

enum AcademicPaperPlanner {
    static func makePlan(
        bookIdentity: String,
        chapterIdentity: String,
        chapterPosition: Int,
        paragraphs: [String]
    ) -> AcademicPaperPlan {
        let seed = URLCanonicalizer.canonicalString(bookIdentity) + "|" + chapterIdentity
        let titles = [
            "A Structured Analysis of Sequential Narrative Systems",
            "Contextual Dynamics in Long-Form Textual Corpora",
            "An Empirical Study of Narrative State Transitions",
            "Representation and Continuity in Textual Systems"
        ]
        let abstracts = [
            "This paper examines a sequential textual corpus through a reproducible structural framework. The analysis emphasizes continuity, contextual transition, and locally observable evidence.",
            "We present a deterministic reading of a long-form corpus. The method preserves source material while organizing observations into a conventional academic structure.",
            "This study investigates narrative progression using stable textual units. Results indicate that local context and ordered evidence remain central to interpretation."
        ]
        let keywordSets = [
            "textual analysis; sequential systems; contextual evidence",
            "narrative structure; corpus reading; deterministic layout",
            "long-form text; continuity; representation"
        ]
        let title = titles[stableNumber(seed + "|title", upperBound: titles.count)]
        let abstract = abstracts[stableNumber(seed + "|abstract", upperBound: abstracts.count)]
        let keywords = keywordSets[stableNumber(seed + "|keywords", upperBound: keywordSets.count)]

        var plannedParagraphs: [AcademicPaperPlan.Paragraph] = []
        var nextCitation = 3 + stableNumber(seed + "|citation-start", upperBound: 3)
        for (index, text) in paragraphs.enumerated() {
            var citations: [Int] = []
            if index == nextCitation {
                let count = 1 + stableNumber(seed + "|citation-count|\(index)", upperBound: 3)
                citations = (0..<count).map {
                    1 + stableNumber(seed + "|citation|\(index)|\($0)", upperBound: 18)
                }.sorted()
                nextCitation += 3 + stableNumber(seed + "|citation-gap|\(index)", upperBound: 3)
            }
            plannedParagraphs.append(.init(index: index, text: text, citations: citations))
        }

        var supplements: [AcademicPaperPlan.Supplement] = []
        var nextSupplement = 10 + stableNumber(seed + "|supplement-start", upperBound: 9)
        var supplementNumber = 1
        while nextSupplement < paragraphs.count {
            let kinds: [AcademicPaperPlan.SupplementKind] = [.equation, .table, .figure]
            let kind = kinds[stableNumber(seed + "|supplement-kind|\(nextSupplement)", upperBound: kinds.count)]
            supplements.append(.init(
                beforeParagraphIndex: nextSupplement,
                kind: kind,
                number: supplementNumber
            ))
            supplementNumber += 1
            nextSupplement += 10 + stableNumber(seed + "|supplement-gap|\(nextSupplement)", upperBound: 9)
        }

        return AcademicPaperPlan(
            paperTitle: title,
            abstract: abstract,
            keywords: keywords,
            sectionTitle: sectionTitle(for: chapterPosition),
            paragraphs: plannedParagraphs,
            supplements: supplements
        )
    }

    private static func sectionTitle(for position: Int) -> String {
        switch position {
        case 0: return "1. Introduction"
        case 1: return "2. Methodology"
        case 2: return "3. Results and Discussion"
        default: return "3.\(position - 2) Extended Analysis"
        }
    }

    private static func stableNumber(_ value: String, upperBound: Int) -> Int {
        guard upperBound > 0 else { return 0 }
        let digest = SHA256.hash(data: Data(value.utf8))
        let number = digest.prefix(8).reduce(UInt64.zero) { ($0 << 8) | UInt64($1) }
        return Int(number % UInt64(upperBound))
    }
}
