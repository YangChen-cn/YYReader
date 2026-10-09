import Foundation

actor NovelProcessingWorker {
    func aggregateCatalogPages(_ pages: [ParsedBookCatalog]) throws -> ParsedBookCatalog {
        var allChapters: [ChapterSeed] = []
        allChapters.reserveCapacity(pages.reduce(0) { $0 + $1.chapters.count })
        var seenChapterURLs = Set<String>()
        var bookTitle = ""
        var author = "未知作者"

        for page in pages {
            try Task.checkCancellation()
            if bookTitle.isEmpty { bookTitle = page.title }
            if author == "未知作者" { author = page.author }

            let pageChapterURLs = Set(page.chapters.lazy.map {
                URLCanonicalizer.canonicalChapterString($0.url.absoluteString)
            })
            if page.chapters.count > allChapters.count,
               !seenChapterURLs.isEmpty,
               seenChapterURLs.isSubset(of: pageChapterURLs) {
                allChapters.removeAll(keepingCapacity: true)
                seenChapterURLs.removeAll(keepingCapacity: true)
            }

            for seed in page.chapters {
                let key = URLCanonicalizer.canonicalChapterString(seed.url.absoluteString)
                if seenChapterURLs.insert(key).inserted {
                    allChapters.append(seed)
                }
            }
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

    func aggregateChapterPages(
        _ pages: [ParsedChapterPage],
        sourceURL: URL,
        nextChapterOverride: URL? = nil
    ) throws -> ChapterLoadResult {
        guard let firstPage = pages.first, let finalPage = pages.last else {
            throw NovelParsingError.noReadableContent
        }

        var paragraphs: [String] = []
        paragraphs.reserveCapacity(pages.reduce(0) { $0 + $1.paragraphs.count })
        for page in pages {
            try Task.checkCancellation()
            appendWithoutBoundaryDuplicate(page.paragraphs, to: &paragraphs)
        }

        var seenImages = Set<URL>()
        let images = pages.flatMap(\.imageURLs).filter { seenImages.insert($0).inserted }
        guard !images.isEmpty || paragraphs.contains(where: { $0.contains { !$0.isWhitespace } }) else {
            throw NovelParsingError.noReadableContent
        }
        return ChapterLoadResult(
            title: firstPage.title,
            bookTitle: firstPage.bookTitle,
            author: firstPage.author,
            catalogURL: firstPage.catalogURL,
            chapterURL: canonicalChapterURL(sourceURL),
            bodyText: paragraphs.joined(separator: "\n\n"),
            previousChapterURL: firstPage.previousChapterURL,
            nextChapterURL: nextChapterOverride ?? finalPage.nextChapterURL,
            imageURLs: images
        )
    }

    func isHighConfidenceChapter(_ chapter: ParsedChapterPage) -> Bool {
        if !chapter.imageURLs.isEmpty { return true }
        let bodyLength = chapter.paragraphs.reduce(into: 0) { $0 += $1.count }
        if bodyLength >= 180 { return true }
        return bodyLength >= 60
            && looksLikeChapterTitle(chapter.title)
            && (chapter.previousChapterURL != nil || chapter.nextChapterURL != nil)
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
        guard path != url.path,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        components.path = path
        return components.url ?? url
    }

    private func looksLikeChapterTitle(_ title: String) -> Bool {
        if HTMLParsingSupport.chapterNumber(in: title) != nil { return true }
        let normalized = HTMLParsingSupport.normalize(title)
        return ["序章", "序言", "楔子", "引子", "尾声", "后记", "番外"].contains {
            normalized.hasPrefix($0)
        }
    }
}
