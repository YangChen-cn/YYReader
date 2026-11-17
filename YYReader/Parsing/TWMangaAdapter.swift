import Foundation
import SwiftSoup

struct TWMangaAdapter: NovelSourceAdapter {
    private static let hosts = ["www.twmanga.com", "twmanga.com", "www.twbzmg.com", "www.baozimh.com"]

    func canHandle(_ document: LoadedHTML) -> Bool {
        Self.hosts.contains(document.finalURL.host?.lowercased() ?? "")
            && document.finalURL.pathComponents.dropFirst().first == "comic"
    }

    func parseChapterPage(_ document: LoadedHTML) throws -> ParsedChapterPage {
        let base = document.finalURL
        guard let identity = chapterIdentity(base) else { throw NovelParsingError.noMangaImages }
        let dom = try HTMLParsingSupport.document(from: document)
        var seen = Set<URL>()
        let images = try dom.select(".comic-contain amp-img.comic-contain__item, .comic-contain img.comic-contain__item")
            .array().compactMap { image -> URL? in
                let lazySource = try image.attr("data-src")
                let source = lazySource.isEmpty ? try image.attr("src") : lazySource
                guard !source.isEmpty, let url = URL(string: source, relativeTo: base)?.absoluteURL,
                      ["http", "https"].contains(url.scheme ?? ""), url.host != nil,
                      seen.insert(url).inserted else { return nil }
                return url
            }
        guard !images.isEmpty else { throw NovelParsingError.noMangaImages }

        let titleParts = try dom.title().components(separatedBy: " - ")
        let title = (titleParts.first ?? "").replacingOccurrences(
            of: #"\s*[（(]\d+\s*/\s*\d+[）)]\s*$"#, with: "", options: .regularExpression)
        let previous = try navigation("#prev-chapter", in: dom, base: base, comic: identity.comic)
        let next = try navigation("#next-chapter", in: dom, base: base, comic: identity.comic)
        let nextIdentity = next.flatMap(chapterIdentity)
        let nextPage = nextIdentity?.slot == identity.slot && (nextIdentity?.page ?? 0) > identity.page ? next : nil
        return ParsedChapterPage(
            title: title.isEmpty ? "漫画章节" : title,
            bookTitle: titleParts.count >= 3 ? titleParts.dropFirst().dropLast().joined(separator: " - ") : nil, author: nil, paragraphs: [],
            catalogURL: URL(string: "/comic/\(identity.comic)", relativeTo: base)?.absoluteURL,
            previousChapterURL: previous.flatMap { chapterIdentity($0)?.slot == identity.slot ? nil : $0 },
            nextChapterURL: nextPage == nil && nextIdentity?.slot != identity.slot ? next : nil,
            nextPageURL: nextPage, imageURLs: images
        )
    }

    func parseCatalogPage(_ document: LoadedHTML) throws -> ParsedBookCatalog {
        let base = document.finalURL
        let path = base.pathComponents
        guard path.count == 3, path[1] == "comic", path[2] != "chapter" else {
            throw NovelParsingError.missingCatalog
        }
        let comic = path[2]
        let dom = try HTMLParsingSupport.document(from: document)
        var seen = Set<URL>()
        // The site's latest-update list repeats entries. The full directory
        // starts in chapter-items and continues in its collapsed HTML section.
        let chapters = try dom.select("#chapter-items a.comics-chapters__item, #chapters_other_list a.comics-chapters__item")
            .array().compactMap { anchor -> ChapterSeed? in
                guard let link = HTMLParsingSupport.absoluteURL(for: anchor, relativeTo: base),
                      HTMLParsingSupport.isSameOrigin(link, as: base),
                      let url = catalogChapterURL(link, base: base, comic: comic) else { return nil }
                let title = try anchor.text()
                guard !title.isEmpty, seen.insert(url).inserted else { return nil }
                return ChapterSeed(title: title, url: url, sortIndex: seen.count)
            }
        guard !chapters.isEmpty else { throw NovelParsingError.missingCatalog }
        let author = try dom.select(".comics-detail__author").text()
        return ParsedBookCatalog(title: try dom.select(".comics-detail__title").text(),
            author: author.isEmpty ? "未知作者" : author, chapters: chapters, nextPageURL: nil)
    }

    private func catalogChapterURL(_ link: URL, base: URL, comic: String) -> URL? {
        if let identity = chapterIdentity(link), identity.comic == comic, identity.page == 1 { return link }
        guard link.path == "/user/page_direct",
              let items = URLComponents(url: link, resolvingAgainstBaseURL: false)?.queryItems,
              items.first(where: { $0.name == "comic_id" })?.value == comic,
              let section = items.first(where: { $0.name == "section_slot" })?.value.flatMap(Int.init),
              let chapter = items.first(where: { $0.name == "chapter_slot" })?.value.flatMap(Int.init),
              section >= 0, chapter >= 0 else { return nil }
        return URL(string: "/comic/chapter/\(comic)/\(section)_\(chapter).html", relativeTo: base)?.absoluteURL
    }

    private func navigation(_ selector: String, in dom: Document, base: URL, comic: String) throws -> URL? {
        guard let anchor = try dom.select(selector).first(),
              let url = HTMLParsingSupport.absoluteURL(for: anchor, relativeTo: base),
              HTMLParsingSupport.isSameOrigin(url, as: base),
              chapterIdentity(url)?.comic == comic else { return nil }
        return url
    }

    private func chapterIdentity(_ url: URL) -> (comic: String, slot: String, page: Int)? {
        let path = url.pathComponents
        let parts = url.deletingPathExtension().lastPathComponent.split(separator: "_", omittingEmptySubsequences: false)
        guard path.count == 5, path[1] == "comic", path[2] == "chapter",
              url.pathExtension == "html", (2...3).contains(parts.count),
              parts.allSatisfy({ Int($0) != nil }) else { return nil }
        return (path[3], "\(parts[0])_\(parts[1])", parts.count == 3 ? Int(parts[2]) ?? 1 : 1)
    }
}
