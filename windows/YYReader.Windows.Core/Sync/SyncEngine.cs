namespace YYReader.Windows.Core.Sync;

public sealed class SyncEngine(
    Func<CancellationToken, Task<SyncSnapshot>> buildLocalSnapshot,
    Func<SyncSnapshot, CancellationToken, Task> mergeRemoteSnapshot)
{
    public const string SyncDirectoryName = "YYReaderSync";
    public const string MacFileName = "mac.json";
    public const string WindowsFileName = "windows.json";

    public async Task<SyncSnapshot> SynchronizeAsync(string selectedFolderPath, CancellationToken cancellationToken = default)
    {
        var syncDirectory = ResolveSyncDirectory(selectedFolderPath);
        if (!Directory.Exists(selectedFolderPath)) throw new DirectoryNotFoundException("同步文件夹暂时不可用。");
        Directory.CreateDirectory(syncDirectory);

        var macPath = Path.Combine(syncDirectory, MacFileName);
        if (File.Exists(macPath))
        {
            var json = await ReadWithRetryAsync(macPath, cancellationToken).ConfigureAwait(false);
            var remote = SyncSnapshotCodec.Decode(json);
            if (!string.Equals(remote.Device, "mac", StringComparison.OrdinalIgnoreCase))
            {
                throw new SyncSnapshotException("mac.json 的 device 必须为 mac。");
            }
            await mergeRemoteSnapshot(remote, cancellationToken).ConfigureAwait(false);
        }

        var snapshot = await buildLocalSnapshot(cancellationToken).ConfigureAwait(false);
        await WriteAtomicallyAsync(Path.Combine(syncDirectory, WindowsFileName), SyncSnapshotCodec.Encode(snapshot), cancellationToken)
            .ConfigureAwait(false);
        return snapshot;
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
}
