import Foundation
import Testing
@testable import YYReader

struct IOSSyncTests {
    @Test
    func choosingSyncDirectoryDirectlyReadsMacAndWritesIosBesideIt() async throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: parent) }
        let directory = parent.appendingPathComponent(SyncEngine.directoryName, isDirectory: true)
        let book = SyncBookRecord(sourceURL: "https://example.com/direct/", title: "目录选择测试", author: "作者", updatedAt: Date(timeIntervalSince1970: 100))
        _ = try await SyncEngine(device: .mac).publishLocal(selectedFolder: parent, localBooks: [book], includeLocalText: false)
        let macURL = directory.appendingPathComponent("mac.json")
        let macData = try Data(contentsOf: macURL)
        let engine = SyncEngine(device: .ios)
        let result = try await engine.synchronize(selectedFolder: directory, localBooks: [])
        #expect(result.books == [book])
        #expect(result.remoteFileSignatures[.mac] != nil)
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("ios.json").path))
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(SyncEngine.directoryName).path))
        #expect(try Data(contentsOf: macURL) == macData)
        #expect(try await engine.remoteFileSignatures(selectedFolder: directory)[.mac] != nil)
    }

    @Test
    func iosWritesOnlyOwnSnapshotAndMacReadsItIdempotently() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let mac = SyncEngine(device: .mac)
        let ios = SyncEngine(device: .ios)
        let book = SyncBookRecord(sourceURL: "https://example.com/book/", title: "同步测试", author: "作者",
                                 currentChapterURL: "https://example.com/book/2.html", currentChapterIndex: 2,
                                 paragraphIndex: 3, progress: 0.2, updatedAt: Date(timeIntervalSince1970: 100))
        _ = try await mac.publishLocal(selectedFolder: folder, localBooks: [book], includeLocalText: false)
        let directory = folder.appendingPathComponent(SyncEngine.directoryName)
        let macURL = directory.appendingPathComponent("mac.json")
        let originalMac = try Data(contentsOf: macURL)
        let initial = try await ios.synchronize(selectedFolder: folder, localBooks: [])
        #expect(initial.books == [book])
        #expect(initial.remoteFileSignatures[.mac] != nil)
        #expect(try Data(contentsOf: macURL) == originalMac)
        var advanced = book
        advanced.currentChapterIndex = 3
        advanced.currentChapterURL = "https://example.com/book/3.html"
        advanced.paragraphIndex = 1
        advanced.progress = 0.05
        _ = try await ios.publishLocal(selectedFolder: folder, localBooks: [advanced], includeLocalText: false)
        let iosURL = directory.appendingPathComponent("ios.json")
        let iosData = try Data(contentsOf: iosURL)
        #expect(try SyncSnapshotCodec.decode(iosData, expectedDevice: .ios).books == [advanced])
        let result = try await mac.synchronize(selectedFolder: folder, localBooks: [book])
        #expect(result.books.first?.currentChapterIndex == 3)
        #expect(result.remoteFileSignatures[.ios] != nil)
        #expect(try Data(contentsOf: iosURL) == iosData)
        let macData = try Data(contentsOf: macURL)
        _ = try await mac.synchronize(selectedFolder: folder, localBooks: result.books)
        #expect(try Data(contentsOf: macURL) == macData)
    }

    @Test
    func iosLocalPublishIgnoresInvalidPeersAndFailedMergePreservesSnapshots() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let directory = folder.appendingPathComponent(SyncEngine.directoryName)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let malformed = Data("{".utf8)
        try malformed.write(to: directory.appendingPathComponent("mac.json"))
        try malformed.write(to: directory.appendingPathComponent("windows.json"))
        let ios = SyncEngine(device: .ios)
        let local = SyncBookRecord(sourceURL: "https://example.com/ios/", title: "手机书籍", author: "作者", updatedAt: .now)
        _ = try await ios.publishLocal(selectedFolder: folder, localBooks: [local], includeLocalText: false)
        let ownURL = directory.appendingPathComponent("ios.json")
        let ownData = try Data(contentsOf: ownURL)
        await #expect(throws: SyncError.self) {
            try await ios.synchronize(selectedFolder: folder, localBooks: [local])
        }
        #expect(try Data(contentsOf: ownURL) == ownData)
        #expect(try Data(contentsOf: directory.appendingPathComponent("mac.json")) == malformed)
        #expect(try Data(contentsOf: directory.appendingPathComponent("windows.json")) == malformed)
    }

    @Test
    func iosDeletionPropagatesToMac() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let book = SyncBookRecord(sourceURL: "https://example.com/deleted/", title: "测试书", author: "作者",
                                 updatedAt: Date(timeIntervalSince1970: 100))
        let mac = SyncEngine(device: .mac)
        let ios = SyncEngine(device: .ios)
        _ = try await mac.publishLocal(selectedFolder: folder, localBooks: [book], includeLocalText: false)
        var tombstone = book
        tombstone.deletedAt = Date(timeIntervalSince1970: 200)
        _ = try await ios.publishLocal(selectedFolder: folder, localBooks: [tombstone], includeLocalText: false)
        let merged = try await mac.synchronize(selectedFolder: folder, localBooks: [book])
        #expect(merged.books.first?.isDeleted == true)
    }
}
