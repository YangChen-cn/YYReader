namespace YYReader.Windows.Core.Parsing;

public sealed record NovelImportResult(
    string BookTitle,
    string Author,
    Uri SourceBookUrl,
    Uri CatalogUrl,
    bool HasCatalog,
    IReadOnlyList<ChapterSeed> Catalog,
    bool CatalogIsComplete,
    string ChapterTitle,
    Uri ChapterUrl,
    string BodyText,
    Uri? PreviousChapterUrl,
    Uri? NextChapterUrl);
