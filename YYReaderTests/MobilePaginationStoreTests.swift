#if os(iOS)
import Foundation
import SwiftData
import Testing
@testable import YYReader

@MainActor
struct MobilePaginationStoreTests {
    @Test
    func cancellationAlwaysClearsLoadingAndAllowsRetry() async throws {
        let store = MobilePaginationStore()
        let request = request()
        let paragraphs = [String(repeating: "山间的风穿过窗边，树影落在书页上。", count: 500)]
        let cancelled = try #require(store.start(request: request, paragraphs: paragraphs))
        cancelled.cancel()
        await cancelled.value
        #expect(!store.isPaginating)
        #expect(store.errorMessage == nil)
        #expect(store.completedRequest == nil)
        await store.start(request: request, paragraphs: ["重试后的正文。"])?.value
        #expect(!store.isPaginating)
        #expect(store.completedRequest == request)
        #expect(store.pages.count == 1)
        #expect(store.start(request: request, paragraphs: ["重试后的正文。"]) == nil)
    }

    @Test
    func obsoleteRequestCannotReplaceNewLayoutOrLeaveSpinnerRunning() async throws {
        let store = MobilePaginationStore()
        let oldRequest = request(height: 400)
        let newRequest = request(height: 600)
        let old = store.start(request: oldRequest, paragraphs: [String(repeating: "旧版式的正文。", count: 500)])
        let new = store.start(request: newRequest, paragraphs: ["新请求的正文。"])
        await old?.value
        await new?.value
        #expect(!store.isPaginating)
        #expect(store.completedRequest == newRequest)
        #expect(store.pages.flatMap(\.fragments).map(\.text).joined().contains("新请求"))
    }

    @Test
    func fiveThousandChapterCatalogWithOnlyCurrentBodyNeedsNoDownloadsToPaginate() async throws {
        let container = try ModelContainer(for: Book.self, Chapter.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let book = Book(title: "大目录测试", author: "测试作者", sourceHost: "example.invalid",
                        catalogURL: "https://example.invalid/book/")
        let paragraphs = (0..<60).map { "段落\($0)：山间的风穿过木窗，树影落在书页上。她收起笔，走向溪边的石桥。" }
        book.chapters = (1...5000).map { index in
            Chapter(sourceURL: "https://example.invalid/book/\(index).html", title: "第\(index)章", sortIndex: index,
                    bodyText: index == 1 ? paragraphs.joined(separator: "\n") : nil,
                    cachedAt: index == 1 ? .now : nil, book: book)
        }
        container.mainContext.insert(book)
        try container.mainContext.save()
        let loader = MockHTMLLoader(documents: [:])
        let library = LibraryStore(modelContext: container.mainContext, coordinator: NovelImportCoordinator(loader: loader))
        let current = try #require(book.chapters.first { $0.sortIndex == 1 })
        library.restoreSelection(bookID: book.id, chapterID: current.id)
        library.configureContinuousReading(false)
        let pagination = MobilePaginationStore()
        let started = ContinuousClock.now
        await pagination.start(request: request(chapterID: current.id), paragraphs: library.readerSession.paragraphs(for: current))?.value
        let elapsed = started.duration(to: .now)
        #expect(pagination.pages.count > 1)
        #expect(!pagination.isPaginating)
        #expect(library.readerSession.cachedParagraphChapterCount == 1)
        #expect(loader.requestedURLs.isEmpty)
        #expect(book.chapters.filter(\.isCached).count == 1)
        print("5000 chapter catalog, current chapter pagination: \(elapsed)")
    }

    private func request(chapterID: UUID = UUID(), height: Double = 640) -> MobilePaginationRequest {
        let font = MobileReadingFont.resolve(.system, size: 20)
        return MobilePaginationRequest(chapterID: chapterID,
            layout: MobilePaginationLayout(width: 350, height: height, fontName: font.fontName, fontSize: 20,
                                           lineHeight: font.lineHeight, lineSpacing: 8, paragraphSpacing: 12, usesFirstLineIndent: true),
            contentRevision: 0)
    }
}
#endif
