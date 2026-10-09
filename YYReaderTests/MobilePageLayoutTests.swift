#if os(iOS)
import SwiftUI
import Testing
@testable import YYReader

@MainActor
struct MobilePageLayoutTests {
    @Test
    func savedOffsetResolvesToThePageThatContainsIt() async throws {
        // One paragraph long enough to span several pages, so paragraph index
        // alone cannot identify the page the reader stopped on.
        let paragraph = String(repeating: "山间的风穿过木窗，桌上的书页轻轻翻动。", count: 60)
        let font = MobileReadingFont.resolve(.serif, size: 20)
        let layout = MobilePaginationLayout(width: 362, height: 640, fontName: font.fontName,
                                            fontSize: 20, lineHeight: font.lineHeight,
                                            lineSpacing: 9, paragraphSpacing: 12, usesFirstLineIndent: true)
        let pages = try await MobileTextPaginator().pages(paragraphs: [paragraph], layout: layout)
        try #require(pages.count >= 3)
        let first = try #require(pages.first?.id)
        let third = try #require(pages.dropFirst(2).first)
        let thirdOffset = try #require(third.fragments.first?.utf16Offset)

        #expect(MobileReadingPage.pageID(containingParagraph: 0, utf16Offset: 0, in: pages) == first)
        #expect(MobileReadingPage.pageID(containingParagraph: 0, utf16Offset: thirdOffset, in: pages) == third.id)
        // A stale offset from a longer layout must clamp to the last page.
        let last = try #require(pages.last?.id)
        #expect(MobileReadingPage.pageID(containingParagraph: 0, utf16Offset: Int.max, in: pages) == last)
    }

    @Test
    func pagesFillTheirActualSwiftUITextHeight() async throws {
        let paragraphs = (1...35).map { index in
            "段落\(index)：" + String(repeating: "山间的风穿过木窗，桌上的书页轻轻翻动。她记下沿途见到的花草，随后收起笔，走向溪边的石桥。", count: index % 3 + 1)
        }
        for family in ReaderFontFamily.allCases {
            for fontSize in [20.0, 30.0] {
                let font = MobileReadingFont.resolve(family, size: fontSize)
                let layout = MobilePaginationLayout(width: 362, height: 640, fontName: font.fontName,
                                                    fontSize: fontSize, lineHeight: font.lineHeight, lineSpacing: fontSize * 0.45,
                                                    paragraphSpacing: fontSize * 0.6, usesFirstLineIndent: true)
                let pages = try await MobileTextPaginator().pages(paragraphs: paragraphs, layout: layout)
                for page in pages.dropLast() {
                    // Measure the production SwiftUI content, rather than trusting
                    // Core Text's fallback-font metrics which caused the large blank area.
                    let renderer = ImageRenderer(content: MobileReaderPageContent(page: page, layout: layout))
                    renderer.proposedSize = ProposedViewSize(width: 402, height: nil)
                    var height: CGFloat = 0
                    renderer.render { size, _ in height = size.height }
                    #expect(height >= layout.height - 60, "\(family.rawValue) \(fontSize) page \(page.id): \(height)")
                    #expect(height <= layout.height + 24, "\(family.rawValue) \(fontSize) page \(page.id): \(height)")
                }
            }
        }
    }
}
#endif
