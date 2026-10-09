import Foundation

actor NovelParserRegistry {
    private let adapters: [any NovelSourceAdapter] = [
        GuaziMangaAdapter(),
        ZaiMangaAdapter(),
        HaoduoMangaAdapter(),
        ManhuazhanMangaAdapter(),
        QidiySourceAdapter(),
        GenericNovelAdapter()
    ]
    private let mangaAdapters: [any NovelSourceAdapter] = [GuaziMangaAdapter(), ZaiMangaAdapter(), HaoduoMangaAdapter(), ManhuazhanMangaAdapter(), GenericMangaAdapter()]
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
        let page = try adapter.parseChapterPage(document)
        if contentType == .manga && page.imageURLs.isEmpty { throw NovelParsingError.noMangaImages }
        if contentType == .novel && (page.paragraphs.isEmpty || !page.imageURLs.isEmpty) { throw NovelParsingError.noReadableContent }
        return page
    }

    func parseCatalogPage(_ document: LoadedHTML, contentType: BookContentType = .auto) throws -> ParsedBookCatalog {
        guard let adapter = adapters(for: contentType).first(where: { $0.canHandle(document) }) else {
            throw NovelParsingError.missingCatalog
        }
        return try adapter.parseCatalogPage(document)
    }
}
