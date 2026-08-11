using YYReader.Windows.Core.Models;

namespace YYReader.Windows.Core.Sync;

public static class SyncMergePlanner
{
    public static IReadOnlyList<SyncSnapshotBook> Merge(
        IEnumerable<SyncSnapshotBook> local,
        IEnumerable<SyncSnapshotBook> remote,
        IReadOnlyDictionary<string, IReadOnlyDictionary<string, int>>? chapterRanksByBook = null)
    {
        var result = new Dictionary<string, SyncSnapshotBook>(StringComparer.Ordinal);
        foreach (var candidate in local.Concat(remote))
        {
            var key = candidate.CanonicalSourceUrl;
            var normalized = candidate with { SourceUrl = key };
            result[key] = result.TryGetValue(key, out var existing)
                ? MergeBook(existing, normalized, chapterRanksByBook?.GetValueOrDefault(key))
                : normalized;
        }
        return result.Values.OrderBy(book => book.CanonicalSourceUrl, StringComparer.Ordinal).ToArray();
    }

    private static SyncSnapshotBook MergeBook(
        SyncSnapshotBook first,
        SyncSnapshotBook second,
        IReadOnlyDictionary<string, int>? chapterRanks)
    {
        var metadata = MetadataPrecedes(first, second) ? second : first;
        var progress = ReadingPrecedes(first, second, chapterRanks) ? second : first;
        var deletedAt = Max(first.DeletedAt, second.DeletedAt);
        var chapterUrl = progress.CurrentChapterUrl is null
            ? null
            : UrlCanonicalizer.CanonicalizeChapter(progress.CurrentChapterUrl).AbsoluteUri;
        return new SyncSnapshotBook
        {
            SourceUrl = first.CanonicalSourceUrl,
            Title = metadata.Title,
            Author = metadata.Author,
            CurrentChapterUrl = chapterUrl,
            CurrentChapterIndex = progress.CurrentChapterIndex ?? EffectiveChapterIndex(progress, chapterRanks),
            ParagraphIndex = progress.ParagraphIndex,
            Progress = progress.Progress,
            LastReadAt = Max(first.LastReadAt, second.LastReadAt),
            UpdatedAt = metadata.UpdatedAt,
            DeletedAt = deletedAt is { } deletion && deletion >= metadata.UpdatedAt ? deletion : null
        };
    }

    private static bool MetadataPrecedes(SyncSnapshotBook first, SyncSnapshotBook second)
    {
        if (first.UpdatedAt != second.UpdatedAt) return first.UpdatedAt < second.UpdatedAt;
        return string.CompareOrdinal(MetadataTieBreaker(first), MetadataTieBreaker(second)) < 0;
    }

    private static bool ReadingPrecedes(
        SyncSnapshotBook first,
        SyncSnapshotBook second,
        IReadOnlyDictionary<string, int>? chapterRanks)
    {
        var firstUrl = CanonicalChapterUrl(first.CurrentChapterUrl);
        var secondUrl = CanonicalChapterUrl(second.CurrentChapterUrl);
        if (firstUrl == secondUrl)
        {
            var firstParagraph = first.ParagraphIndex ?? -1;
            var secondParagraph = second.ParagraphIndex ?? -1;
            if (firstParagraph != secondParagraph) return firstParagraph < secondParagraph;
            var firstProgress = first.Progress ?? -1;
            var secondProgress = second.Progress ?? -1;
            if (firstProgress != secondProgress) return firstProgress < secondProgress;
        }
        else
        {
            var firstIndex = EffectiveChapterIndex(first, chapterRanks);
            var secondIndex = EffectiveChapterIndex(second, chapterRanks);
            if (firstIndex != secondIndex) return firstIndex < secondIndex;
        }
        return string.CompareOrdinal(ReadingTieBreaker(first), ReadingTieBreaker(second)) < 0;
    }

    private static int EffectiveChapterIndex(
        SyncSnapshotBook record,
        IReadOnlyDictionary<string, int>? chapterRanks)
    {
        if (record.CurrentChapterIndex is { } index) return index;
        var url = CanonicalChapterUrl(record.CurrentChapterUrl);
        return url is not null && chapterRanks?.TryGetValue(url, out var rank) == true ? rank : -1;
    }

    private static string? CanonicalChapterUrl(string? value) => value is null
        ? null
        : UrlCanonicalizer.CanonicalizeChapter(value).AbsoluteUri;

    private static string ReadingTieBreaker(SyncSnapshotBook record) =>
        $"{record.CurrentChapterUrl}\0{record.CurrentChapterIndex ?? -1}\0{record.ParagraphIndex}\0{record.Progress}";

    private static string MetadataTieBreaker(SyncSnapshotBook record) =>
        $"{record.Title}\0{record.Author}\0{record.SourceUrl}";

    private static int CompareNullable(DateTimeOffset? first, DateTimeOffset? second) =>
        Nullable.Compare(first, second);

    private static DateTimeOffset? Max(DateTimeOffset? first, DateTimeOffset? second) =>
        CompareNullable(first, second) >= 0 ? first : second;
}
