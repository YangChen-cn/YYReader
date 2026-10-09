import Foundation
import SwiftSoup

/// Public image lists and ordered chapter links; advertisements and recommendations are excluded.
struct GuaziMangaAdapter: NovelSourceAdapter {
    func canHandle(_ document: LoadedHTML) -> Bool {
        let host = document.finalURL.host?.lowercased() ?? ""
        return host == "guazimanhua.com" || host.hasSuffix(".guazimanhua.com")
    }

    func parseChapterPage(_ document: LoadedHTML) throws -> ParsedChapterPage {
        let dom = try SwiftSoup.parse(document.html)
        let article = try objects(in: dom).first { $0["@type"] as? String == "Article" }
        var seen = Set<URL>()
        let images = try dom.select("[data-reader-images] img").array().compactMap { element -> URL? in
            let source = try element.attr("src")
            guard let url = webURL(source, base: document.finalURL), seen.insert(url).inserted else { return nil }
            return url
        }
        guard !images.isEmpty else { throw NovelParsingError.noReadableContent }
        let part = article?["isPartOf"] as? [String: Any]
        let catalog = webURL(part?["url"] as? String ?? "", base: document.finalURL)
        var previous: URL?
        var next: URL?
        for link in try dom.select("a[href]").array() {
            guard let url = chapterURL(try link.attr("href"), base: document.finalURL) else { continue }
            let label = try link.text()
            if label.contains("上一话") { previous = url }
            if label.contains("下一话") { next = url }
        }
        let fallbackTitle = try dom.select("h1").text()
        return ParsedChapterPage(
            title: article?["name"] as? String ?? fallbackTitle,
            bookTitle: part?["name"] as? String,
            author: (article?["author"] as? [String: Any])?["name"] as? String,
            paragraphs: [], catalogURL: catalog,
            previousChapterURL: previous, nextChapterURL: next, nextPageURL: nil,
            imageURLs: images
        )
    }

    func parseCatalogPage(_ document: LoadedHTML) throws -> ParsedBookCatalog {
        let dom = try SwiftSoup.parse(document.html)
        let nodes = try objects(in: dom)
        guard let comic = nodes.first(where: { $0["@type"] as? String == "ComicStory" }),
              let list = nodes.first(where: { $0["@type"] as? String == "ItemList" }),
              let items = list["itemListElement"] as? [[String: Any]] else {
            throw NovelParsingError.missingCatalog
        }
        var seen = Set<URL>()
        // The site's structured list is in reading order, unlike its reverse-order mobile grid.
        // Preserve list order, including extras; never sort by chapter numbers in the titles.
        var chapters = items.compactMap { item -> ChapterSeed? in
            guard let url = chapterURL(item["url"] as? String ?? "", base: document.finalURL),
                  let title = item["name"] as? String, !title.isEmpty,
                  seen.insert(url).inserted else { return nil }
            return ChapterSeed(title: title, url: url, sortIndex: seen.count)
        }
        var fullSeen = Set<URL>()
        var full = try dom.select("[data-chapter-list] a[href]").array().compactMap { link -> ChapterSeed? in
            guard let url = chapterURL(try link.attr("href"), base: document.finalURL),
                  fullSeen.insert(url).inserted else { return nil }
            return ChapterSeed(title: try link.text(), url: url, sortIndex: fullSeen.count)
        }
        if full.count > chapters.count {
            // JSON-LD exposes only the first 50 items, while the complete grid is
            // newest first. Its last link matches the structured list's first link.
            if full.last?.url == chapters.first?.url { full.reverse() }
            chapters = full.enumerated().map { offset, item in
                ChapterSeed(title: item.title, url: item.url, sortIndex: offset + 1)
            }
        }
        guard !chapters.isEmpty else { throw NovelParsingError.missingCatalog }
        let fallbackTitle = try dom.select("h1").text()
        return ParsedBookCatalog(
            title: comic["name"] as? String ?? fallbackTitle,
            author: (comic["author"] as? [String: Any])?["name"] as? String ?? "未知作者",
            chapters: chapters, nextPageURL: nil
        )
    }

    private func objects(in dom: Document) throws -> [[String: Any]] {
        var nodes: [[String: Any]] = []
        for script in try dom.select("script[type=application/ld+json]").array() {
            let data = Data(try script.data().utf8)
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            nodes.append(contentsOf: object["@graph"] as? [[String: Any]] ?? [object])
        }
        return nodes
    }

    private func webURL(_ source: String, base: URL) -> URL? {
        guard !source.isEmpty, let url = URL(string: source, relativeTo: base)?.absoluteURL,
              ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }

    private func chapterURL(_ source: String, base: URL) -> URL? {
        guard let url = webURL(source, base: base), url.host == base.host,
              url.path == "/chapter.php",
              URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains(where: {
                  $0.name == "id" && Int($0.value ?? "") != nil
              }) == true else { return nil }
        return url
    }
}
