import Foundation
import SwiftSoup

struct HaoduoMangaAdapter: NovelSourceAdapter {
    func canHandle(_ document: LoadedHTML) -> Bool {
        let host = document.finalURL.host ?? ""
        return host == "haoduoman.com" || host.hasSuffix(".haoduoman.com")
    }

    static func canonicalURL(_ url: URL) -> URL {
        guard ["m.haoduoman.com", "haoduoman.com"].contains(url.host?.lowercased() ?? ""),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        components.host = "www.haoduoman.com"
        return components.url ?? url
    }

    func parseChapterPage(_ document: LoadedHTML) throws -> ParsedChapterPage {
        let dom = try SwiftSoup.parse(document.html)
        var sources: [String] = []
        if let metadata = try dom.select("#yyreader-manga-images").first(),
           let object = try JSONSerialization.jsonObject(with: Data(try metadata.data().utf8)) as? [String: Any] {
            sources = object["imageURLs"] as? [String] ?? []
        }
        if sources.isEmpty {
            sources = try dom.select(".chapter-images img").array().map { try $0.attr("src") }
        }
        var seen = Set<URL>()
        let images = sources.compactMap { source -> URL? in
            guard let url = webURL(source, base: Self.canonicalURL(document.finalURL)), seen.insert(url).inserted else { return nil }
            return url
        }
        guard !images.isEmpty else { throw NovelParsingError.noReadableContent }
        let path = document.finalURL.path.split(separator: "/")
        guard path.count == 3, path[0] == "manhua", Int(path[1]) != nil else {
            throw NovelParsingError.unsupportedURL
        }
        let catalog = URL(string: "/manhua/\(path[1])", relativeTo: Self.canonicalURL(document.finalURL))!.absoluteURL
        return ParsedChapterPage(
            title: try dom.select(".breadcrumb li span").last()?.text() ?? "漫画章节",
            bookTitle: try dom.select(".breadcrumb a[href='/manhua/\(path[1])']").first()?.text(),
            author: nil, paragraphs: [], catalogURL: catalog,
            previousChapterURL: try navigationURL(".j-chapter-prev", dom: dom, base: Self.canonicalURL(document.finalURL)),
            nextChapterURL: try navigationURL(".j-chapter-next", dom: dom, base: Self.canonicalURL(document.finalURL)),
            nextPageURL: nil, imageURLs: images
        )
    }

    func parseCatalogPage(_ document: LoadedHTML) throws -> ParsedBookCatalog {
        let dom = try SwiftSoup.parse(document.html)
        var seen = Set<URL>()
        let chapters = try dom.select(".comic-chapters a[href]").array().compactMap { link -> ChapterSeed? in
            guard let url = webURL(try link.attr("href"), base: Self.canonicalURL(document.finalURL)),
                  url.host == Self.canonicalURL(document.finalURL).host, seen.insert(url).inserted else { return nil }
            return ChapterSeed(title: try link.text(), url: url, sortIndex: seen.count)
        }
        guard !chapters.isEmpty else { throw NovelParsingError.missingCatalog }
        let author = try dom.select(".metas-body .author").first()?.text() ?? "未知作者"
        return ParsedBookCatalog(title: try dom.select(".metas-title").text(),
                                 author: author.replacingOccurrences(of: "作者：", with: "").trimmingCharacters(in: .whitespaces),
                                 chapters: chapters, nextPageURL: nil)
    }

    private func navigationURL(_ selector: String, dom: Document, base: URL) throws -> URL? {
        guard let link = try dom.select(selector).first(),
              let url = webURL(try link.attr("href"), base: base), url.host == base.host else { return nil }
        return url
    }

    private func webURL(_ source: String, base: URL) -> URL? {
        guard !source.isEmpty, let url = URL(string: source, relativeTo: base)?.absoluteURL,
              ["https", "http"].contains(url.scheme ?? "") else { return nil }
        return url
    }
}
