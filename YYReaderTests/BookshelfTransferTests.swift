import Foundation
import SwiftData
import Testing
@testable import YYReader

struct BookshelfTransferTests {
    @Test
    func codecMatchesWindowsV1AndIgnoresUnknownFields() throws {
        let data = Data(#"""
        {
          "format": "yyreader-bookshelf",
          "version": 1,
          "exportedAt": "2026-08-12T01:02:03.1234567Z",
          "future": true,
          "books": [{
            "sourceURL": "https://EXAMPLE.com:443/book/#fragment",
            "title": "测试书",
            "author": "作者",
            "currentChapterURL": "https://example.com/book/3.html",
            "paragraphIndex": 12,
            "progress": 0.63,
            "futureBookField": "ignored"
          }]
        }
        """#.utf8)

        let document = try BookshelfTransferCodec.decode(data)
        let roundTrip = try BookshelfTransferCodec.decode(BookshelfTransferCodec.encode(document))

        #expect(document.format == "yyreader-bookshelf")
        #expect(document.version == 1)
        #expect(document.books.count == 1)
        #expect(document.books[0].paragraphIndex == 12)
        #expect(roundTrip == document)
    }

    @Test
    func codecSeparatesMalformedAndUnsupportedDocuments() {
        #expect(throws: BookshelfTransferError.self) {
            _ = try BookshelfTransferCodec.decode(Data("{".utf8))
        }
        #expect(throws: BookshelfTransferError.unsupportedVersion(2)) {
            _ = try BookshelfTransferCodec.decode(Data(#"""
            {"format":"yyreader-bookshelf","version":2,"exportedAt":"2026-08-12T00:00:00Z","books":[]}
            """#.utf8))
        }
    }

    @Test
    func plannerSeparatesNewExistingDuplicateAndInvalidBooks() {
        let document = BookshelfTransferDocument(
            books: [
                .init(sourceURL: "https://example.com/book/", title: "旧书", author: "作者"),
                .init(sourceURL: "HTTPS://EXAMPLE.COM:443/book/#x", title: "重复", author: "作者"),
                .init(sourceURL: "https://example.com/new/", title: "新书", author: "作者"),
                .init(sourceURL: "not a url", title: "坏数据", author: "作者")
            ]
        )

        let preview = BookshelfTransferPlanner.preview(
            document: document,
            existingSourceURLs: ["https://example.com/book/"]
        )

        #expect(preview.totalCount == 4)
        #expect(preview.existingCount == 1)
        #expect(preview.duplicateCount == 1)
        #expect(preview.newCount == 1)
        #expect(preview.invalidCount == 1)
    }

    @Test @MainActor
    func storeImportsExistingAndNewBooksIdempotentlyWithoutBodyCache() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Book.self, Chapter.self, configurations: configuration)
        let context = container.mainContext
        context.autosaveEnabled = false
        let oldDate = Date(timeIntervalSince1970: 100)
        let importedAt = Date(timeIntervalSince1970: 200)
        let book = Book(
            title: "旧标题",
            author: "旧作者",
            sourceHost: "example.com",
            catalogURL: "https://example.com/book/",
            updatedAt: oldDate
        )
        let chapter = Chapter(
            sourceURL: "https://example.com/book/3.html",
            title: "第三章",
            sortIndex: 3,
            bodyText: "保留的本地正文",
            lastReadAt: oldDate,
            book: book
        )
        book.chapters = [chapter]
        book.currentChapterID = chapter.id
        context.insert(book)
        context.insert(chapter)
        try context.save()
        let store = LibraryStore(
            modelContext: context,
            coordinator: NovelImportCoordinator(loader: MockHTMLLoader(documents: [:]))
        )
        let document = BookshelfTransferDocument(
            books: [
                .init(
                    sourceURL: "HTTPS://EXAMPLE.COM:443/book/#x",
                    title: "新标题",
                    author: "新作者",
                    currentChapterURL: chapter.sourceURL,
                    paragraphIndex: 18,
                    progress: 0.72
                ),
                .init(
                    sourceURL: "https://example.com/new/",
                    title: "新增小说",
                    author: "新增作者",
                    currentChapterURL: "https://example.com/new/1.html",
                    paragraphIndex: 2,
                    progress: 0.2
                )
            ]
        )

        let first = try store.importBookshelfTransfer(document, importedAt: importedAt)
        let second = try store.importBookshelfTransfer(document, importedAt: importedAt)

        #expect(first.succeeded == 2)
        #expect(second.succeeded == 2)
        #expect(store.books.count == 2)
        #expect(book.title == "新标题")
        #expect(book.author == "新作者")
        #expect(chapter.bodyText == "保留的本地正文")
        #expect(chapter.topParagraphIndex == 18)
        #expect(chapter.readingProgress == 0.72)
        let imported = try #require(store.books.first { $0.sourceBookURL == "https://example.com/new/" })
        #expect(imported.chapters.count == 1)
        #expect(imported.chapters[0].bodyText == nil)
        #expect(!context.hasChanges)
    }

    @Test @MainActor
    func storeExportContainsOnlyCrossPlatformIdentityAndPosition() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Book.self, Chapter.self, configurations: configuration)
        let context = container.mainContext
        let book = Book(
            title: "测试书",
            author: "作者",
            sourceHost: "example.com",
            catalogURL: "https://example.com/book/"
        )
        let chapter = Chapter(
            sourceURL: "https://example.com/book/3.html",
            title: "第三章",
            sortIndex: 3,
            bodyText: "不得导出的正文",
            topParagraphIndex: 42,
            readingProgress: 0.63,
            book: book
        )
        book.chapters = [chapter]
        book.currentChapterID = chapter.id
        context.insert(book)
        context.insert(chapter)
        try context.save()
        let store = LibraryStore(
            modelContext: context,
            coordinator: NovelImportCoordinator(loader: MockHTMLLoader(documents: [:]))
        )

        let data = try BookshelfTransferCodec.encode(
            store.bookshelfTransferDocument(exportedAt: Date(timeIntervalSince1970: 100))
        )
        let text = try #require(String(data: data, encoding: .utf8))
        let decoded = try BookshelfTransferCodec.decode(data)

        #expect(decoded.books[0].currentChapterURL == chapter.sourceURL)
        #expect(decoded.books[0].paragraphIndex == 42)
        #expect(decoded.books[0].progress == 0.63)
        #expect(!text.contains("bodyText"))
        #expect(!text.localizedCaseInsensitiveContains("cookie"))
    }
}
