namespace YYReader.Windows.Core.Parsing;

public sealed record ParsedChapterPage(
    string Title,
    string? BookTitle,
    string? Author,
    IReadOnlyList<string> Paragraphs,
    Uri? CatalogUrl,
    Uri? PreviousChapterUrl,
    Uri? NextChapterUrl,
    Uri? NextPageUrl);
