import Foundation

actor SyncEngine {
    static let directoryName = "YYReaderSync"
    static let macFileName = "mac.json"
    static let windowsFileName = "windows.json"

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func publishLocal(
        selectedFolder: URL,
        localBooks: [SyncBookRecord],
        now: Date = .now
    ) throws -> Date {
        let directory = selectedFolder.appendingPathComponent(Self.directoryName, isDirectory: true)
        try ensureDirectory(directory)

        let macURL = directory.appendingPathComponent(Self.macFileName)
        let previousMac = try readSnapshotIfPresent(at: macURL, expectedDevice: .mac)
        let snapshot = SyncSnapshot(device: .mac, updatedAt: now, books: localBooks)
        if previousMac?.version != SyncSnapshot.currentVersion || previousMac?.books != localBooks {
            try atomicWrite(try SyncSnapshotCodec.encode(snapshot), to: macURL)
        }
        return now
    }

    func synchronize(
        selectedFolder: URL,
        localBooks: [SyncBookRecord],
        chapterRanksByBook: SyncMerger.ChapterRanksByBook = [:],
        now: Date = .now
    ) throws -> SyncResult {
        let directory = selectedFolder.appendingPathComponent(Self.directoryName, isDirectory: true)
        try ensureDirectory(directory)

        let macURL = directory.appendingPathComponent(Self.macFileName)
        let windowsURL = directory.appendingPathComponent(Self.windowsFileName)
        let previousMac = try readSnapshotIfPresent(at: macURL, expectedDevice: .mac)
        let windows = try readSnapshotIfPresent(at: windowsURL, expectedDevice: .windows)
        let mergedBooks = SyncMerger.merge(
            (previousMac?.books ?? []) + localBooks + (windows?.books ?? []),
            chapterRanksByBook: chapterRanksByBook
        )
        let snapshot = SyncSnapshot(device: .mac, updatedAt: now, books: mergedBooks)
        if previousMac?.version != SyncSnapshot.currentVersion || previousMac?.books != mergedBooks {
            try atomicWrite(try SyncSnapshotCodec.encode(snapshot), to: macURL)
        }

        return SyncResult(
            books: mergedBooks,
            synchronizedAt: now,
            windowsFileSignature: try fileSignature(at: windowsURL)
        )
    }

    func windowsFileSignature(selectedFolder: URL) throws -> SyncFileSignature? {
        let url = selectedFolder
            .appendingPathComponent(Self.directoryName, isDirectory: true)
            .appendingPathComponent(Self.windowsFileName)
        return try fileSignature(at: url)
    }

    private func ensureDirectory(_ directory: URL) throws {
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else { throw SyncError.folderUnavailable }
            return
        }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func readSnapshotIfPresent(
        at url: URL,
        expectedDevice: SyncDevice
    ) throws -> SyncSnapshot? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try SyncSnapshotCodec.decode(data, expectedDevice: expectedDevice)
    }

    private func atomicWrite(_ data: Data, to destination: URL) throws {
        let temporaryURL = destination
            .deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString).tmp")
        do {
            try data.write(to: temporaryURL)
            if fileManager.fileExists(atPath: destination.path) {
                _ = try fileManager.replaceItemAt(
                    destination,
                    withItemAt: temporaryURL,
                    backupItemName: nil,
                    options: []
                )
            } else {
                try fileManager.moveItem(at: temporaryURL, to: destination)
            }
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }

    private func fileSignature(at url: URL) throws -> SyncFileSignature? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        guard let modificationDate = values.contentModificationDate else { return nil }
        return SyncFileSignature(
            modificationDate: modificationDate,
            fileSize: Int64(values.fileSize ?? 0)
        )
    }
}
