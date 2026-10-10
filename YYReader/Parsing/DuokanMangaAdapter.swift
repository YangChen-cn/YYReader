import Foundation
import SwiftSoup

/// Normal site JavaScript exposes a complete list, then displays decoded blobs.
/// Persist original HTTP addresses as stable cache keys; the image bridge reads
/// the normal reader's displayed bytes on cache misses.
struct DuokanMangaAdapter: NovelSourceAdapter {
    static func supports(_ url: URL) -> Bool {
        supportsHost(url.host ?? "")
    }
    static func supportsHost(_ value: String) -> Bool {
        let host = value.lowercased()
        return host == "duokanmh.com" || host.hasSuffix(".duokanmh.com")
    }
    func canHandle(_ document: LoadedHTML) -> Bool { Self.supports(document.finalURL) }

    func parseChapterPage(_ loaded: LoadedHTML) throws -> ParsedChapterPage {
        let dom = try HTMLParsingSupport.document(from: loaded)
        guard let json = try dom.select("#yyreader-manga-images").first()?.data(),
              let object = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let addresses = object["imageURLs"] as? [String], !addresses.isEmpty,
              let body = dom.body() else { throw NovelParsingError.noMangaImages }
        try dom.select(".chapter-images").remove()
        let container = try body.appendElement("div").attr("data-reader-images", "true")
        for address in addresses {
            guard let url = URL(string: address), ["https", "http"].contains(url.scheme?.lowercased() ?? "") else {
                throw NovelParsingError.noMangaImages
            }
            try container.appendElement("img").attr("src", url.absoluteString)
        }
        let page = try GenericMangaAdapter().parseChapterPage(LoadedHTML(requestedURL: loaded.requestedURL,
            finalURL: loaded.finalURL, html: dom.outerHtml(), retrievalKind: loaded.retrievalKind))
        let declaredCatalog = (object["catalogURL"] as? String).flatMap { URL(string: $0, relativeTo: loaded.finalURL)?.absoluteURL }
        let catalog = declaredCatalog.flatMap { HTMLParsingSupport.isSameOrigin($0, as: loaded.finalURL) ? $0 : nil }
        return ParsedChapterPage(title: object["chapterTitle"] as? String ?? page.title,
            bookTitle: object["bookTitle"] as? String ?? page.bookTitle, author: page.author, paragraphs: [],
            catalogURL: catalog ?? page.catalogURL, previousChapterURL: page.previousChapterURL,
            nextChapterURL: page.nextChapterURL, nextPageURL: page.nextPageURL, imageURLs: page.imageURLs)
    }

    func parseCatalogPage(_ document: LoadedHTML) throws -> ParsedBookCatalog {
        try GenericMangaAdapter().parseCatalogPage(document)
    }
}
