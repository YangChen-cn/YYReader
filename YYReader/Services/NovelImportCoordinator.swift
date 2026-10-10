import Foundation

@MainActor
final class NovelImportCoordinator {
    private let loader: any HTMLDocumentLoading
    private let parser: NovelParserRegistry
    private let processingWorker: NovelProcessingWorker
    private let catalogRefreshTimeout: Duration

    init(
        loader: any HTMLDocumentLoading,
        parser: NovelParserRegistry = NovelParserRegistry(),
        processingWorker: NovelProcessingWorker = NovelProcessingWorker(),
        catalogRefreshTimeout: Duration = .seconds(180)
    ) {
        self.loader = loader
        self.parser = parser
        self.processingWorker = processingWorker
        self.catalogRefreshTimeout = catalogRefreshTimeout
    }

    func importNovel(from inputURL: URL, contentType: BookContentType = .auto) async throws -> NovelImportResult {
        loader.beginOperation()
        guard ["http", "https"].contains(inputURL.scheme?.lowercased() ?? "") else {
            throw NovelParsingError.unsupportedURL
        }
        let firstDocument = try await loadSourceDocument(inputURL, contentType: contentType)
        if let catalog = try await staticCatalog(in: firstDocument, contentType: contentType) {
            return try await importCatalog(catalog, from: firstDocument, contentType: contentType)
        }
        do {
            let chapter = try await loadChapterContent(from: firstDocument, contentType: contentType)
            return try await importChapter(chapter, contentType: contentType)
        } catch {
            guard let parsingError = error as? NovelParsingError,
                  parsingError == .noReadableContent || parsingError == .noMangaImages else { throw error }
            do { return try await importCatalog(firstDocument, contentType: contentType) }
            catch NovelParsingError.missingCatalog {
                if contentType == .auto { throw NovelParsingError.missingCatalog }
                throw parsingError
            }
        }
    }

    private func importChapter(_ chapter: ChapterLoadResult, contentType: BookContentType) async throws -> NovelImportResult {
        let initialCatalog: ParsedBookCatalog?
        if let catalogURL = chapter.catalogURL {
            do {
                initialCatalog = try await loadCatalogPage(at: catalogURL, contentType: contentType).inReadingOrder()
            } catch is CancellationError {
                throw CancellationError()
            } catch HTMLLoadError.cancelled {
                throw HTMLLoadError.cancelled
            } catch {
                initialCatalog = nil
            }
        } else {
            initialCatalog = nil
        }

        let chapterSeed = ChapterSeed(
            title: chapter.title,
            url: chapter.chapterURL,
            sortIndex: HTMLParsingSupport.chapterNumber(in: chapter.title) ?? 1
        )
        let catalog = initialCatalog?.chapters ?? [chapterSeed]
        let catalogTitle = initialCatalog?.title ?? ""

        return NovelImportResult(
            bookTitle: catalogTitle.isEmpty ? (chapter.bookTitle ?? "未命名小说") : catalogTitle,
            author: initialCatalog?.author ?? chapter.author ?? "未知作者",
            sourceBookURL: chapter.catalogURL ?? sourceBookURL(for: chapter),
            catalogURL: chapter.catalogURL ?? chapter.chapterURL,
            hasCatalog: chapter.catalogURL != nil,
            catalog: catalog,
            catalogIsComplete: initialCatalog?.nextPageURL == nil && initialCatalog != nil,
            chapterTitle: chapter.title,
            chapterURL: chapter.chapterURL,
            bodyText: chapter.bodyText,
            previousChapterURL: chapter.previousChapterURL,
            nextChapterURL: chapter.nextChapterURL,
            imageURLs: chapter.imageURLs,
            contentType: contentType
        )
    }

    private func importCatalog(_ document: LoadedHTML, contentType: BookContentType) async throws -> NovelImportResult {
        let catalog = try await parseCatalogPage(document, contentType: contentType)
        return try await importCatalog(catalog, from: document, contentType: contentType)
    }

    private func importCatalog(
        _ catalog: ParsedBookCatalog,
        from document: LoadedHTML,
        contentType: BookContentType
    ) async throws -> NovelImportResult {
        let catalog = catalog.inReadingOrder()
        guard let firstChapter = catalog.chapters.first else {
            throw NovelParsingError.missingCatalog
        }
        let chapter = try await loadChapterContentWithoutReset(from: firstChapter.url, contentType: contentType)

        return NovelImportResult(
            bookTitle: catalog.title,
            author: catalog.author,
            sourceBookURL: document.finalURL,
            catalogURL: document.finalURL,
            hasCatalog: true,
            catalog: catalog.chapters,
            catalogIsComplete: catalog.nextPageURL == nil,
            chapterTitle: chapter.title,
            chapterURL: chapter.chapterURL,
            bodyText: chapter.bodyText,
            previousChapterURL: chapter.previousChapterURL,
            nextChapterURL: chapter.nextChapterURL,
            imageURLs: chapter.imageURLs,
            contentType: contentType
        )
    }

