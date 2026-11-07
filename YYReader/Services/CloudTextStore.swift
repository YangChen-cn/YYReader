import Foundation

actor CloudTextStore {
    static let maximumBytes = 64 * 1024 * 1024

    static func fileURL(sourceURL: String, selectedFolder: URL) throws -> URL {
        let prefix = "yyreader-local://txt/"
        guard sourceURL.hasPrefix(prefix) else { throw SyncError.invalidBook("不是本地 TXT") }
        let digest = String(sourceURL.dropFirst(prefix.count))
        guard digest.count == 64, digest.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw SyncError.invalidBook("TXT 文件标识无效")
        }
        return SyncEngine.syncDirectory(in: selectedFolder)
            .appendingPathComponent("texts", isDirectory: true)
            .appendingPathComponent(digest + ".json")
    }

    func upload(_ archive: CloudTextArchive, selectedFolder: URL) throws {
        try validate(archive, sourceURL: archive.draft.sourceBookURL)
        let url = try Self.fileURL(sourceURL: archive.draft.sourceBookURL, selectedFolder: selectedFolder)
        let data = try JSONEncoder().encode(archive)
        guard data.count <= Self.maximumBytes else { throw SyncError.invalidBook("正文超过 64 MB") }
        try Task.checkCancellation()
        try SyncFileAccess.coordinate(at: url.deletingLastPathComponent(), writing: true) { directory in
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try SyncFileAccess.coordinate(at: url, writing: true) { destination in
            try data.write(to: destination, options: .atomic)
        }
    }

    func download(sourceURL: String, selectedFolder: URL) throws -> CloudTextArchive? {
        let url = try Self.fileURL(sourceURL: sourceURL, selectedFolder: selectedFolder)
        do {
            return try SyncFileAccess.coordinate(at: url, writing: false) { coordinated in
                guard FileManager.default.fileExists(atPath: coordinated.path) else { return nil }
                let size = try coordinated.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= Self.maximumBytes else { throw SyncError.invalidBook("正文超过 64 MB") }
                let data = try Data(contentsOf: coordinated)
                guard data.count <= Self.maximumBytes else { throw SyncError.invalidBook("正文超过 64 MB") }
                let archive = try JSONDecoder().decode(CloudTextArchive.self, from: data)
                try validate(archive, sourceURL: sourceURL)
                return archive
            }
        } catch where SyncFileAccess.isMissing(error) {
            return nil
        }
    }

    private func validate(_ archive: CloudTextArchive, sourceURL: String) throws {
        guard archive.version == 1, archive.draft.sourceBookURL == sourceURL,
              !archive.draft.chapters.isEmpty, archive.draft.chapters.count <= 100_000 else {
            throw SyncError.invalidBook("正文文件版本或身份不匹配")
        }
        var bytes = 0
        for (offset, chapter) in archive.draft.chapters.enumerated() {
            try Task.checkCancellation()
            let index = offset + 1
            let expected = sourceURL + "/chapter/" + String(format: "%06d", index)
            bytes += chapter.bodyText.utf8.count
            guard chapter.sourceURL == expected, chapter.sortIndex == index,
                  !chapter.bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  bytes <= Self.maximumBytes else {
                throw SyncError.invalidBook("正文文件章节无效或过大")
            }
        }
    }
}
