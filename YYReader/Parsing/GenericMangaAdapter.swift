import Foundation
import SwiftSoup

/// Weighted DOM recognition; automatic import requires high confidence.
struct GenericMangaAdapter: NovelSourceAdapter {
    func canHandle(_ document: LoadedHTML) -> Bool { true }

    private let noiseSelectors = MangaRegionScorer.noiseSelectors

    func recognizeChapter(_ loaded: LoadedHTML) throws -> MangaRegionScorer.Recognition? {
        let dom = try HTMLParsingSupport.document(from: loaded)
        let title = try heading(in: dom)
        let previous = try navigation(in: dom, labels: ["上一话", "上一話", "上一章", "上一章节", "Previous Chapter"], rel: "prev", base: loaded.finalURL)
        let next = try navigation(in: dom, labels: ["下一话", "下一話", "下一章", "下一章节", "Next Chapter"], rel: "next", base: loaded.finalURL)
        return try MangaRegionScorer().recognize(in: dom, base: loaded.finalURL,
            chapterTitle: isChapterTitle(title), chapterNavigation: previous != nil || next != nil)
    }

    func parseChapterPage(_ loaded: LoadedHTML) throws -> ParsedChapterPage {
        try parseChapterPage(loaded, requiringHighConfidence: false)
    }

    func parseChapterPage(_ loaded: LoadedHTML, requiringHighConfidence: Bool) throws -> ParsedChapterPage {
        let dom = try HTMLParsingSupport.document(from: loaded)
        let title = try heading(in: dom)
        let previous = try navigation(in: dom, labels: ["上一话", "上一話", "上一章", "上一章节", "Previous Chapter"], rel: "prev", base: loaded.finalURL)
        let next = try navigation(in: dom, labels: ["下一话", "下一話", "下一章", "下一章节", "Next Chapter"], rel: "next", base: loaded.finalURL)
        let catalog = try navigation(in: dom, labels: ["目录", "章节列表", "返回目录", "全部章节", "All Chapters"], base: loaded.finalURL)
        let nextPage = try navigation(in: dom, labels: ["下一页", "下页", "Next Page"], base: loaded.finalURL)
        guard let recognition = try MangaRegionScorer().recognize(in: dom, base: loaded.finalURL,
            chapterTitle: isChapterTitle(title), chapterNavigation: previous != nil || next != nil),
              !requiringHighConfidence || recognition.isHighConfidence else {
            throw NovelParsingError.noMangaImages
        }
        let blobSequence = recognition.imageURLs.contains { $0.scheme == "blob" }
        let addresses = recognition.imageURLs.enumerated().map { index, url in
            blobSequence && recognition.needsBrowser[index]
                ? MangaBlobSource(chapterURL: loaded.finalURL, index: index).url : url
        }
        return ParsedChapterPage(title: title,
            bookTitle: try meta("og:novel:book_name", in: dom) ?? meta("og:book_name", in: dom) ?? bookTitle(in: dom),
            author: try meta("author", in: dom), paragraphs: [],
            catalogURL: catalog,
            previousChapterURL: previous, nextChapterURL: next,
            nextPageURL: nextPage, imageURLs: addresses)
    }

    func hasMangaCatalogEvidence(_ loaded: LoadedHTML) throws -> Bool {
        let dom = try HTMLParsingSupport.document(from: loaded)
        let type = try meta("og:type", in: dom)?.lowercased() ?? ""
        let title = try dom.title()
        return type.contains("comic") || title.contains("漫画") || title.contains("漫畫")
    }

