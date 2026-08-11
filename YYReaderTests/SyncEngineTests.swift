import Foundation
import SwiftData
import Testing
@testable import YYReader

struct SyncEngineTests {
    @Test @MainActor
    func folderMonitorCancellationStaysOnMainExecutor() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("YYReaderMonitorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let monitor = SyncFolderMonitor()

        monitor.start(directory: directory) {}
        monitor.stop()

        // DispatchSource cancellation is asynchronous. Yield long enough for its
        // handler to run so executor violations fail this regression test.
        try await Task.sleep(for: .milliseconds(50))
    }

    @Test
    func snapshotV1DecodesWindowsDatesAndIgnoresUnknownFields() throws {
        let data = Data(#"""
        {
          "format": "yyreader-sync",
          "version": 1,
          "device": "windows",
          "updatedAt": "2026-08-12T01:02:03.1234567Z",
          "future": true,
          "books": [{
            "sourceURL": "https://EXAMPLE.com:443/book/#fragment",
            "title": "测试书",
            "author": "作者",
            "currentChapterURL": "https://example.com/book/3.html",
            "paragraphIndex": 12,
            "progress": 0.63,
            "lastReadAt": "2026-08-12T01:00:00Z",
            "updatedAt": "2026-08-11T01:00:00Z",
            "deletedAt": null,
            "futureBookField": "ignored"
          }]
        }
        """#.utf8)

        let snapshot = try SyncSnapshotCodec.decode(data, expectedDevice: .windows)

        #expect(snapshot.format == "yyreader-sync")
        #expect(snapshot.version == 1)
        #expect(snapshot.device == .windows)
        #expect(snapshot.books.count == 1)
        #expect(snapshot.books[0].currentChapterIndex == nil)
        #expect(snapshot.books[0].paragraphIndex == 12)
    }

    @Test
    func snapshotV2EncodesChapterIndex() throws {
        let record = SyncBookRecord(
            sourceURL: "https://example.com/book/",
            title: "测试书",
            author: "作者",
            currentChapterURL: "https://example.com/book/9.html",
            currentChapterIndex: 9,
            paragraphIndex: 12,
            progress: 0.5,
            updatedAt: Date(timeIntervalSince1970: 100)
        )

        let data = try SyncSnapshotCodec.encode(SyncSnapshot(device: .mac, books: [record]))
        let decoded = try SyncSnapshotCodec.decode(data, expectedDevice: .mac)

        #expect(decoded.version == 2)
        #expect(decoded.books[0].currentChapterIndex == 9)
    }

    @Test
    func mergeSelectsMetadataAndReadingPositionIndependently() throws {
        let metadataDate = try #require(ISO8601DateFormatter().date(from: "2026-08-12T12:00:00Z"))
        let olderMetadataDate = try #require(ISO8601DateFormatter().date(from: "2026-08-11T12:00:00Z"))
        let newerReadingDate = try #require(ISO8601DateFormatter().date(from: "2026-08-12T13:00:00Z"))
        let olderReadingDate = try #require(ISO8601DateFormatter().date(from: "2026-08-12T11:00:00Z"))
        let mac = SyncBookRecord(
            sourceURL: "https://example.com/book/",
            title: "旧标题",
            author: "旧作者",
            currentChapterURL: "https://example.com/book/9.html",
            currentChapterIndex: 9,
            paragraphIndex: 42,
            progress: 0.75,
            lastReadAt: olderReadingDate,
            updatedAt: olderMetadataDate
        )
        let windows = SyncBookRecord(
            sourceURL: "HTTPS://EXAMPLE.COM:443/book/#x",
            title: "新标题",
            author: "新作者",
            currentChapterURL: "https://example.com/book/3.html",
            currentChapterIndex: 3,
            paragraphIndex: 8,
            progress: 0.25,
            lastReadAt: newerReadingDate,
            updatedAt: metadataDate
        )

        let merged = try #require(SyncMerger.merge([mac, windows]).first)

        #expect(merged.sourceURL == "https://example.com/book/")
        #expect(merged.title == "新标题")
        #expect(merged.author == "新作者")
        #expect(merged.currentChapterURL == mac.currentChapterURL)
        #expect(merged.paragraphIndex == 42)
        #expect(merged.progress == 0.75)
        #expect(merged.lastReadAt == newerReadingDate)
    }

    @Test
    func mergeSameChapterOnlyMovesParagraphForwardRegardlessOfTime() throws {
        let newerReadingDate = try #require(ISO8601DateFormatter().date(from: "2026-08-12T13:00:00Z"))
        let olderReadingDate = try #require(ISO8601DateFormatter().date(from: "2026-08-12T11:00:00Z"))
        let behind = SyncBookRecord(
            sourceURL: "https://example.com/book/",
            title: "书",
            author: "作者",
            currentChapterURL: "https://example.com/book/9.html",
            currentChapterIndex: 9,
            paragraphIndex: 4,
            progress: 0.2,
            lastReadAt: newerReadingDate,
            updatedAt: newerReadingDate
        )
        let ahead = SyncBookRecord(
            sourceURL: "https://example.com/book/",
            title: "书",
            author: "作者",
            currentChapterURL: "https://example.com/book/9.html",
            currentChapterIndex: 9,
            paragraphIndex: 40,
            progress: 0.8,
            lastReadAt: olderReadingDate,
            updatedAt: olderReadingDate
        )

        let merged = try #require(SyncMerger.merge([behind, ahead]).first)

        #expect(merged.paragraphIndex == 40)
        #expect(merged.progress == 0.8)
        #expect(merged.lastReadAt == newerReadingDate)
    }

    @Test
    func tombstoneWinsOlderMetadataAndNewerMetadataResurrects() throws {
        let old = try #require(ISO8601DateFormatter().date(from: "2026-08-10T00:00:00Z"))
        let deletion = try #require(ISO8601DateFormatter().date(from: "2026-08-11T00:00:00Z"))
        let renewed = try #require(ISO8601DateFormatter().date(from: "2026-08-12T00:00:00Z"))
        let active = SyncBookRecord(
            sourceURL: "https://example.com/book/",
            title: "书",
            author: "作者",
            updatedAt: old
        )
        let tombstone = SyncBookRecord(
            sourceURL: "https://example.com/book/",
            title: "书",
            author: "作者",
            updatedAt: old,
            deletedAt: deletion
        )

        let deleted = try #require(SyncMerger.merge([active, tombstone]).first)
        #expect(deleted.isDeleted)
        #expect(deleted.deletedAt == deletion)

        var resurrected = active
        resurrected.updatedAt = renewed
        let merged = try #require(SyncMerger.merge([tombstone, resurrected]).first)
        #expect(!merged.isDeleted)
        #expect(merged.deletedAt == nil)
    }

    @Test
    func engineReadsWindowsWritesOnlyMacAndIsIdempotent() async throws {
        let selectedFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("YYReaderSyncTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: selectedFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: selectedFolder) }
        let syncDirectory = selectedFolder.appendingPathComponent(SyncEngine.directoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: syncDirectory, withIntermediateDirectories: true)
        let windowsURL = syncDirectory.appendingPathComponent(SyncEngine.windowsFileName)
        let windowsBook = SyncBookRecord(
            sourceURL: "https://example.com/windows/",
            title: "Windows 书籍",
            author: "作者",
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let windowsData = try SyncSnapshotCodec.encode(
            SyncSnapshot(device: .windows, updatedAt: Date(timeIntervalSince1970: 110), books: [windowsBook])
        )
        try windowsData.write(to: windowsURL)
        let engine = SyncEngine()
        let local = SyncBookRecord(
            sourceURL: "https://example.com/mac/",
            title: "Mac 书籍",
            author: "作者",
            updatedAt: Date(timeIntervalSince1970: 120)
        )

        let first = try await engine.synchronize(
            selectedFolder: selectedFolder,
            localBooks: [local],
            now: Date(timeIntervalSince1970: 130)
        )
        let macURL = syncDirectory.appendingPathComponent(SyncEngine.macFileName)
        let firstMacData = try Data(contentsOf: macURL)
        let second = try await engine.synchronize(
            selectedFolder: selectedFolder,
            localBooks: first.books,
            now: Date(timeIntervalSince1970: 140)
        )

        #expect(first.books == second.books)
        #expect(first.books.count == 2)
        #expect(try Data(contentsOf: windowsURL) == windowsData)
        #expect(try Data(contentsOf: macURL) == firstMacData)
        let macSnapshot = try SyncSnapshotCodec.decode(Data(contentsOf: macURL), expectedDevice: .mac)
        #expect(macSnapshot.books == first.books)
        let names = try FileManager.default.contentsOfDirectory(atPath: syncDirectory.path)
        #expect(Set(names) == [SyncEngine.macFileName, SyncEngine.windowsFileName])
        let encoded = try #require(String(data: Data(contentsOf: macURL), encoding: .utf8))
        #expect(!encoded.contains("bodyText"))
        #expect(!encoded.contains("cookie"))
    }

    @Test
    func unreadableWindowsSnapshotDoesNotOverwriteMacSnapshot() async throws {
        let selectedFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("YYReaderSyncFailureTests-\(UUID().uuidString)", isDirectory: true)
        let syncDirectory = selectedFolder.appendingPathComponent(SyncEngine.directoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: syncDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: selectedFolder) }
        let macURL = syncDirectory.appendingPathComponent(SyncEngine.macFileName)
        let windowsURL = syncDirectory.appendingPathComponent(SyncEngine.windowsFileName)
        let originalMacData = try SyncSnapshotCodec.encode(SyncSnapshot(device: .mac, books: []))
        try originalMacData.write(to: macURL)
        try Data("{".utf8).write(to: windowsURL)
        let engine = SyncEngine()

        await #expect(throws: SyncError.self) {
            _ = try await engine.synchronize(selectedFolder: selectedFolder, localBooks: [])
        }
        #expect(try Data(contentsOf: macURL) == originalMacData)
    }

    @Test @MainActor
    func libraryStoreAppliesMergedMetadataAndProgressWithoutCachingBody() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Book.self, Chapter.self, configurations: configuration)
        let context = container.mainContext
        context.autosaveEnabled = false
        let oldDate = Date(timeIntervalSince1970: 100)
        let newDate = Date(timeIntervalSince1970: 200)
        let readDate = Date(timeIntervalSince1970: 50)
        let book = Book(
            title: "旧标题",
            author: "旧作者",
            sourceHost: "example.com",
            catalogURL: "https://EXAMPLE.com:443/book/#old",
            updatedAt: oldDate
        )
        let chapter = Chapter(
            sourceURL: "https://example.com/book/3.html",
            title: "第3章",
            sortIndex: 3,
            bodyText: "本地缓存正文",
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
        let record = SyncBookRecord(
            sourceURL: "https://example.com/book/",
            title: "新标题",
            author: "新作者",
            currentChapterURL: chapter.sourceURL,
            currentChapterIndex: 3,
            paragraphIndex: 8,
            progress: 0.5,
            lastReadAt: readDate,
            updatedAt: newDate
        )

        try store.applySyncRecords([record])
        try store.applySyncRecords([record])

        #expect(store.books.count == 1)
        #expect(store.books[0].title == "新标题")
        #expect(store.books[0].author == "新作者")
        #expect(store.books[0].chapters.count == 1)
        #expect(store.books[0].chapters[0].bodyText == "本地缓存正文")
        #expect(store.books[0].chapters[0].topParagraphIndex == 8)
        #expect(store.books[0].chapters[0].readingProgress == 0.5)
        #expect(store.books[0].chapters[0].lastReadAt == oldDate)
        #expect(!context.hasChanges)
    }

    @Test @MainActor
    func libraryStoreDoesNotMoveBackToEarlierChapterWithNewerTimestamp() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Book.self, Chapter.self, configurations: configuration)
        let context = container.mainContext
        context.autosaveEnabled = false
        let book = Book(
            title: "书",
            author: "作者",
            sourceHost: "example.com",
            catalogURL: "https://example.com/book/",
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let earlier = Chapter(
            sourceURL: "https://example.com/book/3.html",
            title: "第3章",
            sortIndex: 3,
            lastReadAt: Date(timeIntervalSince1970: 300),
            topParagraphIndex: 20,
            readingProgress: 0.8,
            book: book
        )
        let later = Chapter(
            sourceURL: "https://example.com/book/9.html",
            title: "第9章",
            sortIndex: 9,
            lastReadAt: Date(timeIntervalSince1970: 200),
            topParagraphIndex: 4,
            readingProgress: 0.2,
            book: book
        )
        book.chapters = [earlier, later]
        book.currentChapterID = later.id
        context.insert(book)
        context.insert(earlier)
        context.insert(later)
        try context.save()
        let store = LibraryStore(
            modelContext: context,
            coordinator: NovelImportCoordinator(loader: MockHTMLLoader(documents: [:]))
        )
        let incoming = SyncBookRecord(
            sourceURL: book.sourceBookURL,
            title: book.title,
            author: book.author,
            currentChapterURL: earlier.sourceURL,
            currentChapterIndex: earlier.sortIndex,
            paragraphIndex: 30,
            progress: 0.9,
            lastReadAt: Date(timeIntervalSince1970: 400),
            updatedAt: book.updatedAt
        )

        try store.applySyncRecords([incoming])

        #expect(store.books[0].currentChapterID == later.id)
        #expect(later.topParagraphIndex == 4)
        #expect(!context.hasChanges)
    }

    @Test @MainActor
    func libraryStoreAppliesTombstoneIdempotently() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Book.self, Chapter.self, configurations: configuration)
        let context = container.mainContext
        let updatedAt = Date(timeIntervalSince1970: 100)
        let deletedAt = Date(timeIntervalSince1970: 200)
        let book = Book(
            title: "待删除",
            author: "作者",
            sourceHost: "example.com",
            catalogURL: "https://example.com/deleted/",
            updatedAt: updatedAt
        )
        context.insert(book)
        try context.save()
        let store = LibraryStore(
            modelContext: context,
            coordinator: NovelImportCoordinator(loader: MockHTMLLoader(documents: [:]))
        )
        let tombstone = SyncBookRecord(
            sourceURL: book.sourceBookURL,
            title: book.title,
            author: book.author,
            updatedAt: updatedAt,
            deletedAt: deletedAt
        )

        try store.applySyncRecords([tombstone])
        try store.applySyncRecords([tombstone])

        #expect(store.books.isEmpty)
        #expect(!context.hasChanges)
    }
}