    func loadChapterContent(from inputURL: URL, contentType: BookContentType = .auto) async throws -> ChapterLoadResult {
        loader.beginOperation()
        return try await loadChapterContentWithoutReset(from: inputURL, contentType: contentType)
    }

    private func loadChapterContentWithoutReset(from inputURL: URL, contentType: BookContentType) async throws -> ChapterLoadResult {
        guard ["http", "https"].contains(inputURL.scheme?.lowercased() ?? "") else {
            throw NovelParsingError.unsupportedURL
        }

        let firstDocument = try await loadSourceDocument(inputURL, contentType: contentType)
        return try await loadChapterContent(from: firstDocument, contentType: contentType)
    }

    private func loadChapterContent(from firstDocument: LoadedHTML, contentType: BookContentType) async throws -> ChapterLoadResult {
        let firstPage = try await parseChapterPage(firstDocument, contentType: contentType)
        var pages = [firstPage]
        var pageURL = firstPage.nextPageURL
        var nextChapterOverride: URL?
        var visitedPages: Set<URL> = [firstDocument.finalURL]

        while let nextPage = pageURL {
            guard visitedPages.count < 20 else { throw NovelParsingError.paginationLimit }
            guard HTMLParsingSupport.isSameOrigin(nextPage, as: firstDocument.finalURL) else {
                throw NovelParsingError.unsupportedURL
            }
            guard visitedPages.insert(nextPage).inserted else { throw NovelParsingError.paginationLoop }
            let document = try await loadSourceDocument(nextPage, contentType: contentType)
            let parsed = try await parseChapterPage(document, contentType: contentType)
            if let originalNumber = chapterNumber(of: firstPage),
               let incomingNumber = chapterNumber(of: parsed),
               originalNumber != incomingNumber {
                // Some readers label the next chapter "下一页". Verify the
                // fetched heading before merging, so a whole novel is never
                // concatenated into the first chapter until the page limit.
                nextChapterOverride = document.finalURL
                break
            }
            pages.append(parsed)
            pageURL = parsed.nextPageURL
        }
        return try await processingWorker.aggregateChapterPages(
            pages,
            sourceURL: firstDocument.finalURL,
            nextChapterOverride: nextChapterOverride
        )
    }

    func refreshCatalog(
        from catalogURL: URL,
        contentType: BookContentType = .auto,
        onPageStarted: ((Int) -> Void)? = nil
    ) async throws -> ParsedBookCatalog {
        loader.beginOperation()
        return try await loadCatalog(startingAt: catalogURL, contentType: contentType, onPageStarted: onPageStarted)
    }

    private func loadCatalogPage(at url: URL, contentType: BookContentType) async throws -> ParsedBookCatalog {
        let document = try await loadSourceDocument(url, contentType: contentType)
        return try await parseCatalogPage(document, contentType: contentType)
    }

    private func loadCatalog(
        startingAt url: URL,
        contentType: BookContentType,
        onPageStarted: ((Int) -> Void)?
    ) async throws -> ParsedBookCatalog {
        let clock = ContinuousClock()
        let startedAt = clock.now
        var nextURL: URL? = url
        var visited = Set<String>()
        var pages: [ParsedBookCatalog] = []

        while let pageURL = nextURL {
            try checkCatalogDeadline(startedAt: startedAt, clock: clock)
            guard visited.count < 200 else { throw NovelParsingError.paginationLimit }
            guard HTMLParsingSupport.isSameOrigin(pageURL, as: url) else { break }
            let pageKey = URLCanonicalizer.canonicalString(pageURL.absoluteString)
            guard visited.insert(pageKey).inserted else { throw NovelParsingError.paginationLoop }
            onPageStarted?(visited.count)
            let document = try await loadSourceDocument(pageURL, contentType: contentType)
            try checkCatalogDeadline(startedAt: startedAt, clock: clock)
            let page = try await parseCatalogPage(document, contentType: contentType)
            pages.append(page)
            if let candidate = page.nextPageURL,
               URLCanonicalizer.canonicalString(candidate.absoluteString)
                == URLCanonicalizer.canonicalString(document.finalURL.absoluteString) {
                nextURL = nil
            } else {
                nextURL = page.nextPageURL
            }
        }

        return try await processingWorker.aggregateCatalogPages(pages)
    }

    private func checkCatalogDeadline(startedAt: ContinuousClock.Instant, clock: ContinuousClock) throws {
        if startedAt.duration(to: clock.now) >= catalogRefreshTimeout {
            throw NovelParsingError.catalogRefreshTimedOut
        }
    }

    private func chapterNumber(of page: ParsedChapterPage) -> Int? {
        if let number = HTMLParsingSupport.chapterNumber(in: page.title) { return number }
        guard !page.imageURLs.isEmpty,
              let number = HTMLParsingSupport.firstCapture("第\\s*(\\d+)\\s*[话話]", in: page.title) else { return nil }
        return Int(number)
    }

