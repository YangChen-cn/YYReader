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
                let path = CGPath(rect: CGRect(x: 0, y: 0, width: width, height: available), transform: nil)
                let frame = CTFramesetterCreateFrame(setter, CFRange(location: offset, length: 0), path, nil)
                var length = CTFrameGetVisibleStringRange(frame).length
                if length == 0, !fragments.isEmpty {
                    finishPage()
                    continue
                }
                // Do not split emoji, combining marks or a surrogate pair. Even
                // very narrow viewports must advance by at least one whole character.
                if length > 0 {
                    let end = offset + length
                    if end < source.length {
                        let character = source.rangeOfComposedCharacterSequence(at: end)
                        if character.location < end { length = character.location - offset }
                    }
                }
                if length == 0 { length = source.rangeOfComposedCharacterSequence(at: offset).length }
                let range = CFRange(location: offset, length: length)
                let size = CTFramesetterSuggestFrameSizeWithConstraints(setter, range, nil,
                                                                       CGSize(width: width, height: .greatestFiniteMagnitude), nil)
                fragments.append(.init(paragraphIndex: index, utf16Offset: offset,
                                       text: source.substring(with: NSRange(location: offset, length: length))))
                remainingHeight -= ceil(size.height) + gap
                offset += length
                if offset < source.length { finishPage() }
            }
        }
        finishPage()
        return pages
    }
}
