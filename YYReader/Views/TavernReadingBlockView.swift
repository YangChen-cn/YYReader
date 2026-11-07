import SwiftUI

struct TavernReadingBlockView: View {
    let block: TavernReadingPlan.Block
    let inferredPlayer: String
    let fontFamily: ReaderFontFamily
    let fontSize: Double
    let lineSpacing: Double
    let usesFirstLineIndent: Bool
    let compact: Bool
    @ScaledMetric(relativeTo: .body) private var textScale = 1.0

    var body: some View {
        VStack(alignment: .leading, spacing: fontSize * 0.6) {
            ForEach(block.segments.indices, id: \.self) { index in
                let segment = block.segments[index]
                switch segment.kind {
                case .narration:
                    let content = ReaderParagraphFormatter.format(segment.text, usesFirstLineIndent: usesFirstLineIndent)
                    Text((try? AttributedString(markdown: content, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(content))
                        .font(fontFamily.font(size: fontSize * textScale))
                        .lineSpacing(lineSpacing * textScale)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case let .dialogue(speaker):
                    TavernDialogueView(speaker: speaker, text: segment.text, inferredPlayer: inferredPlayer,
                                       fontFamily: fontFamily, fontSize: fontSize, lineSpacing: lineSpacing, compact: compact)
                case let .auxiliary(title):
                    DisclosureGroup {
                        Text(segment.text).font(fontFamily.font(size: fontSize * 0.9 * textScale))
                            .lineSpacing(lineSpacing * textScale).padding(.top, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } label: { Text(title).font(.callout.weight(.medium)) }
                    .padding(14)
                    .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
                }
            }
        }
    }
}
