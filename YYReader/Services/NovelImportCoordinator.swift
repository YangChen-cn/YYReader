import Foundation

@MainActor
final class NovelImportCoordinator {
    private let loader: any HTMLDocumentLoading
    private let parser: NovelParserRegistry

    init(loader: any HTMLDocumentLoading, parser: NovelParserRegistry = NovelParserRegistry()) {
        self.loader = loader
        self.parser = parser
    }

    func importNovel(from inputURL: URL) async throws -> NovelImportResult {
        loader.beginOperation()
        let chapter = try await loadChapterContentWithoutReset(from: inputURL)
        guard let catalogURL = chapter.catalogURL else { throw NovelParsingError.missingCatalog }
        let catalog = try await loadCatalog(startingAt: catalogURL)

        return NovelImportResult(
            bookTitle: catalog.title.isEmpty ? (chapter.bookTitle ?? "未命名小说") : catalog.title,
            author: catalog.author,
            catalogURL: catalogURL,
            catalog: catalog.chapters,
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
        let firstPage = try await parser.parseChapterPage(firstDocument)
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
            let parsed = try await parser.parseChapterPage(document)
            appendWithoutBoundaryDuplicate(parsed.paragraphs, to: &paragraphs)
            finalPage = parsed
            pageURL = parsed.nextPageURL
        }

        let chapterURL = canonicalChapterURL(firstDocument.finalURL)

        return ChapterLoadResult(
            title: firstPage.title,
            bookTitle: firstPage.bookTitle,
            catalogURL: firstPage.catalogURL,
            chapterURL: chapterURL,
            bodyText: paragraphs.joined(separator: "\n\n"),
            previousChapterURL: firstPage.previousChapterURL,
            nextChapterURL: finalPage.nextChapterURL
        )
    }

    func refreshCatalog(from catalogURL: URL) async throws -> ParsedBookCatalog {
        loader.beginOperation()
        return try await loadCatalog(startingAt: catalogURL)
    }

    private func loadCatalog(startingAt url: URL) async throws -> ParsedBookCatalog {
        var nextURL: URL? = url
        var visited = Set<URL>()
        var allChapters: [ChapterSeed] = []
        var seenChapterURLs = Set<String>()
        var bookTitle = ""
        var author = "未知作者"

        while let pageURL = nextURL {
            guard visited.count < 200 else { throw NovelParsingError.paginationLimit }
            guard HTMLParsingSupport.isSameOrigin(pageURL, as: url) else { break }
            guard visited.insert(pageURL).inserted else { throw NovelParsingError.paginationLoop }
            let document = try await loader.load(pageURL)
            let page = try await parser.parseCatalogPage(document)
            if bookTitle.isEmpty { bookTitle = page.title }
            if author == "未知作者" { author = page.author }
            for seed in page.chapters where seenChapterURLs.insert(seed.url.absoluteString).inserted {
                allChapters.append(seed)
            }
            nextURL = page.nextPageURL
        }

        return ParsedBookCatalog(
            title: bookTitle,
            author: author,
            chapters: allChapters.sorted { lhs, rhs in
                if lhs.sortIndex == rhs.sortIndex { lhs.url.absoluteString < rhs.url.absoluteString }
                else { lhs.sortIndex < rhs.sortIndex }
            },
            nextPageURL: nil
        )
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
        let path = HTMLParsingSupport.replacingRegex("/\\d+\\.html$", in: url.path, with: ".html")
        guard path != url.path, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        components.path = path
        return components.url ?? url
    }
}
