namespace YYReader.Windows.Core.Parsing;

public sealed record ChapterLoadResult(
    string Title,
    string? BookTitle,
    string? Author,
    Uri? CatalogUrl,
    Uri ChapterUrl,
    string BodyText,
    Uri? PreviousChapterUrl,
    Uri? NextChapterUrl);