    func parseCatalogPage(_ loaded: LoadedHTML) throws -> ParsedBookCatalog {
        let dom = try HTMLParsingSupport.document(from: loaded)
        try dom.select(noiseSelectors).remove()
        let containers = try dom.select(".chapter-list, #chapter-list, #chapterlist, .chapter_list, .chapter-grid, .chapters-grid, .manga-chapters, .comic-chapters, .comic-chapter, .catalog, #catalog, .chapters, #chapters, .playlist, #playlist, .detail-list-select, #chapterlistload").array()
        var candidates: [[ChapterSeed]] = []
        for container in containers {
            var seen = Set<String>()
            var chapters: [ChapterSeed] = []
            for link in try container.select("a[href]").array() {
                let title = try link.text().trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty, title.count <= 100,
                      let url = HTMLParsingSupport.absoluteURL(for: link, relativeTo: loaded.finalURL),
                      isChapterTitle(title) || isChapterPath(url, relativeTo: loaded.finalURL),
                      ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                      HTMLParsingSupport.isSameOrigin(url, as: loaded.finalURL),
                      seen.insert(URLCanonicalizer.canonicalString(url.absoluteString)).inserted else { continue }
                chapters.append(ChapterSeed(title: title, url: url, sortIndex: chapters.count + 1))
            }
            if chapters.count >= 2 { candidates.append(chapters) }
        }
        guard let chapters = candidates.max(by: { $0.count < $1.count }) else { throw NovelParsingError.missingCatalog }
        for control in try dom.select("button, a[href^=javascript]").array() {
            let label = try control.text().filter { !$0.isWhitespace && !"[]【】".contains($0) }
            let style = try control.attr("style").filter { !$0.isWhitespace }.lowercased()
            if CatalogExpansionScripts.labels.contains(label), !style.contains("display:none"),
               !control.hasAttr("hidden"), try control.attr("data-yyreader-expanded") != "true" {
                throw NovelParsingError.catalogNeedsExpansion
            }
        }
        return ParsedBookCatalog(title: try meta("og:book_name", in: dom) ?? heading(in: dom),
            author: try meta("author", in: dom) ?? "未知作者", chapters: chapters,
            nextPageURL: try navigation(in: dom, labels: ["下一页", "下页", "Next Page"], base: loaded.finalURL))
    }

    private func heading(in dom: Document) throws -> String {
        let heading = try dom.select("h1, .chapter-title, #chapter-title").first()?.text()
        return try heading.flatMap { $0.isEmpty ? nil : $0 } ?? dom.title().components(separatedBy: "|")[0]
    }

    private func meta(_ name: String, in dom: Document) throws -> String? {
        let value = try dom.select("meta[property='\(name)'], meta[name='\(name)']").first()?.attr("content")
        return value.flatMap { $0.isEmpty ? nil : $0 }
    }

    private func bookTitle(in dom: Document) throws -> String? {
        guard let title = HTMLParsingSupport.firstCapture("^(.+?)第\\s*[0-9一二三四五六七八九十百千]+\\s*[话話章]", in: try dom.title()) else { return nil }
        return HTMLParsingSupport.replacingRegex("(?:漫画|漫畫)$", in: title.trimmingCharacters(in: CharacterSet(charactersIn: " _-")), with: "")
    }

    private func isChapterTitle(_ title: String) -> Bool {
        HTMLParsingSupport.firstCapture("(?i)(第\\s*[0-9一二三四五六七八九十百千]+\\s*[话話章回卷]|(?:chapter|episode)\\s*\\d+)", in: title) != nil
            || HTMLParsingSupport.firstCapture("^((?:总)?\\d+(?:[.·、\\s].*)?)$", in: title) != nil
            || ["序章", "序话", "番外", "后记"].contains(where: title.hasPrefix)
    }

    private func isChapterPath(_ url: URL, relativeTo base: URL) -> Bool {
        guard url != base else { return false }
        let prefix = "/" + base.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/"
        return url.path.range(of: "^/(?:chapter|read)/[^/]+", options: .regularExpression) != nil
            || (url.path.hasPrefix(prefix) && url.path.range(of: "/[0-9]+\\.html$", options: .regularExpression) != nil)
    }

    private func navigation(in dom: Document, labels: Set<String>, rel: String? = nil, base: URL) throws -> URL? {
        for link in try dom.select("a[href]").array() {
            let visible = try link.text().trimmingCharacters(in: .whitespacesAndNewlines)
            let text = visible.isEmpty ? try link.attr("title") : visible
            let relationship = try link.attr("rel").split(separator: " ")
            guard labels.contains(text) || (labels.contains("目录") && text.hasSuffix("完整章节目录")) || (rel.map { relationship.contains(Substring($0)) } == true && !["下一页", "下页", "Next Page"].contains(text)),
                  let url = HTMLParsingSupport.absoluteURL(for: link, relativeTo: base),
                  HTMLParsingSupport.isSameOrigin(url, as: base), url != base else { continue }
            return url
        }
        return nil
    }
}
