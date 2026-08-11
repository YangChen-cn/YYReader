namespace YYReader.Windows.Core.Parsing;

public sealed class NovelParserRegistry
{
    private readonly IReadOnlyList<INovelSourceAdapter> _adapters =
    [
        new QidiySourceAdapter(),
        new GenericNovelAdapter()
    ];

    public ParsedChapterPage ParseChapterPage(LoadedHtml document)
    {
        var adapter = _adapters.FirstOrDefault(candidate => candidate.CanHandle(document));
        return adapter?.ParseChapterPage(document)
            ?? throw new NovelParsingException(NovelParsingErrorKind.NoReadableContent);
    }

    public ParsedBookCatalog ParseCatalogPage(LoadedHtml document)
    {
        var adapter = _adapters.FirstOrDefault(candidate => candidate.CanHandle(document));
        return adapter?.ParseCatalogPage(document)
            ?? throw new NovelParsingException(NovelParsingErrorKind.MissingCatalog);
    }
}
