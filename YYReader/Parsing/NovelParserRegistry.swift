import Foundation

actor NovelParserRegistry {
    private let adapters: [any NovelSourceAdapter] = [
        GuaziMangaAdapter(),
        ZaiMangaAdapter(),
        HaoduoMangaAdapter(),
        QidiySourceAdapter(),
        GenericNovelAdapter()
    ]

    func canonicalSourceURL(_ url: URL) -> URL { HaoduoMangaAdapter.canonicalURL(url) }

    func dataURL(for url: URL) -> URL? { ZaiMangaAdapter.dataURL(for: url) }

    func parseChapterPage(_ document: LoadedHTML) throws -> ParsedChapterPage {
        guard let adapter = adapters.first(where: { $0.canHandle(document) }) else {
            throw NovelParsingError.noReadableContent
        }
        return try adapter.parseChapterPage(document)
    }

    func parseCatalogPage(_ document: LoadedHTML) throws -> ParsedBookCatalog {
        guard let adapter = adapters.first(where: { $0.canHandle(document) }) else {
            throw NovelParsingError.missingCatalog
        }
        return try adapter.parseCatalogPage(document)
    }
}
