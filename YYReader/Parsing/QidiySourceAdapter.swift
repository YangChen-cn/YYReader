import Foundation
import SwiftSoup

struct QidiySourceAdapter: NovelSourceAdapter {
    func canHandle(_ document: LoadedHTML) -> Bool {
        let host = document.finalURL.host?.lowercased() ?? ""
        return host == "qidiy.com" || host.hasSuffix(".qidiy.com")
    }

    func parseChapterPage(_ loaded: LoadedHTML) throws -> ParsedChapterPage {
        let document = try HTMLParsingSupport.document(from: loaded)
        guard let content = try document.select("#content").first(),
              let heading = try document.select("h1.title").first() else {
            throw NovelParsingError.noReadableContent
        }

        let rawTitle = try heading.text().trimmingCharacters(in: .whitespacesAndNewlines)
        let title = HTMLParsingSupport.replacingRegex(
            "\\s*[（(]第\\d+/\\d+页[）)]\\s*$",
            in: rawTitle,
            with: ""
        )
        let rawParagraphs = try HTMLParsingSupport.paragraphs(from: content)
        let paragraphs = cleanChapterParagraphs(rawParagraphs, title: title)
        guard !paragraphs.isEmpty else { throw NovelParsingError.noReadableContent }

        let catalogURL = try HTMLParsingSupport.link(
            in: document,
            matching: ["章节列表", "目录"],
            baseURL: loaded.finalURL
        )
        let previous = try HTMLParsingSupport.link(
            in: document,
            matching: ["上一章"],
            baseURL: loaded.finalURL
        )
        let next = try HTMLParsingSupport.link(
            in: document,
            matching: ["下一章"],
            baseURL: loaded.finalURL
        )
        let nextPage = try HTMLParsingSupport.link(
            in: document,
            matching: ["下一页"],
            baseURL: loaded.finalURL
        )

        let bookLink = try document.select("a").array().first { anchor in
            guard let url = HTMLParsingSupport.absoluteURL(for: anchor, relativeTo: loaded.finalURL) else {
                return false
            }
            let text = (try? anchor.text()) ?? ""
            return url.path.range(of: "^/book/\\d+/?$", options: .regularExpression) != nil
                && !["上一章", "下一章", "章节列表", "开始阅读"].contains(text)
        }
        let bookTitle = try bookLink?.text().trimmingCharacters(in: .whitespacesAndNewlines)

        return ParsedChapterPage(
            title: title,
            bookTitle: bookTitle?.isEmpty == false ? bookTitle : nil,
            author: nil,
            paragraphs: paragraphs,
            catalogURL: catalogURL,
            previousChapterURL: previous == catalogURL ? nil : previous,
            nextChapterURL: next,
            nextPageURL: nextPage
        )
    }

    func parseCatalogPage(_ loaded: LoadedHTML) throws -> ParsedBookCatalog {
        let document = try HTMLParsingSupport.document(from: loaded)
        let headings = try document.select("h1").array()
        let title = try headings.first { try $0.className() != "logo" }?.text()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let title, !title.isEmpty else { throw NovelParsingError.missingCatalog }

        let author = try document.select("p").array()
            .compactMap { try? $0.text() }
            .first { $0.range(of: "^作者[：:]", options: .regularExpression) != nil }
            .map { HTMLParsingSupport.replacingRegex("^作者[：:]\\s*", in: $0, with: "") }
            ?? "未知作者"

        let catalogSections = try document.select("ul.section-list").array()
            .map { try chapterSeeds(in: $0, baseURL: loaded.finalURL) }
            .filter { !$0.isEmpty }
        let chapters = catalogSections.max(by: isLessLikelyCatalogSection) ?? []

        let nextPage = try HTMLParsingSupport.link(
            in: document,
            matching: ["下一页"],
            baseURL: loaded.finalURL
        )

        return ParsedBookCatalog(
            title: title,
            author: author,
            chapters: chapters,
            nextPageURL: nextPage
        )
    }

    private func chapterSeeds(in section: Element, baseURL: URL) throws -> [ChapterSeed] {
        var seen = Set<String>()
        var chapters: [ChapterSeed] = []
        for anchor in try section.select("a").array() {
            let chapterTitle = try anchor.text().trimmingCharacters(in: .whitespacesAndNewlines)
            guard chapterTitle.range(of: "第.+[章回节]", options: .regularExpression) != nil,
                  let url = HTMLParsingSupport.absoluteURL(for: anchor, relativeTo: baseURL),
                  seen.insert(url.absoluteString).inserted else {
                continue
            }
            // Volumes such as extras can restart their displayed chapter number at 1.
            // The catalog's DOM order is the only unambiguous order within a page.
            let index = chapters.count + 1
            chapters.append(ChapterSeed(title: chapterTitle, url: url, sortIndex: index))
        }
        return chapters
    }

    private func isLessLikelyCatalogSection(_ lhs: [ChapterSeed], _ rhs: [ChapterSeed]) -> Bool {
        if lhs.count != rhs.count { return lhs.count < rhs.count }
        let lhsFirst = lhs.compactMap { HTMLParsingSupport.chapterNumber(in: $0.title) }.min() ?? .max
        let rhsFirst = rhs.compactMap { HTMLParsingSupport.chapterNumber(in: $0.title) }.min() ?? .max
        return lhsFirst > rhsFirst
    }

    private func cleanChapterParagraphs(_ paragraphs: [String], title: String) -> [String] {
        let pageMarker = NSRegularExpression.escapedPattern(for: title) + "\\s*\\(第\\d+/\\d+页\\)\\s*"
        return paragraphs.compactMap { paragraph in
            var value = paragraph
            value = HTMLParsingSupport.replacingRegex("read\\d+\\(\\);?", in: value, with: "")
            value = HTMLParsingSupport.replacingRegex(pageMarker, in: value, with: "")
            value = HTMLParsingSupport.replacingRegex("[（(]本章未完[^）)]*[）)]", in: value, with: "")
            value = HTMLParsingSupport.normalize(value)
            if value.isEmpty || value.contains("加入书签，方便阅读") { return nil }
            return value
        }
    }
}
