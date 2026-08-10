import Foundation
import SwiftSoup

struct GenericNovelAdapter: NovelSourceAdapter {
    func canHandle(_ document: LoadedHTML) -> Bool { true }

    func parseChapterPage(_ loaded: LoadedHTML) throws -> ParsedChapterPage {
        let document = try HTMLParsingSupport.document(from: loaded)
        guard let candidate = try bestContentCandidate(in: document) else {
            throw NovelParsingError.noReadableContent
        }
        let paragraphs = try HTMLParsingSupport.paragraphs(from: candidate)
            .filter { $0.count > 1 }
        guard paragraphs.joined().count >= 60 else { throw NovelParsingError.noReadableContent }

        let title = try chapterTitle(in: document)
        let metadata = metadata(in: document)
        let catalogURL = try navigationURL(
            in: document,
            labels: ["目录", "章节列表", "返回目录", "全部章节"],
            baseURL: loaded.finalURL
        )

        return ParsedChapterPage(
            title: title,
            bookTitle: metadata.bookTitle,
            author: metadata.author,
            paragraphs: paragraphs,
            catalogURL: catalogURL,
            previousChapterURL: try navigationURL(
                in: document,
                labels: ["上一章", "上一章节", "前一章"],
                rel: "prev",
                baseURL: loaded.finalURL
            ),
            nextChapterURL: try navigationURL(
                in: document,
                labels: ["下一章", "下一章节", "后一章"],
                rel: "next",
                baseURL: loaded.finalURL
            ),
            nextPageURL: try navigationURL(
                in: document,
                labels: ["下一页", "下页"],
                baseURL: loaded.finalURL
            )
        )
    }

    func parseCatalogPage(_ loaded: LoadedHTML) throws -> ParsedBookCatalog {
        let document = try HTMLParsingSupport.document(from: loaded)
        let metadata = metadata(in: document)
        let headingTitle = try document.select("h1").first()?.text()
        let title = metadata.bookTitle ?? headingTitle ?? "未命名小说"
        let seeds = try chapterSeeds(in: document, baseURL: loaded.finalURL)
        guard !seeds.isEmpty else { throw NovelParsingError.missingCatalog }

        return ParsedBookCatalog(
            title: title,
            author: metadata.author ?? "未知作者",
            chapters: seeds,
            nextPageURL: try navigationURL(
                in: document,
                labels: ["下一页", "下页"],
                baseURL: loaded.finalURL
            )
        )
    }

    private func bestContentCandidate(in document: Document) throws -> Element? {
        let candidates = try document.select(
            "article, main, [id*=content], [class*=content], [id*=chapter], [class*=chapter], [id*=read], [class*=read]"
        ).array()

        return try candidates.max { lhs, rhs in
            try score(lhs) < score(rhs)
        }.flatMap { candidate in
            guard (try? score(candidate)) ?? 0 > 100 else { return nil }
            return candidate
        }
    }

    private func score(_ element: Element) throws -> Int {
        let textLength = try element.text().count
        let linkLength = try element.select("a").text().count
        let paragraphs = try element.select("p, br").count
        return textLength - (linkLength * 2) + (paragraphs * 30)
    }

