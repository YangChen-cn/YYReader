import CoreFoundation
import Foundation
import SwiftData
import Testing
@testable import YYReader

struct LocalTextImportTests {
    @Test
    func splitsSupportedHeadingsAndPreservesOrder() throws {
        let text = """
        作品说明

        这是第一段前言，长度不需要达到两百字。

        这是第二段前言，因此会独立保存。

        序言
        序言正文第一段。
        序言正文第二段。

        第一章 开始
        第一章正文。

        第 12 章 继续
        第十二章正文。

        第3回 重逢
        回目正文。

        卷一 新篇
        新卷正文。

        尾声
        尾声正文。
        """

        let draft = try LocalTextImportService.prepareImport(
            data: Data(text.utf8),
            fileName: "示例"
        )

        #expect(draft.chapters.map(\.title) == ["前言", "序言", "第一章 开始", "第 12 章 继续", "第3回 重逢", "卷一 新篇", "尾声"])
        #expect(draft.chapters.map(\.sortIndex) == Array(1...7))
        #expect(draft.chapters.first?.bodyText.contains("作品说明") == true)
        #expect(draft.chapters[1].previousURL == draft.chapters[0].sourceURL)
        #expect(draft.chapters[1].nextURL == draft.chapters[2].sourceURL)
    }

    @Test
    func inlineChapterTextDoesNotSplitAndSingleHeadingNeedsSubstantiveBody() throws {
        let inline = "他说第一章只是一个编号，并不是标题。\n接着故事继续发展。"
        let inlineDraft = try LocalTextImportService.prepareImport(data: Data(inline.utf8), fileName: "行内")
        #expect(inlineDraft.chapters.count == 1)
        #expect(inlineDraft.chapters[0].title == "正文")

        let short = "第一章\n只有一句。"
        let shortDraft = try LocalTextImportService.prepareImport(data: Data(short.utf8), fileName: "短篇")
        #expect(shortDraft.chapters.count == 1)
        #expect(shortDraft.chapters[0].title == "正文")

        let reliable = "第一章\n第一段。\n\n第二段。"
        let reliableDraft = try LocalTextImportService.prepareImport(data: Data(reliable.utf8), fileName: "可靠")
        #expect(reliableDraft.chapters.count == 1)
        #expect(reliableDraft.chapters[0].title == "第一章")
    }

    @Test
    func decodesUTF8BOMAndGB18030AndUsesContentIdentity() throws {
        let text = "第一章 开始\n中文正文第一段。\n\n中文正文第二段。"
        let utf8 = Data([0xEF, 0xBB, 0xBF]) + Data(text.utf8)
        let utf8Draft = try LocalTextImportService.prepareImport(data: utf8, fileName: "路径甲")
        let sameBytes = try LocalTextImportService.prepareImport(data: utf8, fileName: "路径乙")
        #expect(utf8Draft.detectedEncoding == "UTF-8 BOM")
        #expect(utf8Draft.sourceBookURL == sameBytes.sourceBookURL)

        let rawEncoding = CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        )
        let gbData = try #require(text.data(using: String.Encoding(rawValue: rawEncoding)))
        let gbDraft = try LocalTextImportService.prepareImport(data: gbData, fileName: "国标")
        #expect(gbDraft.detectedEncoding == "GB18030 / GBK")
        #expect(gbDraft.chapters.first?.title == "第一章 开始")

        let identityVector = try LocalTextImportService.prepareImport(
            data: Data("abc".utf8),
            fileName: "vector"
        )
        #expect(identityVector.sourceBookURL == "yyreader-local://txt/6b1696d3895ebe8ca5de53c421913cae72d95dbf6150df64260081c60ea4793c")
    }

    @Test @MainActor
    func importPersistsBodiesDeduplicatesAndPreservesProgress() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Book.self, Chapter.self, configurations: configuration)
        let loader = MockHTMLLoader(documents: [:])
        let store = LibraryStore(
            modelContext: container.mainContext,
            coordinator: NovelImportCoordinator(loader: loader)
        )
        let text = "第一章 开始\n第一段。\n\n第二段。\n第二章 继续\n第三段。\n\n第四段。"
        let draft = try LocalTextImportService.prepareImport(data: Data(text.utf8), fileName: "本地书")

        let book = try store.importLocalText(draft, title: "本地书", author: "作者")
        let first = try #require(book.chapters.sorted(by: { $0.sortIndex < $1.sortIndex }).first)
        first.topParagraphIndex = 1
        first.readingProgress = 1
        book.currentChapterID = first.id
        try container.mainContext.save()

        let importedAgain = try store.importLocalText(draft, title: "改名后", author: "作者")

        #expect(importedAgain.id == book.id)
        #expect(store.books.count == 1)
        #expect(importedAgain.chapters.count == 2)
        #expect(importedAgain.currentChapterID == first.id)
        #expect(first.topParagraphIndex == 1)
        #expect(importedAgain.chapters.allSatisfy { $0.isCached })
        #expect(importedAgain.hasCatalog)
        #expect(!store.canRefreshSelectedCatalog)
        #expect(!store.canDownloadCurrentChapter)
        #expect(!store.canDeleteOfflineCache)

        store.deleteOfflineCache()
        #expect(importedAgain.chapters.allSatisfy { $0.isCached })
        #expect(loader.requestedURLs.isEmpty)
    }

    @Test @MainActor
    func localPlaceholderNeverUsesWebLoaderAndLocalTailIsFinal() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Book.self, Chapter.self, configurations: configuration)
        let loader = MockHTMLLoader(documents: [:])
        let identity = "yyreader-local://txt/" + String(repeating: "d", count: 64)
        let book = Book(
            title: "同步占位书",
            author: "未知作者",
            sourceHost: "本地 TXT",
            catalogURL: identity,
            hasCatalog: false
        )
        let chapter = Chapter(
            sourceURL: identity + "/chapter/000001",
            title: "当前章节",
            sortIndex: 1,
            book: book
        )
        book.chapters = [chapter]
        book.currentChapterID = chapter.id
        container.mainContext.insert(book)
        container.mainContext.insert(chapter)
        try container.mainContext.save()
        let store = LibraryStore(
            modelContext: container.mainContext,
            coordinator: NovelImportCoordinator(loader: loader)
        )
        store.restoreSelection(bookID: book.id, chapterID: chapter.id)

        await store.ensureSelectedChapterLoaded()

        #expect(loader.requestedURLs.isEmpty)
        #expect(store.presentedError?.message.contains("重新导入同一 TXT") == true)

        chapter.replaceBodyText("本地正文")
        chapter.cachedAt = .now
        store.configureContinuousReading(true)
        #expect(store.continuationStatus(after: chapter.id) == .endOfBook)
    }
}
