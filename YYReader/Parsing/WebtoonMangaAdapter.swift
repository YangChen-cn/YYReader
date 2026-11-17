import Foundation
import SwiftSoup

struct WebtoonMangaAdapter: NovelSourceAdapter {
    func canHandle(_ document: LoadedHTML) -> Bool {
        let url = document.finalURL
        return ["www.webtoons.com", "webtoons.com", "m.webtoons.com"].contains(url.host?.lowercased() ?? "")
            && ["viewer", "list"].contains(url.lastPathComponent)
            && number("title_no", in: url) != nil
    }

    static func canonicalURL(_ url: URL) -> URL {
        guard ["m.webtoons.com", "webtoons.com"].contains(url.host?.lowercased() ?? ""),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        components.host = "www.webtoons.com"
        return components.url ?? url
    }

    func parseChapterPage(_ document: LoadedHTML) throws -> ParsedChapterPage {
        let base = document.finalURL
        guard base.lastPathComponent == "viewer", number("episode_no", in: base) != nil else {
            throw NovelParsingError.noMangaImages
        }
        let dom = try HTMLParsingSupport.document(from: document)
        var seen = Set<URL>()
        let images = try dom.select("#_imageList img._images").array().compactMap { image -> URL? in
            let lazySource = try image.attr("data-url").trimmingCharacters(in: .whitespacesAndNewlines)
            let source = lazySource.isEmpty ? try image.attr("src") : lazySource
            guard !source.isEmpty, let url = URL(string: source, relativeTo: base)?.absoluteURL,
                  ["https", "http"].contains(url.scheme ?? ""), url.host != nil,
                  url.lastPathComponent != "bg_transparency.png", seen.insert(url).inserted else { return nil }
            return url
        }
        guard !images.isEmpty else { throw NovelParsingError.noMangaImages }
        let book = try dom.select(".subj_info a.subj").first()
        return ParsedChapterPage(
            title: try dom.select(".subj_episode").first()?.text() ?? "漫画章节",
            bookTitle: try book?.text(), author: nil, paragraphs: [],
            catalogURL: book.flatMap { link($0, from: base, route: "list") },
            previousChapterURL: try dom.select("a._prevEpisode").first().flatMap { episodeLink($0, from: base) },
            nextChapterURL: try dom.select("a._nextEpisode").first().flatMap { episodeLink($0, from: base) },
            nextPageURL: nil, imageURLs: images
        )
    }

    func parseCatalogPage(_ document: LoadedHTML) throws -> ParsedBookCatalog {
        let base = document.finalURL
        guard base.lastPathComponent == "list" else { throw NovelParsingError.missingCatalog }
        let dom = try HTMLParsingSupport.document(from: document)
        var seen = Set<Int>()
        let chapters = try dom.select("#_listUl li._episodeItem a[href]").array().compactMap { anchor -> ChapterSeed? in
            guard let url = episodeLink(anchor, from: base),
                  let episode = number("episode_no", in: url),
                  let title = try anchor.select(".subj").first()?.text(), !title.isEmpty,
                  seen.insert(episode).inserted else { return nil }
            return ChapterSeed(title: title, url: url, sortIndex: seen.count)
        }
        guard !chapters.isEmpty else { throw NovelParsingError.missingCatalog }

        // The next arrow jumps an entire section of pages. Prefer the adjacent
        // page and use the arrow only when it leads to that same adjacent page.
        let current = number("page", in: base) ?? 1
        let next = try dom.select(".paginate a.pg_page[href], .paginate a.pg_next[href]").array()
            .lazy.compactMap { link($0, from: base, route: "list") }
            .first { number("page", in: $0).map { $0 - 1 } == current }
        try dom.select(".author_area button").remove()
        let author = try dom.select(".author_area").first()?.text()
        return ParsedBookCatalog(title: try dom.select("h1.subj").text(),
            author: author.flatMap { $0.isEmpty ? nil : $0 } ?? "未知作者", chapters: chapters, nextPageURL: next)
    }

    private func episodeLink(_ element: Element, from base: URL) -> URL? {
        guard let url = link(element, from: base, route: "viewer"),
              number("episode_no", in: url) != nil else { return nil }
        return url
    }

    private func link(_ element: Element, from base: URL, route: String) -> URL? {
        guard let url = HTMLParsingSupport.absoluteURL(for: element, relativeTo: base),
              HTMLParsingSupport.isSameOrigin(url, as: base), url.lastPathComponent == route,
              number("title_no", in: url) == number("title_no", in: base) else { return nil }
        return url
    }

    private func number(_ name: String, in url: URL) -> Int? {
        guard let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
            .first(where: { $0.name == name })?.value, let number = Int(value), number > 0 else { return nil }
        return number
    }
}
