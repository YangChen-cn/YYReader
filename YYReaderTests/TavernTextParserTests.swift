import Foundation
import Testing
import SwiftData
@testable import YYReader

struct TavernTextParserTests {
    @Test @MainActor func readableProgressKeepsOriginalParagraphAnchor() throws {
        let container = try ModelContainer(for: Book.self, Chapter.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let book = Book(title: "测试", author: "作者", sourceHost: "example.com", catalogURL: "https://example.com/tavern/")
        let chapter = Chapter(sourceURL: "https://example.com/tavern/1", title: "正文", sortIndex: 1,
                              bodyText: (0..<20).map { "段落\($0)" }.joined(separator: "\n"), book: book)
        book.chapters = [chapter]
        context.insert(book)
        context.insert(chapter)
        try context.save()
        let store = LibraryStore(modelContext: context, coordinator: NovelImportCoordinator(loader: MockHTMLLoader(documents: [:])))
        store.selectBook(book.id)
        store.updateVisibleReaderPosition(chapterID: chapter.id, paragraphIndex: 17, total: 5, progressIndex: 2)
        #expect(chapter.topParagraphIndex == 17)
        #expect(chapter.readingProgress == 0.5)
        store.updateVisibleReaderPosition(chapterID: chapter.id, paragraphIndex: 17, total: 20)
        #expect(chapter.readingProgress == 17.0 / 19.0)
    }

    @Test func separatesNarrationAndDialogueWithoutDiscardingOtherText() {
        let plan = TavernTextParser.parse(["风吹过窗边。", "{旅人}「明天出发。」", "【向导】：先看地图。", "{数学}这是集合符号", "{系统}「非角色信息」"])
        #expect(plan.blocks.map(\.id) == [0, 1, 2, 3, 4])
        #expect(plan.firstSpeaker == "旅人")
        #expect(plan.blocks[1].segments[0].kind == .dialogue(speaker: "旅人"))
        #expect(plan.blocks[2].segments[0].text == "先看地图。")
        #expect(plan.blocks[3].segments[0].kind == .narration)
        #expect(plan.blocks[4].segments[0].kind == .narration)
    }

    @Test func metadataAndCommentsStayHiddenAcrossParagraphs() {
        let plan = TavernTextParser.parse(["<konatan_planning~>", "{假角色}「辅助数据」", "<think>更多数据</think>", "</konatan_planning~>", "<!-- Technical Footer Start", "<danmu>装饰</danmu>", "-->", "真正正文", "<htmlcontent>提示</htmlcontent>"])
        #expect(plan.blocks.map(\.id) == [7])
        #expect(plan.blocks[0].segments[0].text == "真正正文")
        #expect(plan.anchor(for: 0) == 7)
    }

    @Test func unclosedReasoningDoesNotLeakButUnclosedOptionsAreKept() {
        #expect(TavernTextParser.parse(["<think>", "尚未结束的辅助内容"]).blocks.isEmpty)
        let plan = TavernTextParser.parse(["正文", "<options>", ">选项一：继续前行。", ">选项二：稍作休息。"])
        #expect(plan.blocks.map(\.id) == [0, 1])
        #expect(plan.blocks[1].segments[0].kind == .auxiliary(title: "剧情选项"))
        #expect(plan.blocks[1].segments[0].text.contains("继续前行"))
        #expect(plan.anchor(for: 3) == 1)
    }

    @Test func mixedInlineBlocksHaveOneStableParagraphAnchor() {
        let plan = TavernTextParser.parse(["开始<options>选项</options>后续", "<tucao>旁注</tucao>", "{旅人}「*心情很好*」"])
        #expect(plan.blocks.map(\.id) == [0, 1, 2])
        #expect(plan.blocks[0].segments.map(\.text) == ["开始", "选项", "后续"])
        #expect(plan.blocks[1].segments[0].kind == .auxiliary(title: "旁注"))
        #expect(plan.blocks[2].segments[0].text == "「*心情很好*」")
    }

    @Test func acceptsExportSpeakerDelimitersAndPreservesTruncatedDialogue() {
        let plan = TavernTextParser.parse(["{{user}}「你好」", "[向导]：欢迎。", "{旅人}「未写完", "<story>普通叙述</story>"])
        #expect(plan.blocks[0].segments[0].kind == .dialogue(speaker: "{{user}}"))
        #expect(plan.blocks[1].segments[0].kind == .dialogue(speaker: "向导"))
        #expect(plan.blocks[2].segments[0].text == "{旅人}「未写完")
        #expect(plan.blocks[3].segments[0].text == "普通叙述")
    }

    @Test @MainActor func cachedPlanTracksBodyRevisionAndOriginalIndices() {
        let chapter = Chapter(sourceURL: "yyreader-local://test/1", title: "正文", sortIndex: 1,
                              bodyText: "<think>辅助数据</think>\n正文\n{向导}「出发。」")
        let cache = TavernReadingPlanCache()
        let plan = cache.plan(chapter: chapter, paragraphs: chapter.paragraphs)
        #expect(plan.blocks.map(\.id) == [1, 2])
        #expect(plan.anchor(for: 0) == 1)
        #expect(plan.anchor(for: 2) == 2)
        chapter.replaceBodyText("新正文")
        #expect(cache.plan(chapter: chapter, paragraphs: chapter.paragraphs).blocks[0].segments[0].text == "新正文")
    }
}
