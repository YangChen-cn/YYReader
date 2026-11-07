#if os(iOS)
import SwiftUI
import UIKit
import Testing
@testable import YYReader

@MainActor
struct MobilePageRenderingTests {
    @Test func fullPagesMatchRenderedChineseTextHeight() async throws {
        for family in ReaderFontFamily.allCases {
            let font = MobileReadingFont.resolve(family, size: 20)
            let height = MobileReadingFont.paginationLineHeight(font, displayScale: 3)
            let layout = MobilePaginationLayout(width: 350, height: 700, fontName: font.fontName,
                fontSize: 20, lineHeight: height, lineSpacing: 8, paragraphSpacing: 12, usesFirstLineIndent: true)
            let paragraphs = (0..<30).map { _ in String(repeating: "这是一段自造正文，用于测量实际排版高度。", count: 3) }
            let pages = try await MobileTextPaginator().pages(paragraphs: paragraphs, layout: layout)
            // Exclude the chapter's final page, which can naturally be short.
            for page in pages.dropLast() {
                let host = UIHostingController(rootView: MobileReaderPageContent(page: page, layout: layout))
                let actual = host.sizeThatFits(in: CGSize(width: 393, height: 10000)).height
                #expect(actual <= layout.height + 16 + 1)
                #expect(actual >= layout.height - height - layout.lineSpacing - layout.paragraphSpacing)
            }
        }
    }
}
#endif
