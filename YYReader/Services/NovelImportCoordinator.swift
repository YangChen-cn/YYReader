import Foundation

@MainActor
final class NovelImportCoordinator {
    private let loader: any HTMLDocumentLoading
    private let parser: NovelParserRegistry
    private let catalogRefreshTimeout: Duration

    init(
        loader: any HTMLDocumentLoading,
        parser: NovelParserRegistry = NovelParserRegistry(),
        catalogRefreshTimeout: Duration = .seconds(180)
    ) {
        self.loader = loader
        self.parser = parser
        self.catalogRefreshTimeout = catalogRefreshTimeout
    }

    func importNovel(from inputURL: URL) async throws -> NovelImportResult {
        loader.beginOperation()
        guard ["http", "https"].contains(inputURL.scheme?.lowercased() ?? "") else {
            throw NovelParsingError.unsupportedURL
        }
        let firstDocument = try await loader.load(inputURL)
        if let catalog = try await staticCatalog(in: firstDocument) {
            return try await importCatalog(catalog, from: firstDocument)
        }
        do {
            let chapter = try await loadChapterContent(from: firstDocument)
            return try await importChapter(chapter)
        } catch NovelParsingError.noReadableContent {
            return try await importCatalog(firstDocument)
        }
    }

    private func importChapter(_ chapter: ChapterLoadResult) async throws -> NovelImportResult {
        let initialCatalog: ParsedBookCatalog?
        if let catalogURL = chapter.catalogURL {
            do {
                initialCatalog = try await loadCatalogPage(at: catalogURL)
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
            nextChapterURL: chapter.nextChapterURL
        )
    }

    private func importCatalog(_ document: LoadedHTML) async throws -> NovelImportResult {
        let catalog = try await parseCatalogPage(document)
        return try await importCatalog(catalog, from: document)
    }

    private func importCatalog(
        _ catalog: ParsedBookCatalog,
        from document: LoadedHTML
    ) async throws -> NovelImportResult {
        guard let firstChapter = catalog.chapters.first else {
            throw NovelParsingError.missingCatalog
        }
        let chapter = try await loadChapterContentWithoutReset(from: firstChapter.url)

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
            nextChapterURL: chapter.nextChapterURL
        )
    }

    func loadChapterContent(from inputURL: URL) async throws -> ChapterLoadResult {
        loader.beginOperation()
        return try await loadChapterContentWithoutReset(from: inputURL)
    }

    private func loadChapterContentWithoutReset(from inputURL: URL) async throws -> ChapterLoadResult {
        guard ["http", "https"].contains(inputURL.scheme?.lowercased() ?? "") else {
            throw NovelParsingError.unsupportedURL
        }

        let firstDocument = try await loader.load(inputURL)
        return try await loadChapterContent(from: firstDocument)
    }

    private func loadChapterContent(from firstDocument: LoadedHTML) async throws -> ChapterLoadResult {
        let firstPage = try await parseChapterPage(firstDocument)
        var paragraphs = firstPage.paragraphs
        var pageURL = firstPage.nextPageURL
        var visitedPages: Set<URL> = [firstDocument.finalURL]
        var finalPage = firstPage

        while let nextPage = pageURL {
            guard visitedPages.count < 20 else { throw NovelParsingError.paginationLimit }
            guard HTMLParsingSupport.isSameOrigin(nextPage, as: firstDocument.finalURL) else {
                throw NovelParsingError.unsupportedURL
            }
            guard visitedPages.insert(nextPage).inserted else { throw NovelParsingError.paginationLoop }
            let document = try await loader.load(nextPage)
            let parsed = try await parseChapterPage(document)
            appendWithoutBoundaryDuplicate(parsed.paragraphs, to: &paragraphs)
            finalPage = parsed
            pageURL = parsed.nextPageURL
        }

        let chapterURL = canonicalChapterURL(firstDocument.finalURL)

        return ChapterLoadResult(
            title: firstPage.title,
            bookTitle: firstPage.bookTitle,
            author: firstPage.author,
            catalogURL: firstPage.catalogURL,
            chapterURL: chapterURL,
            bodyText: paragraphs.joined(separator: "\n\n"),
            previousChapterURL: firstPage.previousChapterURL,
            nextChapterURL: finalPage.nextChapterURL
        )
    }

    func refreshCatalog(
        from catalogURL: URL,
        onPageStarted: ((Int) -> Void)? = nil
    ) async throws -> ParsedBookCatalog {
        loader.beginOperation()
        return try await loadCatalog(startingAt: catalogURL, onPageStarted: onPageStarted)
    }

    private func loadCatalogPage(at url: URL) async throws -> ParsedBookCatalog {
        let document = try await loader.load(url)
        return try await parseCatalogPage(document)
    }

