import Foundation

enum SyncSnapshotCodec {
    static func encode(_ snapshot: SyncSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(ISO8601DateFormatter.syncString(from: date))
        }
        return try encoder.encode(snapshot)
    }

    static func decode(_ data: Data, expectedDevice: SyncDevice? = nil) throws -> SyncSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            guard let date = ISO8601DateFormatter.syncDate(from: value) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid ISO 8601 date: \(value)"
                )
            }
            return date
        }

        let snapshot: SyncSnapshot
        do {
            snapshot = try decoder.decode(SyncSnapshot.self, from: data)
        } catch {
            throw SyncError.malformedSnapshot(error.localizedDescription)
        }
        guard snapshot.format == SyncSnapshot.currentFormat else {
            throw SyncError.invalidFormat(snapshot.format)
        }
        guard snapshot.version == SyncSnapshot.currentVersion else {
            throw SyncError.unsupportedVersion(snapshot.version)
        }
        if let expectedDevice, snapshot.device != expectedDevice {
            throw SyncError.unexpectedDevice(expected: expectedDevice, actual: snapshot.device)
        }
        try snapshot.books.forEach(validate)
        return snapshot
    }

    private static func validate(_ book: SyncBookRecord) throws {
        guard URLCanonicalizer.isValidBookSource(book.sourceURL) else {
            throw SyncError.invalidBook("sourceURL 必须是 HTTP、HTTPS 或 yyreader-book URL。")
        }
        if let chapterURL = book.currentChapterURL,
           !URLCanonicalizer.isValidChapterSource(chapterURL) {
            throw SyncError.invalidBook("currentChapterURL 必须是 HTTP 或 HTTPS URL。")
        }
        if let paragraphIndex = book.paragraphIndex, paragraphIndex < 0 {
            throw SyncError.invalidBook("paragraphIndex 不能为负数。")
        }
        if let progress = book.progress,
           !progress.isFinite || !(0...1).contains(progress) {
            throw SyncError.invalidBook("progress 必须位于 0 到 1 之间。")
        }
    }
}

private extension ISO8601DateFormatter {
    static func syncFormatter(includesFractionalSeconds: Bool) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = includesFractionalSeconds
            ? [.withInternetDateTime, .withFractionalSeconds]
            : [.withInternetDateTime]
        return formatter
    }

    static func syncString(from date: Date) -> String {
        syncFormatter(includesFractionalSeconds: true).string(from: date)
    }

    static func syncDate(from value: String) -> Date? {
        syncFormatter(includesFractionalSeconds: true).date(from: value)
            ?? syncFormatter(includesFractionalSeconds: false).date(from: value)
    }
}
