import Testing
@testable import YYReader

struct ReaderPresentationTests {
    @Test
    func paragraphFormatterAddsTwoCharacterIndentOnlyWhenNeeded() {
        #expect(
            ReaderParagraphFormatter.format("第一段正文。", usesFirstLineIndent: true)
                == "　　第一段正文。"
        )
        #expect(
            ReaderParagraphFormatter.format("　　已经缩进。", usesFirstLineIndent: true)
                == "　　已经缩进。"
        )
        #expect(
            ReaderParagraphFormatter.format("  已经留白。", usesFirstLineIndent: true)
                == "  已经留白。"
        )
        #expect(ReaderParagraphFormatter.format("", usesFirstLineIndent: true).isEmpty)
        #expect(
            ReaderParagraphFormatter.format("关闭缩进。", usesFirstLineIndent: false)
                == "关闭缩进。"
        )
    }

    @Test
    func readerPresetsUseBoundedNovelReadingValues() {
        #expect(ReaderLineSpacingPreset.compact.value == 5)
        #expect(ReaderLineSpacingPreset.comfortable.value == 8)
        #expect(ReaderLineSpacingPreset.spacious.value == 12)
        #expect(ReaderLineSpacingPreset.closest(to: 9) == .comfortable)

        #expect(ReaderContentWidthPreset.narrow.value == 620)
        #expect(ReaderContentWidthPreset.medium.value == 680)
        #expect(ReaderContentWidthPreset.wide.value == 760)
        #expect(ReaderContentWidthPreset.closest(to: 700) == .medium)
    }
}