    private func loadSourceDocument(_ url: URL, contentType: BookContentType) async throws -> LoadedHTML {
        let dataURL = await parser.dataURL(for: url, contentType: contentType)
        let response = try await loader.load(dataURL ?? url)
        let finalURL = await parser.canonicalSourceURL(dataURL == nil ? response.finalURL : url)
        return LoadedHTML(requestedURL: url, finalURL: finalURL, html: response.html, retrievalKind: response.retrievalKind)
    }

    private func parseChapterPage(_ document: LoadedHTML, contentType: BookContentType) async throws -> ParsedChapterPage {
        do {
            return try await parser.parseChapterPage(document, contentType: contentType)
        } catch {
            return try await retryChapterParsingWithRenderedDOM(document, originalError: error, contentType: contentType)
        }
    }

    private func parseCatalogPage(_ document: LoadedHTML, contentType: BookContentType) async throws -> ParsedBookCatalog {
        do {
            return try await parser.parseCatalogPage(document, contentType: contentType)
        } catch {
            return try await retryCatalogParsingWithRenderedDOM(document, originalError: error, contentType: contentType)
        }
    }

    private func staticCatalog(in document: LoadedHTML, contentType: BookContentType) async throws -> ParsedBookCatalog? {
        if try await hasHighConfidenceChapterContent(in: document, contentType: contentType) {
            return nil
        }
        do {
            let catalog = try await parser.parseCatalogPage(document, contentType: contentType)
            // Two or more chapter entries distinguish a catalog from a chapter page's navigation links.
            return catalog.chapters.count > 1 ? catalog : nil
        } catch NovelParsingError.catalogNeedsExpansion {
            // A static preview is not a complete catalog. Use the existing
            // bounded JavaScript DOM fallback before choosing the first chapter.
            return try await parseCatalogPage(document, contentType: contentType)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return nil
        }
    }

    private func hasHighConfidenceChapterContent(in document: LoadedHTML, contentType: BookContentType) async throws -> Bool {
        do {
            let chapter = try await parser.parseChapterPage(document, contentType: contentType)
            return await processingWorker.isHighConfidenceChapter(chapter)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return false
        }
    }

    private func retryChapterParsingWithRenderedDOM(
        _ document: LoadedHTML,
        originalError: any Error,
        contentType: BookContentType
    ) async throws -> ParsedChapterPage {
        guard document.retrievalKind == .urlSession,
              let fallbackLoader = loader as? any RenderedDOMFallbackLoading else {
            throw originalError
        }
        let renderedDocument = try await fallbackLoader.loadRenderedDOM(document.finalURL)
        let page = try await parser.parseChapterPage(renderedDocument, contentType: contentType)
        fallbackLoader.promoteRenderedDOMHost(for: renderedDocument.finalURL)
        return page
    }

    private func retryCatalogParsingWithRenderedDOM(
        _ document: LoadedHTML,
        originalError: any Error,
        contentType: BookContentType
    ) async throws -> ParsedBookCatalog {
        guard document.retrievalKind == .urlSession,
              let fallbackLoader = loader as? any RenderedDOMFallbackLoading else {
            throw originalError
        }
        let renderedDocument = try await fallbackLoader.loadRenderedDOM(document.finalURL)
        let catalog = try await parser.parseCatalogPage(renderedDocument, contentType: contentType)
        fallbackLoader.promoteRenderedDOMHost(for: renderedDocument.finalURL)
        return catalog
    }

    private func sourceBookURL(for chapter: ChapterLoadResult) -> URL {
        let chapterURL = chapter.chapterURL
        let pathComponents = chapterURL.path.split(separator: "/", omittingEmptySubsequences: true)
        if hasExplicitBookPath(pathComponents),
           var components = URLComponents(url: chapterURL, resolvingAgainstBaseURL: false) {
            components.path = "/" + pathComponents.dropLast().joined(separator: "/") + "/"
            components.query = nil
            components.fragment = nil
            if let url = components.url { return url }
        }

        var components = URLComponents()
        components.scheme = "yyreader-book"
        components.host = chapterURL.host?.lowercased() ?? "unknown-source"
        components.path = "/" + normalizedIdentityComponent(chapter.bookTitle ?? "未命名小说")
            + "/" + normalizedIdentityComponent(chapter.author ?? "未知作者")
        return components.url ?? chapterURL
    }

    private func hasExplicitBookPath(_ pathComponents: [Substring]) -> Bool {
        guard pathComponents.count >= 3 else { return false }
        let collection = pathComponents[pathComponents.count - 3].lowercased()
        return ["book", "books", "novel", "novels", "serial", "fiction", "story", "stories", "comic", "comics", "manga", "manhua"].contains(collection)
    }

    private func normalizedIdentityComponent(_ value: String) -> String {
        HTMLParsingSupport.normalize(value).folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

}
