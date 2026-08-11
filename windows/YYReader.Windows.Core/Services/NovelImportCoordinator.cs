using System.Diagnostics;
using System.Text.RegularExpressions;
using YYReader.Windows.Core.Models;
using YYReader.Windows.Core.Parsing;

namespace YYReader.Windows.Core.Services;

public sealed class NovelImportCoordinator
{
    private readonly IHtmlDocumentLoader _loader;
    private readonly NovelParserRegistry _parser;
    private readonly TimeSpan _catalogRefreshTimeout;

    public NovelImportCoordinator(
        IHtmlDocumentLoader loader,
        NovelParserRegistry? parser = null,
        TimeSpan? catalogRefreshTimeout = null)
    {
        _loader = loader;
        _parser = parser ?? new NovelParserRegistry();
        _catalogRefreshTimeout = catalogRefreshTimeout ?? TimeSpan.FromSeconds(180);
    }

    public async Task<NovelImportResult> ImportNovelAsync(Uri inputUrl, CancellationToken cancellationToken = default)
    {
        _loader.BeginOperation();
        if (!UrlCanonicalizer.IsHttp(inputUrl))
        {
            throw new NovelParsingException(NovelParsingErrorKind.UnsupportedUrl);
        }

        var firstDocument = await _loader.LoadAsync(inputUrl, cancellationToken).ConfigureAwait(false);
        var catalog = await StaticCatalogAsync(firstDocument, cancellationToken).ConfigureAwait(false);
        if (catalog is not null)
        {
            return await ImportCatalogAsync(catalog, firstDocument, cancellationToken).ConfigureAwait(false);
        }

        try
        {
            var chapter = await LoadChapterContentAsync(firstDocument, cancellationToken).ConfigureAwait(false);
            return await ImportChapterAsync(chapter, cancellationToken).ConfigureAwait(false);
        }
        catch (NovelParsingException ex) when (ex.Kind == NovelParsingErrorKind.NoReadableContent)
        {
            return await ImportCatalogAsync(firstDocument, cancellationToken).ConfigureAwait(false);
        }
    }

    public async Task<ChapterLoadResult> LoadChapterContentAsync(Uri inputUrl, CancellationToken cancellationToken = default)
    {
        _loader.BeginOperation();
        if (!UrlCanonicalizer.IsHttp(inputUrl))
        {
            throw new NovelParsingException(NovelParsingErrorKind.UnsupportedUrl);
        }

        var firstDocument = await _loader.LoadAsync(inputUrl, cancellationToken).ConfigureAwait(false);
        return await LoadChapterContentAsync(firstDocument, cancellationToken).ConfigureAwait(false);
    }

    public async Task<ParsedBookCatalog> RefreshCatalogAsync(
        Uri catalogUrl,
        Action<int>? onPageStarted = null,
        CancellationToken cancellationToken = default)
    {
        _loader.BeginOperation();
        return await LoadCatalogAsync(catalogUrl, onPageStarted, cancellationToken).ConfigureAwait(false);
    }

    private async Task<NovelImportResult> ImportChapterAsync(
        ChapterLoadResult chapter,
        CancellationToken cancellationToken)
    {
        ParsedBookCatalog? initialCatalog = null;
        if (chapter.CatalogUrl is not null)
        {
            try
            {
                initialCatalog = await LoadCatalogPageAsync(chapter.CatalogUrl, cancellationToken).ConfigureAwait(false);
            }
            catch (OperationCanceledException)
            {
                throw;
            }
            catch
            {
                // A chapter with usable text is still importable when its catalog is unavailable.
            }
        }

        var chapterSeed = new ChapterSeed(
            chapter.Title,
            chapter.ChapterUrl,
            HtmlParsingSupport.ChapterNumber(chapter.Title) ?? 1);
        var catalog = initialCatalog?.Chapters ?? [chapterSeed];
        var bookTitle = string.IsNullOrWhiteSpace(initialCatalog?.Title) ? chapter.BookTitle ?? "未命名小说" : initialCatalog.Title;
        var author = initialCatalog?.Author ?? chapter.Author ?? "未知作者";
        var sourceBookUrl = chapter.CatalogUrl ?? UrlCanonicalizer.SourceBookIdentityForChapter(chapter.ChapterUrl, chapter.BookTitle, chapter.Author);
        var catalogUrl = chapter.CatalogUrl ?? chapter.ChapterUrl;
        return new NovelImportResult(
            bookTitle,
            author,
            sourceBookUrl,
            catalogUrl,
            chapter.CatalogUrl is not null,
            catalog,
            initialCatalog is not null && initialCatalog.NextPageUrl is null,
            chapter.Title,
            chapter.ChapterUrl,
            chapter.BodyText,
            chapter.PreviousChapterUrl,
            chapter.NextChapterUrl);
    }

