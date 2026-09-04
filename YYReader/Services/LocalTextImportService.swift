import CoreFoundation
import CryptoKit
import Foundation

actor LocalTextImportService {
    func prepareImport(from url: URL) throws -> LocalTextImportDraft {
        try Task.checkCancellation()
        guard url.pathExtension.lowercased() == "txt" else {
            throw LocalTextImportError.invalidFileType
        }
        let scopedAccess = url.startAccessingSecurityScopedResource()
        defer {
            if scopedAccess { url.stopAccessingSecurityScopedResource() }
        }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        try Task.checkCancellation()
        return try Self.prepareImport(data: data, fileName: url.deletingPathExtension().lastPathComponent)
    }

    static func prepareImport(data: Data, fileName: String) throws -> LocalTextImportDraft {
        guard !data.isEmpty else { throw LocalTextImportError.emptyFile }
        let decoded = try decode(data)
        let text = clean(decoded.text)
        guard text.contains(where: { !$0.isWhitespace }) else {
            throw LocalTextImportError.noReadableContent
        }

        let digestInput = Data("yyreader-txt-v1\0\(data.count)\0".utf8) + data
        let stableID = SHA256.hash(data: digestInput).map { String(format: "%02x", $0) }.joined()
        let sourceBookURL = "yyreader-local://txt/\(stableID)"
        let pieces = split(text)
        let chapters = pieces.enumerated().map { offset, piece in
            let index = offset + 1
            let sourceURL = chapterURL(bookURL: sourceBookURL, index: index)
            return LocalTextChapterDraft(
                title: piece.title,
                bodyText: piece.body,
                sortIndex: index,
                sourceURL: sourceURL,
                previousURL: index > 1 ? chapterURL(bookURL: sourceBookURL, index: index - 1) : nil,
                nextURL: index < pieces.count ? chapterURL(bookURL: sourceBookURL, index: index + 1) : nil
            )
        }

        return LocalTextImportDraft(
            sourceBookURL: sourceBookURL,
            suggestedTitle: fileName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "本地小说",
            detectedEncoding: decoded.encoding,
            byteCount: data.count,
            chapters: chapters
        )
    }

    private static func decode(_ data: Data) throws -> (text: String, encoding: String) {
        if data.starts(with: [0xEF, 0xBB, 0xBF]),
           let value = String(data: data.dropFirst(3), encoding: .utf8) {
            return (value, "UTF-8 BOM")
        }
        if let value = String(data: data, encoding: .utf8) {
            return (value, "UTF-8")
        }
        let rawEncoding = CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        )
        if let value = String(data: data, encoding: String.Encoding(rawValue: rawEncoding)) {
            return (value, "GB18030 / GBK")
        }
        throw LocalTextImportError.unsupportedEncoding
    }

    private static func clean(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}").union(.whitespacesAndNewlines))
            .replacingOccurrences(
                of: "\n[ \\t\\u3000]*\n(?:[ \\t\\u3000]*\n)+",
                with: "\n\n",
                options: .regularExpression
            )
    }

    private static func split(_ text: String) -> [(title: String, body: String)] {
        let lines = text.components(separatedBy: "\n")
        let candidates = lines.enumerated().compactMap { index, line -> (Int, String)? in
            let title = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return isChapterTitle(title) ? (index, title) : nil
        }
        let nonEmptyLineIndices = lines.indices.filter { !lines[$0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let reliable: Bool
        if candidates.count >= 2 {
            reliable = true
        } else if let candidate = candidates.first {
            let nonEmptyPosition = nonEmptyLineIndices.firstIndex(of: candidate.0) ?? .max
            let following = Array(lines.dropFirst(candidate.0 + 1))
            reliable = nonEmptyPosition < 20 && isSubstantive(following)
        } else {
            reliable = false
        }

        guard reliable, let first = candidates.first else {
            return [("正文", text)]
        }

        var result: [(String, String)] = []
        let prefix = Array(lines[..<first.0])
        var shortPrefix: [String] = []
        if isSubstantive(prefix) {
            result.append(("前言", prefix.joined(separator: "\n")))
        } else {
            shortPrefix = prefix
        }

        for (offset, candidate) in candidates.enumerated() {
            let end = offset + 1 < candidates.count ? candidates[offset + 1].0 : lines.count
            var bodyLines = Array(lines[(candidate.0 + 1)..<end])
            if offset == 0, !shortPrefix.isEmpty {
                bodyLines.insert(contentsOf: shortPrefix + [""], at: 0)
            }
            let body = bodyLines.joined(separator: "\n")
            if body.contains(where: { !$0.isWhitespace }) {
                result.append((candidate.1, body))
            }
        }
        return result.isEmpty ? [("正文", text)] : result
    }

    private static func isSubstantive(_ lines: [String]) -> Bool {
        let nonEmpty = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let characterCount = nonEmpty.joined().filter { !$0.isWhitespace }.count
        return nonEmpty.count >= 2 || characterCount >= 200
    }

    private static func isChapterTitle(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 60,
              value.range(of: "[。！？!?；;]$", options: .regularExpression) == nil else {
            return false
        }
        let number = "[0-9０-９〇零一二三四五六七八九十百千万两]+"
        let suffix = "(?:[ \\t\\u3000:：·、\\-—]+.{1,42})?"
        let patterns = [
            "^第[ \\t\\u3000]*\(number)[ \\t\\u3000]*(?:章|回|节|卷)\(suffix)$",
            "^(?:序章|序言|楔子|引子|尾声|后记|番外(?:[ \\t\\u3000]*\(number))?)\(suffix)$",
            "^卷[ \\t\\u3000]*\(number)\(suffix)$"
        ]
        return patterns.contains { value.range(of: $0, options: .regularExpression) != nil }
    }

    private static func chapterURL(bookURL: String, index: Int) -> String {
        "\(bookURL)/chapter/\(String(format: "%06d", index))"
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
