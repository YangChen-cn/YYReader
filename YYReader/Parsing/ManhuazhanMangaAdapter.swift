import Foundation
import SwiftSoup

/// This reader lazily replaces placeholder src values, so use its complete public list.
struct ManhuazhanMangaAdapter: NovelSourceAdapter {
    func canHandle(_ document: LoadedHTML) -> Bool {
        let host = document.finalURL.host?.lowercased() ?? ""
        return host == "manhuazhan.com" || host.hasSuffix(".manhuazhan.com")
    }

    func parseChapterPage(_ loaded: LoadedHTML) throws -> ParsedChapterPage {
        let dom = try HTMLParsingSupport.document(from: loaded)
        guard let json = try dom.select("#yyreader-manga-images").first()?.data(),
              let data = json.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: [String]],
              let addresses = object["imageURLs"], !addresses.isEmpty else {
            throw NovelParsingError.noMangaImages
        }
        let container = try dom.body()?.appendElement("div").attr("data-reader-images", "true")
        for address in addresses {
            guard let url = URL(string: address), ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { continue }
            try container?.appendElement("img").attr("src", url.absoluteString)
        }
        let page = try GenericMangaAdapter().parseChapterPage(LoadedHTML(requestedURL: loaded.requestedURL,
            finalURL: loaded.finalURL, html: dom.outerHtml(), retrievalKind: loaded.retrievalKind))
        let bookLink = try dom.select(".bread-crumbs a[href*='/comic/']").first()
        let catalog = bookLink.flatMap { HTMLParsingSupport.absoluteURL(for: $0, relativeTo: loaded.finalURL) }
        return ParsedChapterPage(title: page.title, bookTitle: try bookLink?.text() ?? page.bookTitle,
            author: page.author, paragraphs: [], catalogURL: catalog ?? page.catalogURL,
            previousChapterURL: page.previousChapterURL, nextChapterURL: page.nextChapterURL,
            nextPageURL: page.nextPageURL, imageURLs: page.imageURLs)
    }

    func parseCatalogPage(_ document: LoadedHTML) throws -> ParsedBookCatalog {
        try GenericMangaAdapter().parseCatalogPage(document)
    }
}
