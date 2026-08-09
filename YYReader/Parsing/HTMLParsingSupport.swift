import Foundation
import SwiftSoup

enum HTMLParsingSupport {
    static func document(from loaded: LoadedHTML) throws -> Document {
        try SwiftSoup.parse(loaded.html, loaded.finalURL.absoluteString)
    }

    static func absoluteURL(for element: Element, relativeTo baseURL: URL) -> URL? {
        guard let href = try? element.attr("href"),
              !href.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !href.lowercased().hasPrefix("javascript:") else {
            return nil
        }
        if let absolute = try? element.attr("abs:href"), !absolute.isEmpty,
           let url = URL(string: absolute) {
            return url
        }
        return URL(string: href, relativeTo: baseURL)?.absoluteURL
    }

    static func link(
        in document: Document,
        matching labels: Set<String>,
        baseURL: URL
    ) throws -> URL? {
        for anchor in try document.select("a").array() {
            let label = try anchor.text().trimmingCharacters(in: .whitespacesAndNewlines)
            if labels.contains(label), let url = absoluteURL(for: anchor, relativeTo: baseURL) {
                return url
            }
        }
        return nil
    }

    static func paragraphs(from element: Element) throws -> [String] {
        try element.select("script, style, noscript, iframe, form, .ad, .ads, .advertisement").remove()
        var source = try element.html()
        source = replacingRegex("(?i)<br\\s*/?>", in: source, with: "\n")
        source = replacingRegex("(?i)</(?:p|div|li|section|article|h[1-6])>", in: source, with: "\n")
        source = replacingRegex("(?i)<(?:p|div|li|section|article|h[1-6])[^>]*>", in: source, with: "")

        return source
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { fragment -> String? in
                let text = (try? SwiftSoup.parseBodyFragment(String(fragment)).text()) ?? ""
                let cleaned = normalize(text)
                return cleaned.isEmpty ? nil : cleaned
            }
    }

    static func normalize(_ text: String) -> String {
        text
            .replacing("\u{00a0}", with: " ")
            .replacing("\u{3000}", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func replacingRegex(_ pattern: String, in value: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return value }
        let range = NSRange(value.startIndex..., in: value)
        return regex.stringByReplacingMatches(in: value, range: range, withTemplate: replacement)
    }

    static func firstCapture(_ pattern: String, in value: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: value) else {
            return nil
        }
        return String(value[range])
    }

    static func chapterNumber(in title: String) -> Int? {
        guard let value = firstCapture("第\\s*(\\d+)\\s*[章回节]", in: title) else { return nil }
        return Int(value)
    }

    static func isSameOrigin(_ candidate: URL, as origin: URL) -> Bool {
        candidate.scheme?.lowercased() == origin.scheme?.lowercased()
            && candidate.host?.lowercased() == origin.host?.lowercased()
            && candidate.port == origin.port
    }
}
