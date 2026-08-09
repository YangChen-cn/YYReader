import SwiftUI

struct ReaderParagraphView: View {
    let paragraph: String
    let fontFamily: ReaderFontFamily
    let fontSize: Double
    let lineSpacing: Double
    let usesFirstLineIndent: Bool

    var body: some View {
        Text(ReaderParagraphFormatter.format(paragraph, usesFirstLineIndent: usesFirstLineIndent))
            .font(fontFamily.font(size: fontSize))
            .lineSpacing(lineSpacing)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
