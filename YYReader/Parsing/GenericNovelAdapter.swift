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
            .compactMap(cleanedParagraph)
        guard paragraphs.joined().count >= 60 else { throw NovelParsingError.noReadableContent }

        let title = try chapterTitle(in: document)
        let metadata = metadata(in: document)
        let catalogURL = try navigationURL(
            in: document,
            labels: ["目录", "章节列表", "返回目录", "全部章节"],
            fallbackSelectors: [
                "a#index_url",
                "a#bookname",
                "a[href*='/novel/chapters/']",
                ".bcrumb a[rel='category tag']"
            ],
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
                fallbackSelectors: [".prev_page a"],
                baseURL: loaded.finalURL
            ),
            nextChapterURL: try navigationURL(
                in: document,
                labels: ["下一章", "下一章节", "后一章"],
                rel: "next",
                fallbackSelectors: [".next_page_links a"],
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
        let headingTitle = try catalogHeading(in: document)
        let title = metadata.bookTitle ?? headingTitle ?? "未命名小说"
        let seeds = try chapterSeeds(in: document, baseURL: loaded.finalURL)
        guard !seeds.isEmpty else { throw NovelParsingError.missingCatalog }

        return ParsedBookCatalog(
            title: title,
            author: metadata.author ?? "未知作者",
            chapters: seeds,
            nextPageURL: try navigationURL(
                in: document,
                labels: ["下一页", "下页", "全部章节", "完整目录", "查看全部章节"],
                baseURL: loaded.finalURL
            )
        )
    }

    private func bestContentCandidate(in document: Document) throws -> Element? {
        let dedicated = try document.select(
            "[itemprop=articleBody], #content, #chaptercontent, #chapter-content, "
                + "#nr1, .chapter-content, .read-content, .post-content, .entry-content, .content"
        ).array()
        if let candidate = try dedicated.max(by: { try score($0) < score($1) }),
           try score(candidate) >= 60 {
            return candidate
        }

        // Long catalog pages often have an outer id/class containing "read" or
        // "content". Without a dedicated body container they are not chapters.
        if try likelyChapterAnchorCount(in: document) >= 8 {
            return nil
        }

        let semantic = try document.select("article, main").array()
        if let candidate = try semantic.max(by: { try score($0) < score($1) }),
           try score(candidate) >= 60 {
            return candidate
        }

        let candidates = try document.select(
            "article, main, [id*=content], [class*=content], [id*=chapter], [class*=chapter], [id*=read], [class*=read]"
        ).array()
        let hasChapterNavigation = try hasChapterNavigation(in: document)
        let hasChapterTitle = isLikelyChapterTitle(try chapterTitle(in: document))

        return try candidates.max { lhs, rhs in
            try score(lhs) < score(rhs)
        }.flatMap { candidate in
            let candidateScore = (try? score(candidate)) ?? 0
            guard candidateScore > 100
                || (candidateScore >= 60 && hasChapterTitle && hasChapterNavigation) else {
                return nil
            }
            return candidate
        }
    }

    private func hasChapterNavigation(in document: Document) throws -> Bool {
        let labels = Set(["上一章", "上一章节", "前一章", "下一章", "下一章节", "后一章"])
        return try document.select("a").array().contains { anchor in
            labels.contains(try anchor.text().trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private func likelyChapterAnchorCount(in document: Document) throws -> Int {
        try document.select("a").array().reduce(into: 0) { count, anchor in
            if isLikelyChapterTitle(try chapterTitle(from: anchor)) {
                count += 1
            }
        }
    }

    private func score(_ element: Element) throws -> Int {
        let textLength = try element.text().count
        let linkLength = try element.select("a").text().count
        let paragraphs = try element.select("p, br").count
        return textLength - (linkLength * 2) + (paragraphs * 30)
    }

    private func chapterTitle(in document: Document) throws -> String {
        let selectors = [
            "[itemprop=headline]", "h1.title", "#nr_title", ".post-title",
            ".reader-main > h1", ".kfyd > h2", ".title > h1", "article h1"
        ]
        for selector in selectors {
            if let heading = try document.select(selector).first()?.text(), !heading.isEmpty {
                return cleanedChapterTitle(heading)
            }
        }
        for heading in try document.select("h1, h2").array() {
            let text = try heading.text().trimmingCharacters(in: .whitespacesAndNewlines)
            if isLikelyChapterTitle(text) {
                return cleanedChapterTitle(text)
            }
        }
        let pageTitle = try document.title()
        if let title = pageTitle.components(separatedBy: CharacterSet(charactersIn: "_｜|-|")).first {
            return cleanedChapterTitle(title)
        }
        return "未命名章节"
    }

    private func metadata(in document: Document) -> (bookTitle: String?, author: String?) {
        let pageTitle = (try? document.title()) ?? ""
        let ogTitle = metaContent(named: "og:title", in: document)
        let author = metaContent(named: "author", in: document)
            ?? metaContent(named: "og:novel:author", in: document)
            ?? jsonLDValue(named: "author", in: document)
            ?? visibleAuthor(in: document)
        let bookTitle = metaContent(named: "og:novel:book_name", in: document)
            ?? jsonLDValue(named: "isPartOf", in: document)
            ?? visibleBookTitle(in: document)
            ?? bookTitleFromDecoratedTitle(ogTitle)
            ?? bookTitleFromDecoratedTitle(pageTitle)
        return (normalizedMetadata(bookTitle), normalizedMetadata(author))
    }

    private func visibleAuthor(in document: Document) -> String? {
        let text = (try? document.text()) ?? ""
        let description = metaContent(named: "description", in: document) ?? ""
        return firstNonempty([
            try? document.select("#author").first()?.text(),
            linkedAuthor(in: document),
            scopedAuthor(in: document),
            HTMLParsingSupport.firstCapture("由作者\\s*([^，,。\\s]+)\\s*创作", in: description),
            HTMLParsingSupport.firstCapture("提供(?:了)?([^，,。\\s]+)创作", in: description),
            HTMLParsingSupport.firstCapture("作者\\s*([^，,。\\s]+)", in: description),
            HTMLParsingSupport.firstCapture("lastread\\.set\\([^;]+,'([^']+)'\\s*,\\s*'[^']*'\\s*\\)", in: (try? document.html()) ?? ""),
            HTMLParsingSupport.firstCapture("作者\\s*[：:]\\s*([^\\s|，,。]{1,16})(?:\\s|[|，,。])", in: text)
        ])
    }

    private func linkedAuthor(in document: Document) -> String? {
        guard let anchors = try? document.select("a[href*='/author/'], a[href*='/zuojia/']").array() else {
            return nil
        }
        for anchor in anchors {
            guard let text = try? anchor.text() else { continue }
            let normalized = HTMLParsingSupport.normalize(text)
            if !normalized.isEmpty, normalized != "作者", normalized != "作家目录" {
                return normalized
            }
        }
        return nil
    }

    private func scopedAuthor(in document: Document) -> String? {
        guard let elements = try? document.select(
            ".book-describe p, .bookname, .info p, .border_b, [class*=book-info]"
        ).array() else {
            return nil
        }
        for element in elements {
            guard let text = try? element.text(),
                  let author = HTMLParsingSupport.firstCapture("作者\\s*[：:]\\s*([^|，,。]+)", in: text) else {
                continue
            }
            let normalized = HTMLParsingSupport.normalize(author)
            if !normalized.isEmpty { return normalized }
        }
        return nil
    }

    private func visibleBookTitle(in document: Document) -> String? {
        let selectors = [
            "#bookname", ".book-describe h1", ".bookname h1",
            ".info .top h1", ".novel_info h1"
        ]
        for selector in selectors {
            guard let element = try? document.select(selector).first() else { continue }
            let ownText = element.ownText()
            if !ownText.isEmpty { return ownText }
            if let text = try? element.text(), !text.isEmpty { return text }
        }
        if let breadcrumb = try? document.select(
            ".breadcrumb a[href*='/book/'], .breadcrumb a[href*='/read/'], "
                + ".breadcrumb a[href*='/novel/chapters/'], .bcrumb a[rel='category tag']"
        ).last() {
            return try? breadcrumb.text()
        }
        return nil
    }

    private func catalogHeading(in document: Document) throws -> String? {
        if let title = visibleBookTitle(in: document) { return title }
        return try document.select("h1:not(#logo) > a, h1:not(#logo)").array()
            .compactMap { element in
                let ownText = element.ownText()
                return ownText.isEmpty ? try? element.text() : ownText
            }
            .first { !$0.isEmpty }
    }

    private func metaContent(named name: String, in document: Document) -> String? {
        guard let element = try? document.select("meta[name='\(name)'], meta[property='\(name)']").first(),
              let content = try? element.attr("content"),
              !content.isEmpty else {
            return nil
        }
        return content
    }

    private func bookTitleFromDecoratedTitle(_ value: String?) -> String? {
        guard let value else { return nil }
        if let quoted = HTMLParsingSupport.firstCapture("《([^》]+)》", in: value) {
            return quoted
        }
        if let prefix = HTMLParsingSupport.firstCapture("^(.+?)\\s+第\\s*\\d+\\s*[章回节]", in: value) {
            return prefix
        }
        let pieces = value.split(separator: "_")
        return pieces.count > 1 ? String(pieces[1]) : nil
    }

    private func normalizedMetadata(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = HTMLParsingSupport.normalize(value)
            .trimmingCharacters(in: CharacterSet(charactersIn: "《》"))
        return normalized.isEmpty ? nil : normalized
    }

    private func firstNonempty(_ values: [String?]) -> String? {
        values.compactMap(normalizedMetadata).first
    }

    private func cleanedChapterTitle(_ title: String) -> String {
        let normalized = HTMLParsingSupport.normalize(title)
        return HTMLParsingSupport.replacingRegex(
            "\\s*[（(]第\\s*\\d+\\s*页\\s*/\\s*共\\s*\\d+\\s*页[）)]\\s*$",
            in: normalized,
            with: ""
        )
    }

    private func cleanedParagraph(_ paragraph: String) -> String? {
        var text = HTMLParsingSupport.normalize(paragraph)
        guard text.count > 1 else { return nil }
        if isChapterNavigationParagraph(text) || isReaderModeNotice(text) { return nil }
        let noise = [
            "本站最新网址", "您阅读的小说来自", "小主，这个章节后面还有",
            "加入书签，方便阅读", "点击下一页继续阅读"
        ]
        if noise.contains(where: text.contains) { return nil }
        if text.count < 80, text.contains("落`霞"), text.contains("读`书") { return nil }
        if text.count > 20, text.hasSuffix("落霞") {
            text.removeLast(2)
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }

    private func isChapterNavigationParagraph(_ text: String) -> Bool {
        let compact = text.filter { !$0.isWhitespace }
        if compact.range(
            of: "^(?:上一章|下一章|上一章节|下一章节|前一章|后一章)[：:].+$",
            options: .regularExpression
        ) != nil {
            return true
        }

        let labels = [
            "上一章节", "下一章节", "返回目录", "章节目录", "全部章节",
            "上一章", "下一章", "前一章", "后一章",
            "上一页", "下一页", "上页", "下页", "目录", "书页", "首页"
        ]
        var remainder = text
        for label in labels {
            remainder = remainder.replacing(label, with: "")
        }
        guard remainder.count < text.count else { return false }
        return remainder.unicodeScalars.allSatisfy {
            CharacterSet.whitespacesAndNewlines.contains($0)
                || CharacterSet.punctuationCharacters.contains($0)
                || CharacterSet.symbols.contains($0)
        }
    }

    private func isReaderModeNotice(_ text: String) -> Bool {
        let compact = text
            .replacing("/", with: "")
            .replacing("\\", with: "")
            .filter { !$0.isWhitespace }
        return compact.contains("浏览器")
            && compact.contains("阅读模式")
            && compact.contains("退出")
            && compact.contains("转码阅读")
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
            let chapterTitle = try chapterTitle(from: anchor)
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

    private func chapterTitle(from anchor: Element) throws -> String {
        if let heading = try anchor.select("h1, h2, h3, h4, h5, h6").first() {
            let text = try heading.text().trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { return text }
        }
        return try anchor.text().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isLikelyChapterTitle(_ title: String) -> Bool {
        if title.range(of: "第.+[章回节]", options: .regularExpression) != nil {
            return true
        }
        return ["序章", "序言", "楔子", "引子", "尾声", "后记", "番外"].contains { title.contains($0) }
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
        fallbackSelectors: [String] = [],
        baseURL: URL
    ) throws -> URL? {
        if let rel,
           let anchor = try document.select("a[rel=\(rel)]").first(),
           let url = HTMLParsingSupport.absoluteURL(for: anchor, relativeTo: baseURL) {
            return url
        }
        if let exact = try HTMLParsingSupport.link(in: document, matching: labels, baseURL: baseURL) {
            return exact
        }
        for anchor in try document.select("a").array() {
            let label = try anchor.text().trimmingCharacters(in: .whitespacesAndNewlines)
            let compactLabel = label.filter { !$0.isWhitespace }
            if labels.contains(where: { compactLabel.hasPrefix($0.filter { !$0.isWhitespace }) }),
               let url = HTMLParsingSupport.absoluteURL(for: anchor, relativeTo: baseURL) {
                return url
            }
        }
        for selector in fallbackSelectors {
            if let anchor = try document.select(selector).first(),
               let url = HTMLParsingSupport.absoluteURL(for: anchor, relativeTo: baseURL) {
                return url
            }
        }
        return nil
    }
}
