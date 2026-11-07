import Foundation
import SwiftData
import Testing
@testable import YYReader

struct CloudTextSyncTests {
    private func draft() throws -> LocalTextImportDraft {
        try LocalTextImportService.prepareImport(data: Data("[#0]\n（第0楼）\n{旅人}「开始。」\n--------------------\n[#2]\n（第2楼）\n第一段。\n第二段。\n第三段。".utf8), fileName: "楼层导出")
    }

    @Test @MainActor
    func explicitUploadDownloadsAndRestoresFloorAndParagraphWithoutSelectingBook() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let original = try draft()
        let container = try ModelContainer(for: Book.self, Chapter.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = LibraryStore(modelContext: container.mainContext, coordinator: NovelImportCoordinator(loader: MockHTMLLoader(documents: [:])))
        let archive = CloudTextArchive(draft: original, author: "作者")
        let cloud = CloudTextStore()
        try await cloud.upload(archive, selectedFolder: folder)
        let mac = SyncEngine(device: .mac)
        let record = SyncBookRecord(sourceURL: original.sourceBookURL, title: "楼层导出", author: "作者",
            currentChapterURL: original.chapters[1].sourceURL, currentChapterIndex: 2,
            paragraphIndex: 2, progress: 0.6, updatedAt: .now)
        let published = try await mac.synchronize(selectedFolder: folder, localBooks: [record])
        #expect(published.books == [record]) // First device must publish before its peer exists.
        let result = try await SyncEngine(device: .ios).synchronize(selectedFolder: folder, localBooks: [])
        try store.applySyncRecords(result.books)
        #expect(store.needsCloudText(sourceURL: original.sourceBookURL))
        let downloaded = try #require(try await cloud.download(sourceURL: original.sourceBookURL,
            selectedFolder: SyncEngine.syncDirectory(in: folder)))
        #expect(downloaded.draft == original)
        let book = try store.importLocalText(downloaded.draft, title: record.title, author: record.author,
            importedAt: record.updatedAt, selectAfterImport: false)
        #expect(store.selectedBookID == nil)
        #expect(book.chapters.count == 2)
        let current = try #require(book.chapters.first { $0.id == book.currentChapterID })
        #expect(current.title == "第2楼")
        #expect(current.topParagraphIndex == 2)
        #expect(current.readingProgress == 0.6)
        #expect(!store.needsCloudText(sourceURL: original.sourceBookURL))
        // Reimporting a renamed copy uses the original file hash and keeps progress.
        let reimported = try store.importLocalText(original, title: "文件改名", author: "作者")
        #expect(reimported.id == book.id)
        #expect(current.topParagraphIndex == 2)
        #expect(store.books.count == 1)
    }

    @Test
    func absentUploadDoesNotCreateContentAndRejectsWrongIdentity() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let original = try draft()
        let cloud = CloudTextStore()
        #expect(try await cloud.download(sourceURL: original.sourceBookURL, selectedFolder: folder) == nil)
        #expect(!FileManager.default.fileExists(atPath: SyncEngine.syncDirectory(in: folder).path))
        try await cloud.upload(CloudTextArchive(draft: original, author: "作者"), selectedFolder: folder)
        let other = "yyreader-local://txt/" + String(repeating: "c", count: 64)
        let originalURL = try CloudTextStore.fileURL(sourceURL: original.sourceBookURL, selectedFolder: folder)
        let otherURL = try CloudTextStore.fileURL(sourceURL: other, selectedFolder: folder)
        try FileManager.default.copyItem(at: originalURL, to: otherURL)
        await #expect(throws: (any Error).self) {
            _ = try await cloud.download(sourceURL: other, selectedFolder: folder)
        }
        #expect(throws: (any Error).self) {
            try CloudTextStore.fileURL(sourceURL: "yyreader-local://txt/../../outside", selectedFolder: folder)
        }
    }
}
