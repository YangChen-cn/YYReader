import SwiftUI

struct AcademicPaperChapterView: View {
    let plan: AcademicPaperPlan
    let chapterID: UUID
    let showsPaperFrontMatter: Bool
    let usesDoubleColumns: Bool
    let fontSize: Double
    let lineSpacing: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if showsPaperFrontMatter {
                paperFrontMatter
            } else {
                runningHeader
            }

            Text(plan.sectionTitle)
                .font(.system(size: max(18, fontSize * 1.15), weight: .bold, design: .serif))
                .padding(.top, showsPaperFrontMatter ? 12 : 18)
                .padding(.bottom, 4)

            ForEach(segments) { segment in
                if usesDoubleColumns {
                    let columns = columnRanges(for: segment.range)
                    HStack(alignment: .top, spacing: 22) {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(plan.paragraphs[columns.left]), id: \.index) { paragraph in
                                paragraphView(paragraph)
                            }
                        }

                        Rectangle()
                            .fill(Color(white: 0.84))
                            .frame(width: 0.6)
                            .padding(.vertical, 2)

                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(plan.paragraphs[columns.right]), id: \.index) { paragraph in
                                paragraphView(paragraph)
                            }
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(plan.paragraphs[segment.range]), id: \.index) { paragraph in
                            paragraphView(paragraph)
                        }
                    }
                }

                if let supplement = segment.supplement {
                    AcademicPaperSupplementView(supplement: supplement)
                }
            }

            paperFooter
        }
        .foregroundStyle(Color(white: 0.12))
    }

    private func paragraphView(_ paragraph: AcademicPaperPlan.Paragraph) -> some View {
        let formattedText = ReaderParagraphFormatter.format(paragraph.text, usesFirstLineIndent: true)
        let citations = formattedCitations(paragraph.citations)

        return (Text(formattedText) + citations)
            .font(.system(size: fontSize, design: .serif))
            .lineSpacing(lineSpacing * fontSize)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .id(ReaderScrollTarget.paragraph(chapterID: chapterID, index: paragraph.index))
    }

    private func columnRanges(for range: Range<Int>) -> (left: Range<Int>, right: Range<Int>) {
        let midpoint = range.lowerBound + (range.count + 1) / 2
        return (range.lowerBound..<midpoint, midpoint..<range.upperBound)
    }

    private var runningHeader: some View {
        HStack(alignment: .bottom) {
            Text("IEEE TRANSACTIONS ON APPLIED TEXTUAL SYSTEMS, VOL. 32, NO. 4")
                .font(.system(size: 8.5, weight: .semibold, design: .serif))
                .tracking(0.6)
                .foregroundStyle(Color(white: 0.45))
            Spacer()
            Text("Y. Y. RESEARCH: \(plan.sectionTitle.uppercased())")
                .font(.system(size: 8.5, weight: .medium, design: .serif))
                .tracking(0.5)
                .foregroundStyle(Color(white: 0.50))
        }
        .padding(.bottom, 6)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(white: 0.78))
                .frame(height: 0.5)
        }
    }

    private var paperFrontMatter: some View {
        VStack(spacing: 14) {
            HStack {
                Text("IEEE TRANSACTIONS ON APPLIED TEXTUAL SYSTEMS, VOL. 32, NO. 4, AUGUST 2026")
                    .font(.system(size: 8.5, weight: .bold, design: .serif))
                    .tracking(0.8)
                    .foregroundStyle(Color(white: 0.38))
                Spacer()
                Text("PREPRINT")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.red.opacity(0.85))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(Color.red.opacity(0.85), lineWidth: 0.8)
                    )
            }
            .frame(maxWidth: .infinity)

            Text(plan.paperTitle)
                .font(.system(size: 24, weight: .bold, design: .serif))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)

            Text("Y. Y. Research Group*, Senior Member, IEEE, and Project Collaborators")
                .font(.system(size: 12, design: .serif))
                .foregroundStyle(Color(white: 0.32))
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 8) {
                (Text("Abstract—")
                    .font(.system(size: 12.5, weight: .bold, design: .serif))
                +
                Text(plan.abstract)
                    .font(.system(size: 12.5, design: .serif)))
                    .lineSpacing(4)

                HStack(alignment: .top, spacing: 4) {
                    Text("Index Terms—")
                        .font(.system(size: 11.5, weight: .bold, design: .serif))
                        .italic()
                    Text(plan.keywords)
                        .font(.system(size: 11.5, design: .serif))
                        .italic()
                }
                .foregroundStyle(Color(white: 0.35))
                .padding(.top, 2)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(Color(white: 0.98))
            .overlay(alignment: .top) { Rectangle().fill(Color(white: 0.76)).frame(height: 0.75) }
            .overlay(alignment: .bottom) { Rectangle().fill(Color(white: 0.76)).frame(height: 0.75) }

            firstPageFootnote
        }
    }

    private var firstPageFootnote: some View {
        VStack(alignment: .leading, spacing: 3) {
            Rectangle()
                .fill(Color(white: 0.75))
                .frame(width: 140, height: 0.5)
                .padding(.bottom, 2)
            Text("* Manuscript received April 12, 2026; revised July 19, 2026. This work was supported in part by the National Textual Analytics Initiative under Grant #2024-TA-092.")
                .font(.system(size: 8, design: .serif))
                .foregroundStyle(Color(white: 0.45))
            Text("The authors are with the Department of Computational Textual Studies, Institute of Fiction Systems (e-mail: yy.reader@research.org).")
                .font(.system(size: 8, design: .serif))
                .foregroundStyle(Color(white: 0.45))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    private var paperFooter: some View {
        VStack(spacing: 5) {
            Rectangle()
                .fill(Color(white: 0.80))
                .frame(height: 0.5)

            HStack {
                Text("DOI: 10.1109/TATS.2026.3141592")
                    .font(.system(size: 8, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color(white: 0.50))
                Spacer()
                Text("© 2026 IEEE. Personal use permitted.")
                    .font(.system(size: 8, design: .serif))
                    .foregroundStyle(Color(white: 0.50))
            }
        }
        .padding(.top, 16)
    }

    private func formattedCitations(_ citations: [Int]) -> Text {
        guard let label = AcademicPaperPlan.Formatting.citationLabel(for: citations) else { return Text("") }
        let superscriptSize = max(9.0, fontSize * 0.55)
        let baselineOffset = fontSize * 0.28
        return Text("[\(label)]")
            .font(.system(size: superscriptSize, weight: .semibold, design: .serif))
            .baselineOffset(baselineOffset)
            .foregroundStyle(Color(red: 0.08, green: 0.36, blue: 0.72))
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
