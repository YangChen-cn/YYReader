import Foundation

actor SyncEngine {
    static let directoryName = "YYReaderSync"
    static let macFileName = "mac.json"
    static let windowsFileName = "windows.json"
    static let localTextCapability = "local-txt-v1"
    static func syncDirectory(in selectedFolder: URL) -> URL {
        selectedFolder.lastPathComponent == directoryName
            ? selectedFolder
            : selectedFolder.appendingPathComponent(directoryName, isDirectory: true)
    }
    private static let localCapabilities = [localTextCapability]

    private let device: SyncDevice
    private let fileManager: FileManager

    init(device: SyncDevice = .current, fileManager: FileManager = .default) {
        self.device = device
        self.fileManager = fileManager
    }

    func publishLocal(
        selectedFolder: URL,
        localBooks: [SyncBookRecord],
        includeLocalText: Bool,
        now: Date = .now
    ) throws -> Date {
        let directory = Self.syncDirectory(in: selectedFolder)
        try ensureDirectory(directory)

        let localURL = directory.appendingPathComponent(device.fileName)
        let previousLocal = try readSnapshotIfPresent(at: localURL, expectedDevice: device)
        let publishedBooks = filteredBooks(localBooks, includeLocalText: includeLocalText)
        let snapshot = SyncSnapshot(
            device: device,
            updatedAt: now,
            capabilities: Self.localCapabilities,
            books: publishedBooks
        )
        if previousLocal?.version != SyncSnapshot.currentVersion
            || previousLocal?.capabilities != snapshot.capabilities
            || previousLocal?.books != publishedBooks {
            try atomicWrite(try SyncSnapshotCodec.encode(snapshot), to: localURL)
        }
        return now
    }

    func synchronize(
        selectedFolder: URL,
        localBooks: [SyncBookRecord],
        chapterRanksByBook: SyncMerger.ChapterRanksByBook = [:],
        now: Date = .now
    ) throws -> SyncResult {
        let directory = Self.syncDirectory(in: selectedFolder)
        try ensureDirectory(directory)

        let localURL = directory.appendingPathComponent(device.fileName)
        let previousLocal = try readSnapshotIfPresent(at: localURL, expectedDevice: device)
        let signatures = try remoteFileSignatures(selectedFolder: selectedFolder)
        let remotes = try device.peers.compactMap { peer in
            try readSnapshotIfPresent(at: directory.appendingPathComponent(peer.fileName), expectedDevice: peer)
        }
        let remoteSupportsLocalText = !remotes.isEmpty
            && remotes.allSatisfy { $0.capabilities.contains(Self.localTextCapability) }
        let mergedBooks = SyncMerger.merge(
            filteredBooks(previousLocal?.books ?? [], includeLocalText: remoteSupportsLocalText)
                + filteredBooks(localBooks, includeLocalText: remoteSupportsLocalText)
                + filteredBooks(remotes.flatMap(\.books), includeLocalText: remoteSupportsLocalText),
            chapterRanksByBook: chapterRanksByBook
        )
        let snapshot = SyncSnapshot(
            device: device,
            updatedAt: now,
            capabilities: Self.localCapabilities,
            books: mergedBooks
        )
        if previousLocal?.version != SyncSnapshot.currentVersion
            || previousLocal?.capabilities != snapshot.capabilities
            || previousLocal?.books != mergedBooks {
            try atomicWrite(try SyncSnapshotCodec.encode(snapshot), to: localURL)
        }

        return SyncResult(
            books: mergedBooks,
            synchronizedAt: now,
            remoteFileSignatures: signatures,
            remoteCapabilities: remoteSupportsLocalText ? Self.localCapabilities : []
        )
    }

    private func filteredBooks(
        _ books: [SyncBookRecord],
        includeLocalText: Bool
    ) -> [SyncBookRecord] {
        guard !includeLocalText else { return books }
        return books.filter { BookSourceKind.resolve($0.sourceURL) != .localText }
    }

    func remoteFileSignatures(selectedFolder: URL) throws -> [SyncDevice: SyncFileSignature] {
        let directory = Self.syncDirectory(in: selectedFolder)
        var result: [SyncDevice: SyncFileSignature] = [:]
        for peer in device.peers {
            if let signature = try fileSignature(at: directory.appendingPathComponent(peer.fileName)) {
                result[peer] = signature
            }
        }
        return result
    }

    func windowsFileSignature(selectedFolder: URL) throws -> SyncFileSignature? {
        let url = Self.syncDirectory(in: selectedFolder)
            .appendingPathComponent(Self.windowsFileName)
        return try fileSignature(at: url)
    }

    private func ensureDirectory(_ directory: URL) throws {
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else { throw SyncError.folderUnavailable }
            return
        }
        try SyncFileAccess.coordinate(at: directory, writing: true) { url in
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    private func readSnapshotIfPresent(
        at url: URL,
        expectedDevice: SyncDevice
    ) throws -> SyncSnapshot? {
        do {
            return try SyncFileAccess.coordinate(at: url, writing: false) { url in
                guard fileManager.fileExists(atPath: url.path) else { return nil }
                let data = try Data(contentsOf: url)
                return try SyncSnapshotCodec.decode(data, expectedDevice: expectedDevice)
            }
        } catch where SyncFileAccess.isMissing(error) {
            return nil
        }
    }

    private func atomicWrite(_ data: Data, to destination: URL) throws {
        try SyncFileAccess.coordinate(at: destination, writing: true) { url in
            try writeAtomically(data, to: url)
        }
    }

    private func writeAtomically(_ data: Data, to destination: URL) throws {
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
        do {
            return try SyncFileAccess.coordinate(at: url, writing: false) { url in
                guard fileManager.fileExists(atPath: url.path) else { return nil }
                let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                guard let modificationDate = values.contentModificationDate else { return nil }
                return SyncFileSignature(modificationDate: modificationDate, fileSize: Int64(values.fileSize ?? 0))
            }
        } catch where SyncFileAccess.isMissing(error) {
            return nil
        }
    }
}
