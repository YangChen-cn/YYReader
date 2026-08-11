namespace YYReader.Windows.Core.Models;

public sealed class Book
{
    public Book(
        string id,
        string sourceBookUrl,
        string catalogUrl,
        string title,
        string author,
        string sourceHost,
        bool hasCatalog,
        DateTimeOffset createdAt,
        DateTimeOffset updatedAt,
        DateTimeOffset? catalogFetchedAt = null,
        string? currentChapterUrl = null)
    {
        Id = id;
        SourceBookUrl = sourceBookUrl;
        CatalogUrl = catalogUrl;
        Title = title;
        Author = author;
        SourceHost = sourceHost;
        HasCatalog = hasCatalog;
        CreatedAt = createdAt;
        UpdatedAt = updatedAt;
        CatalogFetchedAt = catalogFetchedAt;
        CurrentChapterUrl = currentChapterUrl;
    }

    public string Id { get; }
    public string SourceBookUrl { get; set; }
    public string CatalogUrl { get; set; }
    public string Title { get; set; }
    public string Author { get; set; }
    public string SourceHost { get; set; }
    public bool HasCatalog { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }
    public DateTimeOffset? CatalogFetchedAt { get; set; }
    public string? CurrentChapterUrl { get; set; }
    public List<Chapter> Chapters { get; } = new();

    public Chapter? CurrentChapter =>
        CurrentChapterUrl is null
            ? Chapters.OrderBy(chapter => chapter.SortIndex).FirstOrDefault()
            : Chapters.FirstOrDefault(chapter =>
                UrlCanonicalizer.CanonicalizeChapter(chapter.SourceUrl).AbsoluteUri
                == UrlCanonicalizer.CanonicalizeChapter(CurrentChapterUrl).AbsoluteUri)
                ?? Chapters.OrderBy(chapter => chapter.SortIndex).FirstOrDefault();

    public double CurrentProgress => CurrentChapter?.Progress ?? 0;

    public string CurrentChapterTitle => CurrentChapter?.Title ?? "尚未开始";

    public string ProgressDisplay => $"{CurrentProgress:P0}";

    public string LastReadDisplay => LastReadAt is { } value
        ? value.ToLocalTime().ToString("yyyy-MM-dd HH:mm")
        : "尚未阅读";

    public DateTimeOffset? LastReadAt => CurrentChapter?.LastReadAt;
}
