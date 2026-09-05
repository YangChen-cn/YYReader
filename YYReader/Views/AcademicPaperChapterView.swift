import SwiftUI

struct AcademicPaperChapterView: View {
    let plan: AcademicPaperPlan
    let chapterID: UUID
    let showsPaperFrontMatter: Bool
    let usesDoubleColumns: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Color.clear
                .frame(height: 1)
                .id(ReaderScrollTarget.chapterHeader(chapterID))

            if showsPaperFrontMatter {
                paperFrontMatter
            }

            Text(plan.sectionTitle)
                .font(.system(size: 20, weight: .semibold, design: .serif))
                .padding(.top, showsPaperFrontMatter ? 10 : 28)

            ForEach(segments) { segment in
                if usesDoubleColumns {
                    let columns = columnRanges(for: segment.range)
                    HStack(alignment: .top, spacing: 32) {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            ForEach(Array(plan.paragraphs[columns.left]), id: \.index) { paragraph in
                                paragraphView(paragraph)
                            }
                        }
                        .scrollTargetLayout()

                        LazyVStack(alignment: .leading, spacing: 14) {
                            ForEach(Array(plan.paragraphs[columns.right]), id: \.index) { paragraph in
                                paragraphView(paragraph)
                            }
                        }
                        .scrollTargetLayout()
                    }
                } else {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(plan.paragraphs[segment.range]), id: \.index) { paragraph in
                            paragraphView(paragraph)
                        }
                    }
                    .scrollTargetLayout()
                }

                if let supplement = segment.supplement {
                    AcademicPaperSupplementView(supplement: supplement)
                }
            }
        }
        .font(.system(size: 15.5, design: .serif))
        .foregroundStyle(Color(white: 0.12))
    }

    private func paragraphView(_ paragraph: AcademicPaperPlan.Paragraph) -> some View {
        Text(paragraph.text + citationText(paragraph.citations))
            .lineSpacing(5)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .id(ReaderScrollTarget.paragraph(chapterID: chapterID, index: paragraph.index))
    }

    private func columnRanges(for range: Range<Int>) -> (left: Range<Int>, right: Range<Int>) {
        let midpoint = range.lowerBound + (range.count + 1) / 2
        return (range.lowerBound..<midpoint, midpoint..<range.upperBound)
    }

    private var paperFrontMatter: some View {
        VStack(spacing: 16) {
            Text("JOURNAL OF APPLIED TEXTUAL STUDIES")
                .font(.system(size: 10, weight: .medium, design: .serif))
                .tracking(1.8)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)

            Text(plan.paperTitle)
                .font(.system(size: 29, weight: .bold, design: .serif))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            Text("Y. Y. Research Group")
                .font(.system(size: 13, design: .serif))
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 7) {
                Text("Abstract")
                    .font(.system(size: 15, weight: .bold, design: .serif))
                Text(plan.abstract)
                    .lineSpacing(4)
                Text("Keywords: \(plan.keywords)")
                    .font(.system(size: 12.5, design: .serif))
                    .italic()
            }
            .padding(.vertical, 14)
            .overlay(alignment: .top) { Divider() }
            .overlay(alignment: .bottom) { Divider() }
        }
    }

    private func citationText(_ citations: [Int]) -> String {
        guard !citations.isEmpty else { return "" }
        return " " + citations.map { "[\($0)]" }.joined(separator: " ")
    }

    private var segments: [Segment] {
        var result: [Segment] = []
        var start = 0
        for supplement in plan.supplements.sorted(by: { $0.beforeParagraphIndex < $1.beforeParagraphIndex }) {
            let end = min(max(supplement.beforeParagraphIndex, start), plan.paragraphs.count)
            if start < end {
                result.append(Segment(range: start..<end, supplement: supplement))
            } else if var last = result.popLast() {
                last = Segment(range: last.range, supplement: supplement)
                result.append(last)
            }
            start = end
        }
        if start < plan.paragraphs.count {
            result.append(Segment(range: start..<plan.paragraphs.count, supplement: nil))
        }
        return result
    }
}

private struct Segment: Identifiable {
    let range: Range<Int>
    let supplement: AcademicPaperPlan.Supplement?

    var id: String { "\(range.lowerBound)-\(range.upperBound)-\(supplement?.number ?? 0)" }
}
