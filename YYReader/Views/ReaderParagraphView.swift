import SwiftUI

struct ReaderParagraphView: View {
    let paragraph: String
    let fontFamily: ReaderFontFamily
    let fontSize: Double
    let lineSpacing: Double
    let usesFirstLineIndent: Bool
    @ScaledMetric(relativeTo: .body) private var textScale = 1.0

    var body: some View {
        Text(ReaderParagraphFormatter.format(paragraph, usesFirstLineIndent: usesFirstLineIndent))
            .font(fontFamily.font(size: fontSize * textScale))
            .lineSpacing(lineSpacing * textScale)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
