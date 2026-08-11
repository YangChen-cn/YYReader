namespace YYReader.Windows.Core.Models;

public sealed class Chapter
{
    public Chapter(
        string sourceUrl,
        string title,
        int sortIndex,
        string? bodyText = null,
        string? previousUrl = null,
        string? nextUrl = null,
        DateTimeOffset? cachedAt = null,
        int paragraphIndex = 0,
        double progress = 0,
        DateTimeOffset? lastReadAt = null)
    {
        SourceUrl = UrlCanonicalizer.CanonicalizeChapter(sourceUrl).AbsoluteUri;
        Title = title;
        SortIndex = sortIndex;
        BodyText = bodyText is null ? null : ChapterText.NormalizeBodyText(bodyText);
        PreviousUrl = previousUrl;
        NextUrl = nextUrl;
        CachedAt = cachedAt;
        ParagraphIndex = Math.Max(paragraphIndex, 0);
        Progress = Math.Clamp(progress, 0, 1);
        LastReadAt = lastReadAt;
    }

    public string SourceUrl { get; }
    public string Title { get; set; }
    public int SortIndex { get; set; }
    public string? BodyText { get; private set; }
    public string? PreviousUrl { get; set; }
    public string? NextUrl { get; set; }
    public DateTimeOffset? CachedAt { get; private set; }
    public int ParagraphIndex { get; set; }
    public double Progress { get; set; }
    public DateTimeOffset? LastReadAt { get; set; }
    public int ContentRevision { get; private set; }
    public bool IsCached => !string.IsNullOrWhiteSpace(BodyText);
    public IReadOnlyList<string> Paragraphs => ChapterText.ToParagraphs(BodyText);

    public void ReplaceBodyText(string? bodyText, DateTimeOffset? cachedAt = null)
    {
        BodyText = bodyText is null ? null : ChapterText.NormalizeBodyText(bodyText);
        CachedAt = bodyText is null ? null : cachedAt ?? DateTimeOffset.UtcNow;
        ContentRevision++;
    }

    public void MarkUncached()
    {
        BodyText = null;
        CachedAt = null;
        ContentRevision++;
    }

    public void ApplyProgress(int paragraphIndex, int paragraphCount, DateTimeOffset at)
    {
        ParagraphIndex = Math.Max(paragraphIndex, 0);
        Progress = ReaderPosition.ProgressForParagraph(ParagraphIndex, paragraphCount);
        LastReadAt = at;
    }
}