    private async Task<NovelImportResult> ImportCatalogAsync(LoadedHtml document, CancellationToken cancellationToken)
    {
        var catalog = await ParseCatalogPageAsync(document, cancellationToken).ConfigureAwait(false);
        return await ImportCatalogAsync(catalog, document, cancellationToken).ConfigureAwait(false);
    }

    private async Task<NovelImportResult> ImportCatalogAsync(
        ParsedBookCatalog catalog,
        LoadedHtml document,
        CancellationToken cancellationToken)
    {
        var firstChapter = catalog.Chapters.FirstOrDefault()
            ?? throw new NovelParsingException(NovelParsingErrorKind.MissingCatalog);
        var chapter = await LoadChapterContentAsync(firstChapter.Url, cancellationToken).ConfigureAwait(false);
        return new NovelImportResult(
            catalog.Title,
            catalog.Author,
            UrlCanonicalizer.Canonicalize(document.FinalUri),
            UrlCanonicalizer.Canonicalize(document.FinalUri),
            true,
            catalog.Chapters,
            catalog.NextPageUrl is null,
            chapter.Title,
            chapter.ChapterUrl,
            chapter.BodyText,
            chapter.PreviousChapterUrl,
            chapter.NextChapterUrl);
    }

    private async Task<ChapterLoadResult> LoadChapterContentAsync(
        LoadedHtml firstDocument,
        CancellationToken cancellationToken)
    {
        var firstPage = await ParseChapterPageAsync(firstDocument, cancellationToken).ConfigureAwait(false);
        var paragraphs = firstPage.Paragraphs.ToList();
        var nextPageUrl = firstPage.NextPageUrl;
        var visitedPages = new HashSet<string>(StringComparer.Ordinal)
        {
            UrlCanonicalizer.Canonicalize(firstDocument.FinalUri).AbsoluteUri
        };
        var finalPage = firstPage;

        while (nextPageUrl is not null)
        {
            if (visitedPages.Count >= 20)
            {
                throw new NovelParsingException(NovelParsingErrorKind.PaginationLimit);
            }
            if (!HtmlParsingSupport.IsSameOrigin(nextPageUrl, firstDocument.FinalUri))
            {
                throw new NovelParsingException(NovelParsingErrorKind.UnsupportedUrl);
            }

            var pageKey = UrlCanonicalizer.Canonicalize(nextPageUrl).AbsoluteUri;
            if (!visitedPages.Add(pageKey))
            {
                throw new NovelParsingException(NovelParsingErrorKind.PaginationLoop);
            }

            var document = await _loader.LoadAsync(nextPageUrl, cancellationToken).ConfigureAwait(false);
            var parsed = await ParseChapterPageAsync(document, cancellationToken).ConfigureAwait(false);
            AppendWithoutBoundaryDuplicate(parsed.Paragraphs, paragraphs);
            finalPage = parsed;
            nextPageUrl = parsed.NextPageUrl;
        }

        var chapterUrl = UrlCanonicalizer.CanonicalizeChapter(firstDocument.FinalUri);
        return new ChapterLoadResult(
            firstPage.Title,
            firstPage.BookTitle,
            firstPage.Author,
            firstPage.CatalogUrl ?? firstDocument.FinalUri,
            chapterUrl,
            string.Join("\n\n", paragraphs),
            firstPage.PreviousChapterUrl,
            finalPage.NextChapterUrl);
    }

    private async Task<ParsedBookCatalog> LoadCatalogAsync(
        Uri startingUrl,
        Action<int>? onPageStarted,
        CancellationToken cancellationToken)
    {
        var stopwatch = Stopwatch.StartNew();
        var nextUrl = UrlCanonicalizer.Canonicalize(startingUrl);
        var visited = new HashSet<string>(StringComparer.Ordinal);
        var seenChapterUrls = new HashSet<string>(StringComparer.Ordinal);
        var chapters = new List<ChapterSeed>();
        var title = string.Empty;
        var author = "未知作者";

        while (nextUrl is not null)
        {
            CheckCatalogDeadline(stopwatch, cancellationToken);
            if (visited.Count >= 200)
            {
                throw new NovelParsingException(NovelParsingErrorKind.PaginationLimit);
            }
            if (!HtmlParsingSupport.IsSameOrigin(nextUrl, startingUrl))
            {
                break;
            }

            var pageKey = nextUrl.AbsoluteUri;
            if (!visited.Add(pageKey))
            {
                throw new NovelParsingException(NovelParsingErrorKind.PaginationLoop);
            }

            onPageStarted?.Invoke(visited.Count);
            var document = await _loader.LoadAsync(nextUrl, cancellationToken).ConfigureAwait(false);
            CheckCatalogDeadline(stopwatch, cancellationToken);
            var page = await ParseCatalogPageAsync(document, cancellationToken).ConfigureAwait(false);
            if (title.Length == 0) title = page.Title;
            if (author == "未知作者") author = page.Author;
            foreach (var seed in page.Chapters)
            {
                var key = UrlCanonicalizer.CanonicalizeChapter(seed.Url).AbsoluteUri;
                if (seenChapterUrls.Add(key))
                {
                    chapters.Add(seed);
                }
            }

            nextUrl = page.NextPageUrl;
        }

        var ordered = chapters.Select((seed, index) => seed with { SortIndex = index + 1 }).ToArray();
        return new ParsedBookCatalog(title, author, ordered, null);
    }

