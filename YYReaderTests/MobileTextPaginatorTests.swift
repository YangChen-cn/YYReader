#if os(iOS)
import Foundation
import Testing
@testable import YYReader

@MainActor
struct MobileTextPaginatorTests {
    @Test
    func longParagraphsAndUnicodeArePreservedAcrossPages() async throws {
        let paragraphs = [String(repeating: "山间的风拂过窗沿，👨‍👩‍👧‍👦一家人沿着石桥走来。e\u{301}，树影落在纸上。", count: 35),
                          "第二段正文，必须恰好出现一次。", "第三段正文，不能在分页边界丢失。"]
        let pages = try await MobileTextPaginator().pages(paragraphs: paragraphs, layout: layout(width: 220, height: 180))
        #expect(pages.count > 2)
        #expect(pages.map(\.id) == Array(pages.indices))
        for (index, paragraph) in paragraphs.enumerated() {
            let fragments = pages.flatMap(\.fragments).filter { $0.paragraphIndex == index }
            let expected = ReaderParagraphFormatter.format(paragraph, usesFirstLineIndent: true)
            #expect(fragments.map(\.text).joined() == expected)
            var offset = 0
            for fragment in fragments {
                #expect(fragment.utf16Offset == offset)
                #expect(!fragment.text.contains("�"))
                let range = Range(NSRange(location: fragment.utf16Offset, length: fragment.text.utf16.count), in: expected)
                #expect(range != nil)
                offset += fragment.text.utf16.count
            }
        }
    }

    @Test
    func resizingAndLargerFontsReflowAroundTheSameTextAnchor() async throws {
        let paragraphs = [String(repeating: "这是一段用于验证重新排版的自造正文，阅读位置应当保持在同一段文字附近。", count: 80)]
        let paginator = MobileTextPaginator()
        let initial = try await paginator.pages(paragraphs: paragraphs, layout: layout(width: 300, height: 500))
        let anchor = try #require(initial[initial.count / 2].fragments.first)
        let resized = try await paginator.pages(paragraphs: paragraphs, layout: layout(width: 220, height: 300, size: 30))
        #expect(resized.count > initial.count)
        let id = try #require(MobileReadingPage.pageID(containingParagraph: anchor.paragraphIndex,
                                                      utf16Offset: anchor.utf16Offset, in: resized))
        let page = try #require(resized.first { $0.id == id })
        let first = try #require(page.fragments.first)
        let last = try #require(page.fragments.last)
        #expect(first.utf16Offset <= anchor.utf16Offset)
        #expect(last.utf16Offset + last.text.utf16.count > anchor.utf16Offset)
    }

    @Test
    func paragraphRestorationFindsTheContainingPageAndClampsStalePositions() async throws {
        let paragraphs = (0..<30).map { "段落\($0)：" + String(repeating: "窗外的风很轻，石桥边的花开了。", count: 3) }
        let pages = try await MobileTextPaginator().pages(paragraphs: paragraphs, layout: layout(width: 240, height: 300))
        let id = try #require(MobileReadingPage.pageID(containingParagraph: 18, in: pages))
        let page = try #require(pages.first { $0.id == id })
        #expect(page.fragments.contains { $0.paragraphIndex == 18 })
        #expect(MobileReadingPage.pageID(containingParagraph: -1, in: pages) == pages.first?.id)
        #expect(MobileReadingPage.pageID(containingParagraph: 300, in: pages) == pages.last?.id)
        #expect(MobileReadingPage.pageID(containingParagraph: 0, in: []) == nil)
    }

    @Test
    func narrowViewportStillAdvancesByWholeCharacters() async throws {
        let paragraphs = ["👨‍👩‍👧‍👦你好e\u{301}，这是很窄的窗口。"]
        let pages = try await MobileTextPaginator().pages(paragraphs: paragraphs, layout: layout(width: 1, height: 1))
        #expect(!pages.isEmpty)
        #expect(pages.flatMap(\.fragments).map(\.text).joined()
                == ReaderParagraphFormatter.format(paragraphs[0], usesFirstLineIndent: true))
    }

    @Test
    func cancelledPaginationDoesNotReturnAnObsoleteLayout() async throws {
        let paginator = MobileTextPaginator()
        let config = layout(width: 240, height: 300)
        let task = Task { try await paginator.pages(paragraphs: [String(repeating: "取消测试。", count: 20_000)], layout: config) }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    private func layout(width: Double, height: Double, size: Double = 20) -> MobilePaginationLayout {
        let font = MobileReadingFont.resolve(.system, size: size)
        return MobilePaginationLayout(width: width, height: height, fontName: font.fontName,
                                      fontSize: size, lineHeight: font.lineHeight, lineSpacing: size * 0.4,
                                      paragraphSpacing: size * 0.6, usesFirstLineIndent: true)
    }
}
#endif
