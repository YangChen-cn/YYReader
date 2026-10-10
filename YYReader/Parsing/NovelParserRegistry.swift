import Foundation

actor NovelParserRegistry {
    private let adapters: [any NovelSourceAdapter] = [
        GuaziMangaAdapter(),
        ZaiMangaAdapter(),
        HaoduoMangaAdapter(),
        DuokanMangaAdapter(),
        ManhuazhanMangaAdapter(),
        QidiySourceAdapter(),
        GenericNovelAdapter()
    ]
    private let mangaAdapters: [any NovelSourceAdapter] = [GuaziMangaAdapter(), ZaiMangaAdapter(), HaoduoMangaAdapter(), DuokanMangaAdapter(), ManhuazhanMangaAdapter(), GenericMangaAdapter()]
    private let novelAdapters: [any NovelSourceAdapter] = [QidiySourceAdapter(), GenericNovelAdapter()]

    private func adapters(for type: BookContentType) -> [any NovelSourceAdapter] {
        switch type { case .auto: adapters; case .novel: novelAdapters; case .manga: mangaAdapters }
    }

    func canonicalSourceURL(_ url: URL) -> URL { HaoduoMangaAdapter.canonicalURL(url) }

    func dataURL(for url: URL, contentType: BookContentType = .auto) -> URL? {
        contentType == .novel ? nil : ZaiMangaAdapter.dataURL(for: url)
    }

    func parseChapterPage(_ document: LoadedHTML, contentType: BookContentType = .auto) throws -> ParsedChapterPage {
        guard let adapter = adapters(for: contentType).first(where: { $0.canHandle(document) }) else {
            throw NovelParsingError.noReadableContent
        }
        let page: ParsedChapterPage
        if contentType == .auto, adapter is GenericNovelAdapter {
            do {
                page = try GenericNovelAdapter().parseChapterPage(document, requiringTrustworthyText: true)
            } catch NovelParsingError.noReadableContent {
                do {
                    return try GenericMangaAdapter().parseChapterPage(document, requiringHighConfidence: true)
                } catch NovelParsingError.noMangaImages {
                    // Relax only link density for navigation-heavy novels;
                    // keep the minimum non-link prose requirement after cleanup.
                    page = try GenericNovelAdapter().parseChapterPage(document,
                        requiringTrustworthyText: true, allowingNavigationHeavyText: true)
                }
            }
        } else {
            page = try adapter.parseChapterPage(document)
        }
        if contentType == .manga && page.imageURLs.isEmpty { throw NovelParsingError.noMangaImages }
        if contentType == .novel && (page.paragraphs.isEmpty || !page.imageURLs.isEmpty) { throw NovelParsingError.noReadableContent }
        return page
    }

    func parseCatalogPage(_ document: LoadedHTML, contentType: BookContentType = .auto) throws -> ParsedBookCatalog {
        guard let adapter = adapters(for: contentType).first(where: { $0.canHandle(document) }) else {
            throw NovelParsingError.missingCatalog
        }
        if contentType == .auto, adapter is GenericNovelAdapter,
           try GenericMangaAdapter().hasMangaCatalogEvidence(document) {
            do {
                return try GenericMangaAdapter().parseCatalogPage(document)
            } catch NovelParsingError.missingCatalog {
                // A manga label alone does not establish a usable chapter list.
            }
        }
        do {
            return try adapter.parseCatalogPage(document)
        } catch NovelParsingError.missingCatalog where contentType == .auto && adapter is GenericNovelAdapter {
            return try GenericMangaAdapter().parseCatalogPage(document)
        }
    }
}
