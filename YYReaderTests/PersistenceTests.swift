import Foundation
import SwiftData
import Testing
@testable import YYReader

@MainActor
struct PersistenceTests {
    @Test
    func savesProgressAndCascadesChapterDeletion() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Book.self, Chapter.self, configurations: configuration)
        let context = container.mainContext
        let book = Book(title: "测试小说", author: "作者", sourceHost: "example.com", catalogURL: "https://example.com/book/")
        let chapter = Chapter(sourceURL: "https://example.com/book/1.html", title: "第1章", sortIndex: 1, bodyText: "第一段\n\n第二段", book: book)
        book.chapters.append(chapter)
        context.insert(book)
        context.insert(chapter)
        chapter.topParagraphIndex = 1
        chapter.readingProgress = 1
        try context.save()

        #expect(chapter.paragraphs == ["第一段", "第二段"])
        #expect(chapter.topParagraphIndex == 1)

        context.delete(book)
        try context.save()
        let remaining = try context.fetch(FetchDescriptor<Chapter>())
        #expect(remaining.isEmpty)
    }
}