    private func chapterTitle(in document: Document) throws -> String {
        if let heading = try document.select("h1").first()?.text(), !heading.isEmpty {
            return heading
        }
        if let title = try document.title().components(separatedBy: CharacterSet(charactersIn: "_｜|-|")).first {
            return title.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return "未命名章节"
    }

    private func metadata(in document: Document) -> (bookTitle: String?, author: String?) {
        let pageTitle = (try? document.title()) ?? ""
        let ogTitle = try? document.select("meta[property=og:title]").first()?.attr("content")
        let author = (try? document.select("meta[name=author]").first()?.attr("content"))
            ?? jsonLDValue(named: "author", in: document)
            ?? visibleAuthor(in: document)
        let bookTitle = jsonLDValue(named: "isPartOf", in: document)
            ?? ogTitle.flatMap { value in
                let pieces = value.split(separator: "_")
                return pieces.count > 1 ? String(pieces[1]) : nil
            }
            ?? pageTitle.split(separator: "_").dropFirst().first.map(String.init)
        return (bookTitle?.trimmingCharacters(in: .whitespacesAndNewlines), author)
    }

    private func visibleAuthor(in document: Document) -> String? {
        let text = (try? document.text()) ?? ""
        return HTMLParsingSupport.firstCapture("作者\\s*[：:]\\s*([^\\s]+)", in: text)
    }

    private func chapterSeeds(in document: Document, baseURL: URL) throws -> [ChapterSeed] {
        let selectors = [
            "[id*=catalog]", "[class*=catalog]",
            "[id*=chapter]", "[class*=chapter]",
            "[id*=list]", "[class*=list]",
            "ul", "ol"
        ]
        let containers = try selectors.flatMap { try document.select($0).array() }
        let chapterURLs = try Set(
            containers
                .map { try chapterSeeds(in: $0, baseURL: baseURL) }
                .filter { $0.count >= 2 }
                .flatMap { $0.map { $0.url.absoluteString } }
        )
        if !chapterURLs.isEmpty {
            return try chapterSeeds(
                from: document.select("a").array(),
                baseURL: baseURL,
                restrictingTo: chapterURLs
            )
        }
        return try chapterSeeds(from: document.select("a").array(), baseURL: baseURL)
    }

    private func chapterSeeds(in container: Element, baseURL: URL) throws -> [ChapterSeed] {
        try chapterSeeds(from: container.select("a").array(), baseURL: baseURL)
    }

    private func chapterSeeds(
        from anchors: [Element],
        baseURL: URL,
        restrictingTo allowedURLs: Set<String>? = nil
    ) throws -> [ChapterSeed] {
        var seen = Set<String>()
        var seeds: [ChapterSeed] = []
        for anchor in anchors {
            let chapterTitle = try anchor.text().trimmingCharacters(in: .whitespacesAndNewlines)
            guard isLikelyChapterTitle(chapterTitle),
                  let url = HTMLParsingSupport.absoluteURL(for: anchor, relativeTo: baseURL),
                  HTMLParsingSupport.isSameOrigin(url, as: baseURL),
                  allowedURLs?.contains(url.absoluteString) ?? true,
                  seen.insert(url.absoluteString).inserted else {
                continue
            }
            seeds.append(ChapterSeed(title: chapterTitle, url: url, sortIndex: seeds.count + 1))
        }
        return seeds
    }

    private func isLikelyChapterTitle(_ title: String) -> Bool {
        if title.range(of: "第.+[章回节]", options: .regularExpression) != nil {
            return true
        }
        return ["序章", "楔子", "引子", "尾声", "后记", "番外"].contains { title.contains($0) }
    }

    private func jsonLDValue(named key: String, in document: Document) -> String? {
        guard let scripts = try? document.select("script[type=application/ld+json]").array() else { return nil }
        for script in scripts {
            guard let json = try? script.html(),
                  let data = json.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data),
                  let value = recursiveValue(for: key, in: object) else {
                continue
            }
            return value
        }
        return nil
    }

    private func recursiveValue(for key: String, in object: Any) -> String? {
        if let dictionary = object as? [String: Any] {
            if let string = dictionary[key] as? String { return string }
            if let nested = dictionary[key] as? [String: Any], let name = nested["name"] as? String { return name }
            for value in dictionary.values {
                if let result = recursiveValue(for: key, in: value) { return result }
            }
        } else if let array = object as? [Any] {
            for value in array {
                if let result = recursiveValue(for: key, in: value) { return result }
            }
        }
        return nil
    }

    private func navigationURL(
        in document: Document,
        labels: Set<String>,
        rel: String? = nil,
        baseURL: URL
    ) throws -> URL? {
        if let rel,
           let anchor = try document.select("a[rel=\(rel)]").first(),
           let url = HTMLParsingSupport.absoluteURL(for: anchor, relativeTo: baseURL) {
            return url
        }
        return try HTMLParsingSupport.link(in: document, matching: labels, baseURL: baseURL)
    }
}
