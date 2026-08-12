namespace YYReader.Windows.Core.Sync;

public sealed class SyncEngine(
    Func<CancellationToken, Task<SyncSnapshot>> buildLocalSnapshot,
    Func<SyncSnapshot, CancellationToken, Task<SyncApplicationResult>> mergeRemoteSnapshot)
{
    public const string SyncDirectoryName = "YYReaderSync";
    public const string MacFileName = "mac.json";
    public const string WindowsFileName = "windows.json";

    public async Task<SyncExecutionResult> SynchronizeAsync(string selectedFolderPath, CancellationToken cancellationToken = default)
    {
        var syncDirectory = EnsureSyncDirectory(selectedFolderPath);

        var macPath = Path.Combine(syncDirectory, MacFileName);
        var application = SyncApplicationResult.None;
        if (File.Exists(macPath))
        {
            var json = await ReadWithRetryAsync(macPath, cancellationToken).ConfigureAwait(false);
            var remote = SyncSnapshotCodec.Decode(json);
            if (!string.Equals(remote.Device, "mac", StringComparison.OrdinalIgnoreCase))
            {
                throw new SyncSnapshotException("mac.json 的 device 必须为 mac。");
            }
            application = await mergeRemoteSnapshot(remote, cancellationToken).ConfigureAwait(false);
        }

        var published = await PublishLocalCoreAsync(syncDirectory, cancellationToken).ConfigureAwait(false);
        return published with { Application = application };
    }

    public async Task<SyncExecutionResult> PublishLocalAsync(
        string selectedFolderPath,
        CancellationToken cancellationToken = default)
    {
        var syncDirectory = EnsureSyncDirectory(selectedFolderPath);
        return await PublishLocalCoreAsync(syncDirectory, cancellationToken).ConfigureAwait(false);
    }

    private async Task<SyncExecutionResult> PublishLocalCoreAsync(
        string syncDirectory,
        CancellationToken cancellationToken)
    {
        var built = await buildLocalSnapshot(cancellationToken).ConfigureAwait(false);
        var snapshot = new SyncSnapshot
        {
            Device = "windows",
            UpdatedAt = built.UpdatedAt,
            Books = SyncMergePlanner.Merge(built.Books, []).ToList()
        };
        var windowsPath = Path.Combine(syncDirectory, WindowsFileName);
        var shouldWrite = true;
        if (File.Exists(windowsPath))
        {
            try
            {
                var existing = SyncSnapshotCodec.Decode(await ReadWithRetryAsync(windowsPath, cancellationToken).ConfigureAwait(false));
                shouldWrite = existing.Version != SyncSnapshotCodec.Version
                    || !string.Equals(existing.Device, "windows", StringComparison.OrdinalIgnoreCase)
                    || !BooksAreEquivalent(existing.Books, snapshot.Books);
            }
            catch (SyncSnapshotException)
            {
                // Repair an invalid file owned by this client with the current local snapshot.
            }
        }
        if (shouldWrite)
        {
            await WriteAtomicallyAsync(windowsPath, SyncSnapshotCodec.Encode(snapshot), cancellationToken).ConfigureAwait(false);
        }
        return new SyncExecutionResult(snapshot, SyncApplicationResult.None, shouldWrite);
    }

    private static string EnsureSyncDirectory(string selectedFolderPath)
    {
        if (!Directory.Exists(selectedFolderPath)) throw new DirectoryNotFoundException("同步文件夹暂时不可用。");
        var syncDirectory = ResolveSyncDirectory(selectedFolderPath);
        Directory.CreateDirectory(syncDirectory);
        return syncDirectory;
    }

    public static string ResolveSyncDirectory(string selectedFolderPath) =>
        string.Equals(new DirectoryInfo(selectedFolderPath).Name, SyncDirectoryName, StringComparison.OrdinalIgnoreCase)
            ? Path.GetFullPath(selectedFolderPath)
            : Path.Combine(Path.GetFullPath(selectedFolderPath), SyncDirectoryName);

    private static async Task<string> ReadWithRetryAsync(string path, CancellationToken cancellationToken)
    {
        try
        {
            return await File.ReadAllTextAsync(path, cancellationToken).ConfigureAwait(false);
        }
        catch (IOException)
        {
            await Task.Delay(400, cancellationToken).ConfigureAwait(false);
            return await File.ReadAllTextAsync(path, cancellationToken).ConfigureAwait(false);
        }
    }

    private static async Task WriteAtomicallyAsync(string path, string contents, CancellationToken cancellationToken)
    {
        var temporaryPath = Path.Combine(Path.GetDirectoryName(path)!, $".{Path.GetFileName(path)}.{Guid.NewGuid():N}.tmp");
        try
        {
            await File.WriteAllTextAsync(temporaryPath, contents, cancellationToken).ConfigureAwait(false);
            if (File.Exists(path)) File.Replace(temporaryPath, path, null, ignoreMetadataErrors: true);
            else File.Move(temporaryPath, path);
        }
        finally
        {
            if (File.Exists(temporaryPath)) File.Delete(temporaryPath);
        }
    }

    private static bool BooksAreEquivalent(
        IReadOnlyCollection<SyncSnapshotBook> first,
        IReadOnlyCollection<SyncSnapshotBook> second)
    {
        var left = SyncMergePlanner.Merge(first, []);
        var right = SyncMergePlanner.Merge(second, []);
        if (left.Count != right.Count) return false;
        for (var index = 0; index < left.Count; index++)
        {
            var a = left[index];
            var b = right[index];
            if (a.CanonicalSourceUrl != b.CanonicalSourceUrl
                || a.Title != b.Title
                || a.Author != b.Author
                || a.CurrentChapterUrl != b.CurrentChapterUrl
                || a.CurrentChapterIndex != b.CurrentChapterIndex
                || a.ParagraphIndex != b.ParagraphIndex
                || a.Progress != b.Progress
                || a.LastReadAt != b.LastReadAt
                || a.UpdatedAt != b.UpdatedAt
                || a.DeletedAt != b.DeletedAt)
            {
                return false;
            }
        }
        return true;
    }
}

public sealed record SyncApplicationResult(bool Changed)
{
    public static SyncApplicationResult None { get; } = new(false);
}

public sealed record SyncExecutionResult(
    SyncSnapshot Snapshot,
    SyncApplicationResult Application,
    bool WindowsFileWritten);
