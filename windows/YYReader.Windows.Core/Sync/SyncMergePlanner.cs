namespace YYReader.Windows.Core.Sync;

public static class SyncMergePlanner
{
    public static IReadOnlyList<SyncSnapshotBook> Merge(
        IEnumerable<SyncSnapshotBook> local,
        IEnumerable<SyncSnapshotBook> remote)
    {
        var result = new Dictionary<string, SyncSnapshotBook>(StringComparer.Ordinal);
        foreach (var candidate in local.Concat(remote))
        {
            var key = candidate.CanonicalSourceUrl;
            var normalized = candidate with { SourceUrl = key };
            result[key] = result.TryGetValue(key, out var existing)
                ? MergeBook(existing, normalized)
                : normalized;
        }
        return result.Values.OrderBy(book => book.CanonicalSourceUrl, StringComparer.Ordinal).ToArray();
    }

    private static SyncSnapshotBook MergeBook(SyncSnapshotBook first, SyncSnapshotBook second)
    {
        var metadata = first.UpdatedAt >= second.UpdatedAt ? first : second;
        var progress = CompareNullable(first.LastReadAt, second.LastReadAt) >= 0 ? first : second;
        var deletedAt = Max(first.DeletedAt, second.DeletedAt);
        var newestActiveAt = first.ActiveAt >= second.ActiveAt ? first.ActiveAt : second.ActiveAt;
        return new SyncSnapshotBook
        {
            SourceUrl = first.CanonicalSourceUrl,
            Title = metadata.Title,
            Author = metadata.Author,
            CurrentChapterUrl = progress.CurrentChapterUrl,
            ParagraphIndex = progress.ParagraphIndex,
            Progress = progress.Progress,
            LastReadAt = progress.LastReadAt,
            UpdatedAt = metadata.UpdatedAt,
            DeletedAt = deletedAt is { } deletion && deletion >= newestActiveAt ? deletion : null
        };
    }

    private static int CompareNullable(DateTimeOffset? first, DateTimeOffset? second) =>
        Nullable.Compare(first, second);

    private static DateTimeOffset? Max(DateTimeOffset? first, DateTimeOffset? second) =>
        CompareNullable(first, second) >= 0 ? first : second;
}
