namespace YYReader.Windows.Core.Parsing;

public sealed record ParsedBookCatalog(
    string Title,
    string Author,
    IReadOnlyList<ChapterSeed> Chapters,
    Uri? NextPageUrl);