    private async Task<ParsedBookCatalog?> StaticCatalogAsync(LoadedHtml document, CancellationToken cancellationToken)
    {
        if (await HasHighConfidenceChapterContentAsync(document, cancellationToken).ConfigureAwait(false))
        {
            return null;
        }

        try
        {
            var catalog = await ParseCatalogPageAsync(document, cancellationToken).ConfigureAwait(false);
            return catalog.Chapters.Count > 1 ? catalog : null;
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch
        {
            return null;
        }
    }

    private async Task<bool> HasHighConfidenceChapterContentAsync(LoadedHtml document, CancellationToken cancellationToken)
    {
        try
        {
            var chapter = await ParseChapterPageAsync(document, cancellationToken).ConfigureAwait(false);
            var bodyLength = string.Concat(chapter.Paragraphs).Length;
            return bodyLength >= 180
                || (bodyLength >= 60
                    && LooksLikeChapterTitle(chapter.Title)
                    && (chapter.PreviousChapterUrl is not null || chapter.NextChapterUrl is not null));
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch
        {
            return false;
        }
    }

    private async Task<ParsedChapterPage> ParseChapterPageAsync(LoadedHtml document, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        try
        {
            return _parser.ParseChapterPage(document);
        }
        catch (Exception original) when (original is not OperationCanceledException)
        {
            if (document.RetrievalKind != HtmlRetrievalKind.UrlSession
                || _loader is not IRenderedDomFallbackLoading fallback)
            {
                throw;
            }

            var rendered = await fallback.LoadRenderedDomAsync(document.FinalUri, cancellationToken).ConfigureAwait(false);
            var page = _parser.ParseChapterPage(rendered);
            fallback.PromoteRenderedDomHost(rendered.FinalUri);
            return page;
        }
    }

    private async Task<ParsedBookCatalog> ParseCatalogPageAsync(LoadedHtml document, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        try
        {
            return _parser.ParseCatalogPage(document);
        }
        catch (Exception original) when (original is not OperationCanceledException
            && document.RetrievalKind == HtmlRetrievalKind.UrlSession
            && _loader is IRenderedDomFallbackLoading)
        {
            var fallback = (IRenderedDomFallbackLoading)_loader;
            var rendered = await fallback.LoadRenderedDomAsync(document.FinalUri, cancellationToken).ConfigureAwait(false);
            var catalog = _parser.ParseCatalogPage(rendered);
            fallback.PromoteRenderedDomHost(rendered.FinalUri);
            return catalog;
        }
    }

    private async Task<ParsedBookCatalog> LoadCatalogPageAsync(Uri url, CancellationToken cancellationToken)
    {
        var document = await _loader.LoadAsync(url, cancellationToken).ConfigureAwait(false);
        return await ParseCatalogPageAsync(document, cancellationToken).ConfigureAwait(false);
    }

    private void CheckCatalogDeadline(Stopwatch stopwatch, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        if (stopwatch.Elapsed >= _catalogRefreshTimeout)
        {
            throw new NovelParsingException(NovelParsingErrorKind.CatalogRefreshTimedOut);
        }
    }

    private static void AppendWithoutBoundaryDuplicate(IEnumerable<string> incoming, ICollection<string> existing)
    {
        var newParagraphs = incoming.ToList();
        if (newParagraphs.Count == 0) return;
        if (existing is List<string> list && list.Count > 0 && list[^1] == newParagraphs[0])
        {
            list.AddRange(newParagraphs.Skip(1));
        }
        else if (existing is List<string> target)
        {
            target.AddRange(newParagraphs);
        }
        else
        {
            foreach (var paragraph in newParagraphs) existing.Add(paragraph);
        }
    }

    private static bool LooksLikeChapterTitle(string title) =>
        HtmlParsingSupport.ChapterNumber(title) is not null
        || Regex.IsMatch(title, "^(?:序章|楔子|引子|尾声|后记|番外)", RegexOptions.CultureInvariant);
}