    private func loadCatalog(
        startingAt url: URL,
        onPageStarted: ((Int) -> Void)?
    ) async throws -> ParsedBookCatalog {
        let clock = ContinuousClock()
        let startedAt = clock.now
        var nextURL: URL? = url
        var visited = Set<URL>()
        var allChapters: [ChapterSeed] = []
        var seenChapterURLs = Set<String>()
        var bookTitle = ""
        var author = "未知作者"

        while let pageURL = nextURL {
            try checkCatalogDeadline(startedAt: startedAt, clock: clock)
            guard visited.count < 200 else { throw NovelParsingError.paginationLimit }
            guard HTMLParsingSupport.isSameOrigin(pageURL, as: url) else { break }
            guard visited.insert(pageURL).inserted else { throw NovelParsingError.paginationLoop }
            onPageStarted?(visited.count)
            let document = try await loader.load(pageURL)
            try checkCatalogDeadline(startedAt: startedAt, clock: clock)
            let page = try await parseCatalogPage(document)
            if bookTitle.isEmpty { bookTitle = page.title }
            if author == "未知作者" { author = page.author }
            for seed in page.chapters where seenChapterURLs.insert(seed.url.absoluteString).inserted {
                allChapters.append(seed)
            }
            nextURL = page.nextPageURL
        }

        let orderedChapters = allChapters.enumerated().map { offset, seed in
            ChapterSeed(title: seed.title, url: seed.url, sortIndex: offset + 1)
        }

        return ParsedBookCatalog(
            title: bookTitle,
            author: author,
            chapters: orderedChapters,
            nextPageURL: nil
        )
    }

    private func checkCatalogDeadline(startedAt: ContinuousClock.Instant, clock: ContinuousClock) throws {
        if startedAt.duration(to: clock.now) >= catalogRefreshTimeout {
            throw NovelParsingError.catalogRefreshTimedOut
        }
    }

    private func parseChapterPage(_ document: LoadedHTML) async throws -> ParsedChapterPage {
        do {
            return try await parser.parseChapterPage(document)
        } catch {
            return try await retryChapterParsingWithRenderedDOM(document, originalError: error)
        }
    }

    private func parseCatalogPage(_ document: LoadedHTML) async throws -> ParsedBookCatalog {
        do {
            return try await parser.parseCatalogPage(document)
        } catch {
            return try await retryCatalogParsingWithRenderedDOM(document, originalError: error)
        }
    }

    private func staticCatalog(in document: LoadedHTML) async throws -> ParsedBookCatalog? {
        if try await hasHighConfidenceChapterContent(in: document) {
            return nil
        }
        do {
            let catalog = try await parser.parseCatalogPage(document)
            // Two or more chapter entries distinguish a catalog from a chapter page's navigation links.
            return catalog.chapters.count > 1 ? catalog : nil
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return nil
        }
    }

    private func hasHighConfidenceChapterContent(in document: LoadedHTML) async throws -> Bool {
        do {
            let chapter = try await parser.parseChapterPage(document)
            let bodyLength = chapter.paragraphs.joined().count
            if bodyLength >= 180 {
                return true
            }
            return bodyLength >= 60
                && looksLikeChapterTitle(chapter.title)
                && (chapter.previousChapterURL != nil || chapter.nextChapterURL != nil)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return false
        }
    }

    private func retryChapterParsingWithRenderedDOM(
        _ document: LoadedHTML,
        originalError: any Error
    ) async throws -> ParsedChapterPage {
        guard document.retrievalKind == .urlSession,
              let fallbackLoader = loader as? any RenderedDOMFallbackLoading else {
            throw originalError
        }
        let renderedDocument = try await fallbackLoader.loadRenderedDOM(document.finalURL)
        let page = try await parser.parseChapterPage(renderedDocument)
        fallbackLoader.promoteRenderedDOMHost(for: renderedDocument.finalURL)
        return page
    }

    private func retryCatalogParsingWithRenderedDOM(
        _ document: LoadedHTML,
        originalError: any Error
    ) async throws -> ParsedBookCatalog {
        guard document.retrievalKind == .urlSession,
              let fallbackLoader = loader as? any RenderedDOMFallbackLoading else {
            throw originalError
        }
        let renderedDocument = try await fallbackLoader.loadRenderedDOM(document.finalURL)
        let catalog = try await parser.parseCatalogPage(renderedDocument)
        fallbackLoader.promoteRenderedDOMHost(for: renderedDocument.finalURL)
        return catalog
    }

    private func appendWithoutBoundaryDuplicate(_ newParagraphs: [String], to paragraphs: inout [String]) {
        guard !newParagraphs.isEmpty else { return }
        if paragraphs.last == newParagraphs.first {
            paragraphs.append(contentsOf: newParagraphs.dropFirst())
        } else {
            paragraphs.append(contentsOf: newParagraphs)
        }
    }

    private func canonicalChapterURL(_ url: URL) -> URL {
        let path = HTMLParsingSupport.replacingRegex(
            "/(\\d+)/(\\d+)/(\\d+)\\.html$",
            in: url.path,
            with: "/$1/$2.html"
        )
        guard path != url.path, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        components.path = path
        return components.url ?? url
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
        return ["book", "books", "novel", "novels", "serial", "fiction", "story", "stories"].contains(collection)
    }

    private func normalizedIdentityComponent(_ value: String) -> String {
        HTMLParsingSupport.normalize(value).folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    private func looksLikeChapterTitle(_ title: String) -> Bool {
        HTMLParsingSupport.chapterNumber(in: title) != nil
            || HTMLParsingSupport.firstCapture("^(?:序章|楔子|引子|尾声|后记|番外)", in: title) != nil
    }
}
