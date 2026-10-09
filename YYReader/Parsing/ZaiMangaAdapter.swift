import Foundation

/// Uses the same unauthenticated JSON endpoints as the site's public web reader.
struct ZaiMangaAdapter: NovelSourceAdapter {
    func canHandle(_ document: LoadedHTML) -> Bool { document.finalURL.host == "manhua.zaimanhua.com" }

    static func dataURL(for url: URL) -> URL? {
        guard url.host == "manhua.zaimanhua.com" else { return nil }
        let path = url.path.split(separator: "/").map(String.init)
        var components = URLComponents()
        components.scheme = "https"
        components.host = url.host
        var query = [URLQueryItem(name: "channel", value: "pc"),
                     URLQueryItem(name: "app_name", value: "zmh"),
                     URLQueryItem(name: "version", value: "1.0.0")]
        if path.count == 4, path[0] == "view", Int(path[2]) != nil, Int(path[3]) != nil {
            components.path = "/api/v1/comic2/chapter/detail"
            query += [URLQueryItem(name: "comic_id", value: path[2]), URLQueryItem(name: "chapter_id", value: path[3])]
        } else if path.count == 1 {
            components.path = "/api/v1/comic2/comic/detail"
            query += [URLQueryItem(name: "comic_py", value: path[0])]
        } else { return nil }
        components.queryItems = query
        return components.url
    }

    func parseChapterPage(_ document: LoadedHTML) throws -> ParsedChapterPage {
        let payload = try data(in: document)
        guard let info = payload["chapterInfo"] as? [String: Any],
              let sources = info["page_url"] as? [String] else { throw NovelParsingError.noReadableContent }
        let urls = sources.compactMap { value -> URL? in
            guard let url = URL(string: value), ["http", "https"].contains(url.scheme ?? "") else { return nil }
            return url
        }
        guard !urls.isEmpty else { throw NovelParsingError.noReadableContent }
        let path = document.finalURL.path.split(separator: "/")
        guard path.count == 4 else { throw NovelParsingError.unsupportedURL }
        let catalogURL = URL(string: "/\(path[1])/", relativeTo: document.finalURL)!.absoluteURL
        return ParsedChapterPage(title: info["title"] as? String ?? "漫画章节", bookTitle: nil, author: nil,
                                 paragraphs: [], catalogURL: catalogURL, previousChapterURL: nil,
                                 nextChapterURL: nil, nextPageURL: nil, imageURLs: urls)
    }

    func parseCatalogPage(_ document: LoadedHTML) throws -> ParsedBookCatalog {
        let payload = try data(in: document)
        guard let info = payload["comicInfo"] as? [String: Any],
              let groups = info["chapterList"] as? [[String: Any]],
              let comicID = info["id"] as? Int, let name = info["comicPy"] as? String else {
            throw NovelParsingError.missingCatalog
        }
        guard info["canRead"] as? Bool != false else { throw NovelParsingError.noReadableContent }
        var chapters: [ChapterSeed] = []
        var seen = Set<Int>()
        for group in groups {
            var entries = group["data"] as? [[String: Any]] ?? []
            // The API returns newest first inside each volume group. Reverse the whole
            // group to preserve extras and the publisher's order; don't sort title numbers.
            if let first = entries.first?["chapter_order"] as? Int,
               let last = entries.last?["chapter_order"] as? Int, first > last { entries.reverse() }
            for item in entries {
                guard let id = item["chapter_id"] as? Int, seen.insert(id).inserted,
                      let title = item["chapter_title"] as? String,
                      let url = URL(string: "/view/\(name)/\(comicID)/\(id)", relativeTo: document.finalURL)?.absoluteURL
                else { continue }
                chapters.append(ChapterSeed(title: title, url: url, sortIndex: chapters.count + 1))
            }
        }
        guard !chapters.isEmpty else { throw NovelParsingError.missingCatalog }
        let authors = (info["authorsTagList"] as? [[String: Any]] ?? []).compactMap { $0["tagName"] as? String }
        return ParsedBookCatalog(title: info["title"] as? String ?? "漫画", author: authors.joined(separator: "、"),
                                 chapters: chapters, nextPageURL: nil)
    }

    private func data(in document: LoadedHTML) throws -> [String: Any] {
        guard let response = try JSONSerialization.jsonObject(with: Data(document.html.utf8)) as? [String: Any],
              response["errno"] as? Int == 0, let data = response["data"] as? [String: Any] else {
            throw NovelParsingError.noReadableContent
        }
        return data
    }
}
