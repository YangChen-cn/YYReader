import CoreText
import Foundation

actor MobileTextPaginator {
    func pages(paragraphs: [String], layout: MobilePaginationLayout) throws -> [MobileReadingPage] {
        try Task.checkCancellation()
        guard layout.width.isFinite, layout.height.isFinite,
              layout.width > 0, layout.height > 0, layout.fontSize > 0 else { return [] }
        let font = CTFontCreateWithName(layout.fontName as CFString, layout.fontSize, nil)
        var spacing = CGFloat(layout.lineSpacing)
        var lineHeight = CGFloat(layout.lineHeight)
        let style = withUnsafePointer(to: &spacing) { value in
            withUnsafePointer(to: &lineHeight) { height in
                let settings = [
                    CTParagraphStyleSetting(spec: .lineSpacingAdjustment, valueSize: MemoryLayout<CGFloat>.size, value: value),
                    CTParagraphStyleSetting(spec: .minimumLineHeight, valueSize: MemoryLayout<CGFloat>.size, value: height),
                    CTParagraphStyleSetting(spec: .maximumLineHeight, valueSize: MemoryLayout<CGFloat>.size, value: height)
                ]
                return settings.withUnsafeBufferPointer { CTParagraphStyleCreate($0.baseAddress, $0.count) }
            }
        }
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String): style
        ]
        // Core Text's CJK fallback metrics are taller than SwiftUI's fixed font
        // lines. Match the resolved line height instead of reserving a whole extra line.
        // Pages also allow vertical overflow at extreme accessibility sizes, so text is never clipped.
        let pageHeight = max(layout.height - 2, layout.lineHeight)
        let width = max(layout.width - 2, 1)
        var remainingHeight = pageHeight
        var fragments: [MobileReadingPage.Fragment] = []
        var pages: [MobileReadingPage] = []

        func finishPage() {
            guard !fragments.isEmpty else { return }
            pages.append(MobileReadingPage(id: pages.count, fragments: fragments))
            fragments = []
            remainingHeight = pageHeight
        }

        for (index, paragraph) in paragraphs.enumerated() {
            try Task.checkCancellation()
            let text = ReaderParagraphFormatter.format(paragraph, usesFirstLineIndent: layout.usesFirstLineIndent)
            let source = text as NSString
            guard source.length > 0 else { continue }
            let setter = CTFramesetterCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
            var offset = 0
            while offset < source.length {
                try Task.checkCancellation()
                let gap = fragments.isEmpty ? 0 : layout.paragraphSpacing
                let available = max(remainingHeight - gap, 0)
                // SwiftUI adds lineSpacing between lines, never after the final
                // line of a Text. Framesetter heights include trailing leading,
                // which accumulated across paragraphs and left a large blank.
                if available < layout.lineHeight, !fragments.isEmpty {
                    finishPage()
                    continue
                }
                let lineAdvance = max(layout.lineHeight + layout.lineSpacing, 1)
                let capacity = max(1, Int(floor((available + layout.lineSpacing + 0.001) / lineAdvance)))
                let typesetter = CTFramesetterGetTypesetter(setter)
                var end = offset
                var lines = 0
                while end < source.length, lines < capacity {
                    try Task.checkCancellation()
                    var count = CTTypesetterSuggestLineBreak(typesetter, end, width)
                    if count > 0, end + count < source.length {
                        let character = source.rangeOfComposedCharacterSequence(at: end + count)
                        if character.location < end + count { count = character.location - end }
                    }
                    if count == 0 { count = source.rangeOfComposedCharacterSequence(at: end).length }
                    end += count
                    lines += 1
                }
                let length = end - offset
                let usedHeight = Double(lines) * layout.lineHeight + Double(max(lines - 1, 0)) * layout.lineSpacing
                fragments.append(.init(paragraphIndex: index, utf16Offset: offset,
                                       text: source.substring(with: NSRange(location: offset, length: length))))
                remainingHeight -= usedHeight + gap
                offset += length
                if offset < source.length { finishPage() }
            }
        }
        finishPage()
        return pages
    }
}
