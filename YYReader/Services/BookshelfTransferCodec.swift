import Foundation

enum BookshelfTransferCodec {
    static let currentFormat = "yyreader-bookshelf"
    static let currentVersion = 1

    static func encode(_ document: BookshelfTransferDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(ISO8601DateFormatter.bookshelfTransferString(from: date))
        }
        return try encoder.encode(document)
    }

    static func decode(_ data: Data) throws -> BookshelfTransferDocument {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            guard let date = ISO8601DateFormatter.bookshelfTransferDate(from: value) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "exportedAt 不是有效的日期时间。"
                )
            }
            return date
        }

        let document: BookshelfTransferDocument
        do {
            document = try decoder.decode(BookshelfTransferDocument.self, from: data)
        } catch {
            throw BookshelfTransferError.malformedJSON(error.localizedDescription)
        }
        guard document.format == currentFormat else {
            throw BookshelfTransferError.invalidDocument("不是 YYReader bookshelf-transfer 文件。")
        }
        guard document.version == currentVersion else {
            throw BookshelfTransferError.unsupportedVersion(document.version)
        }
        return document
    }

    static func validationError(for book: BookshelfTransferBook) -> String? {
        guard URLCanonicalizer.isValidBookSource(book.sourceURL) else {
            return "sourceURL 必须是 HTTP、HTTPS 或 YYReader 无目录书籍身份 URL。"
        }
        if let paragraphIndex = book.paragraphIndex, paragraphIndex < 0 {
            return "paragraphIndex 不能为负数。"
        }
        if let progress = book.progress,
           !progress.isFinite || !(0...1).contains(progress) {
            return "progress 必须位于 0 到 1 之间。"
        }
        if let chapterURL = book.currentChapterURL,
           !URLCanonicalizer.isValidChapterSource(chapterURL) {
            return "currentChapterURL 必须是 HTTP 或 HTTPS URL。"
        }
        return nil
    }
}

private extension ISO8601DateFormatter {
    static func bookshelfTransferFormatter(includesFractionalSeconds: Bool) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = includesFractionalSeconds
            ? [.withInternetDateTime, .withFractionalSeconds]
            : [.withInternetDateTime]
        return formatter
    }

    static func bookshelfTransferString(from date: Date) -> String {
        bookshelfTransferFormatter(includesFractionalSeconds: true).string(from: date)
    }

    static func bookshelfTransferDate(from value: String) -> Date? {
        bookshelfTransferFormatter(includesFractionalSeconds: true).date(from: value)
            ?? bookshelfTransferFormatter(includesFractionalSeconds: false).date(from: value)
    }
}
