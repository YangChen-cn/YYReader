import SwiftUI

struct ReaderParagraphView: View {
    let paragraph: String
    let fontFamily: ReaderFontFamily
    let fontSize: Double
    let lineSpacing: Double
    let usesFirstLineIndent: Bool
    var focusOpacity = 1.0

    var body: some View {
        Text(ReaderParagraphFormatter.format(paragraph, usesFirstLineIndent: usesFirstLineIndent))
            .font(fontFamily.font(size: fontSize))
            .lineSpacing(lineSpacing)
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(focusOpacity)
    }
}
