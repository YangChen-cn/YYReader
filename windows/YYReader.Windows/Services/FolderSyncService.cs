using Microsoft.UI.Dispatching;
using YYReader.Windows.Core.Persistence;
using YYReader.Windows.Core.Sync;

namespace YYReader.Windows.Services;

public sealed record FolderSyncState(
    bool IsSyncing = false,
    DateTimeOffset? LastSyncAt = null,
    string? ErrorMessage = null,
    bool ShouldNotify = false);

public sealed class FolderSyncService : IAsyncDisposable
{
    private readonly SqliteLibraryRepository _repository;
    private readonly LibraryStore _store;
    private readonly DispatcherQueue _dispatcherQueue;
    private readonly Func<IReadOnlyList<string>, Task> _remoteChangesApplied;
    private readonly FolderSyncPreferencesStore _preferencesStore = new();
    private readonly SemaphoreSlim _syncGate = new(1, 1);
    private readonly CancellationTokenSource _lifetimeCancellation = new();
    private readonly Timer _pollTimer;
    private CancellationTokenSource? _localDebounceCancellation;
    private CancellationTokenSource? _remoteDebounceCancellation;
    private FileSystemWatcher? _watcher;
    private DateTime _observedMacWriteTimeUtc;
    private long _observedMacLength = -1;
    private bool _disposed;
    private bool _suppressScheduling;

    public FolderSyncService(
        SqliteLibraryRepository repository,
        LibraryStore store,
        DispatcherQueue dispatcherQueue,
        Func<IReadOnlyList<string>, Task> remoteChangesApplied)
    {
        _repository = repository;
        _store = store;
        _dispatcherQueue = dispatcherQueue;
        _remoteChangesApplied = remoteChangesApplied;
        Engine = new SyncEngine(
            token => _repository.BuildSyncSnapshotAsync("windows", token),
            (snapshot, token) => _repository.ApplySyncSnapshotAsync(snapshot, token));
        _pollTimer = new Timer(_ => Poll(), null, Timeout.Infinite, Timeout.Infinite);
        _store.BooksChanged += StoreBooksChanged;
        _store.ProgressPersisted += StoreProgressPersisted;
    }

    public SyncEngine Engine { get; }
    public FolderSyncPreferences Preferences { get; private set; } = new();
    public FolderSyncState State { get; private set; } = new();
    public event EventHandler<FolderSyncState>? StateChanged;

    public async Task InitializeAsync(CancellationToken cancellationToken = default)
    {
        Preferences = await _preferencesStore.LoadAsync(cancellationToken);
        await Task.Run(ConfigureWatcher, cancellationToken).ConfigureAwait(false);
        _pollTimer.Change(TimeSpan.FromMinutes(1), TimeSpan.FromMinutes(1));
        if (Preferences.IsEnabled) ScheduleRemoteSync(TimeSpan.Zero, onlyIfMacChanged: false);
    }

    public async Task ConfigureAsync(bool enabled, string? folderPath, CancellationToken cancellationToken = default)
    {
        Preferences = Preferences with
        {
            IsEnabled = enabled,
            FolderPath = string.IsNullOrWhiteSpace(folderPath) ? null : Path.GetFullPath(folderPath)
        };
        await _preferencesStore.SaveAsync(Preferences, cancellationToken);
        await Task.Run(ConfigureWatcher, cancellationToken).ConfigureAwait(false);
        if (enabled) ScheduleRemoteSync(TimeSpan.Zero, onlyIfMacChanged: false);
    }

    public void OnAppActivated()
    {
        if (!Preferences.IsEnabled) return;
        ScheduleLocalPublish(TimeSpan.Zero);
        ScheduleRemoteSync(TimeSpan.Zero, onlyIfMacChanged: true);
    }

    private void ScheduleLocalPublish(TimeSpan? delay = null)
    {
        if (_disposed || !Preferences.IsEnabled || string.IsNullOrWhiteSpace(Preferences.FolderPath)) return;
        _localDebounceCancellation?.Cancel();
        _localDebounceCancellation?.Dispose();
        var cancellation = new CancellationTokenSource();
        _localDebounceCancellation = cancellation;
        _ = PublishLocalAfterDelayAsync(delay ?? TimeSpan.FromMilliseconds(1500), cancellation);
    }

    private void ScheduleRemoteSync(TimeSpan? delay = null, bool onlyIfMacChanged = true)
    {
        if (_disposed || !Preferences.IsEnabled || string.IsNullOrWhiteSpace(Preferences.FolderPath)) return;
        _remoteDebounceCancellation?.Cancel();
        _remoteDebounceCancellation?.Dispose();
        var cancellation = new CancellationTokenSource();
        _remoteDebounceCancellation = cancellation;
        _ = SynchronizeRemoteAfterDelayAsync(
            delay ?? TimeSpan.FromMilliseconds(350),
            onlyIfMacChanged,
            cancellation);
    }

    public Task SynchronizeNowAsync(CancellationToken cancellationToken = default) =>
        SynchronizeRemoteCoreAsync(userInitiated: true, cancellationToken);

    private async Task SynchronizeRemoteCoreAsync(bool userInitiated, CancellationToken cancellationToken = default)
    {
        if (!Preferences.IsEnabled || string.IsNullOrWhiteSpace(Preferences.FolderPath)) return;
        using var linkedCancellation = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken, _lifetimeCancellation.Token);
        var operationToken = linkedCancellation.Token;
        await _syncGate.WaitAsync(operationToken).ConfigureAwait(false);
        try
        {
            UpdateState(new(true, Preferences.LastSyncAt, ShouldNotify: userInitiated));
            _suppressScheduling = true;
            try { await RunOnUiThreadAsync(() => _store.FlushPendingProgressAsync(operationToken)); }
            finally { _suppressScheduling = false; }
            var result = await Task.Run(
                () => Engine.SynchronizeAsync(Preferences.FolderPath, operationToken),
                operationToken).ConfigureAwait(false);
            var now = DateTimeOffset.UtcNow;
            Preferences = Preferences with { LastSyncAt = now };
            await _preferencesStore.SaveAsync(Preferences, operationToken);
            UpdateObservedMacWriteTime();
            if (result.Application.Changed || result.Application.CatalogRefreshSourceUrls.Count > 0)
            {
                _suppressScheduling = true;
                try { await RunOnUiThreadAsync(() => _remoteChangesApplied(result.Application.CatalogRefreshSourceUrls)); }
                finally { _suppressScheduling = false; }
            }
            UpdateState(new(false, now, ShouldNotify: userInitiated || result.Application.Changed));
        }
        catch (OperationCanceledException)
        {
            UpdateState(new(false, Preferences.LastSyncAt, ShouldNotify: userInitiated));
        }
        catch (Exception exception)
        {
            UpdateState(new(false, Preferences.LastSyncAt, exception.Message, ShouldNotify: true));
        }
        finally
        {
            _syncGate.Release();
        }
    }

    private async Task PublishLocalCoreAsync(CancellationToken cancellationToken)
    {
        if (!Preferences.IsEnabled || string.IsNullOrWhiteSpace(Preferences.FolderPath)) return;
        using var linkedCancellation = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken, _lifetimeCancellation.Token);
        await _syncGate.WaitAsync(linkedCancellation.Token).ConfigureAwait(false);
        try
        {
            _suppressScheduling = true;
            try { await RunOnUiThreadAsync(() => _store.FlushPendingProgressAsync(linkedCancellation.Token)); }
            finally { _suppressScheduling = false; }
            await Task.Run(
                () => Engine.PublishLocalAsync(Preferences.FolderPath, linkedCancellation.Token),
                linkedCancellation.Token).ConfigureAwait(false);
        }
        catch (OperationCanceledException)
        {
        }
        catch (Exception exception)
        {
            UpdateState(new(false, Preferences.LastSyncAt, exception.Message, ShouldNotify: true));
        }
        finally
        {
            _syncGate.Release();
        }
    }

    private async Task PublishLocalAfterDelayAsync(TimeSpan delay, CancellationTokenSource scheduled)
    {
        try
        {
            await Task.Delay(delay, scheduled.Token).ConfigureAwait(false);
            if (ReferenceEquals(_localDebounceCancellation, scheduled))
            {
                _localDebounceCancellation = null;
                await PublishLocalCoreAsync(scheduled.Token);
            }
        }
        catch (OperationCanceledException)
        {
        }
        finally
        {
            scheduled.Dispose();
        }
    }

    private async Task SynchronizeRemoteAfterDelayAsync(
        TimeSpan delay,
        bool onlyIfMacChanged,
        CancellationTokenSource scheduled)
    {
        try
        {
            await Task.Delay(delay, scheduled.Token).ConfigureAwait(false);
            if (!ReferenceEquals(_remoteDebounceCancellation, scheduled)) return;
            _remoteDebounceCancellation = null;
            if (onlyIfMacChanged && !MacSnapshotSignatureChanged()) return;
            await SynchronizeRemoteCoreAsync(userInitiated: false, scheduled.Token);
        }
        catch (OperationCanceledException)
        {
        }
        finally
        {
            scheduled.Dispose();
        }
    }

    private void ConfigureWatcher()
    {
        _watcher?.Dispose();
        _watcher = null;
        if (!Preferences.IsEnabled || string.IsNullOrWhiteSpace(Preferences.FolderPath)) return;
        try
        {
            var syncDirectory = SyncEngine.ResolveSyncDirectory(Preferences.FolderPath);
            Directory.CreateDirectory(syncDirectory);
            _watcher = new FileSystemWatcher(syncDirectory, SyncEngine.MacFileName)
            {
                NotifyFilter = NotifyFilters.LastWrite | NotifyFilters.FileName | NotifyFilters.Size,
                EnableRaisingEvents = true
            };
            _watcher.Changed += MacSnapshotChanged;
            _watcher.Created += MacSnapshotChanged;
            _watcher.Renamed += MacSnapshotChanged;
            UpdateObservedMacWriteTime();
        }
        catch (Exception exception)
        {
            UpdateState(new(false, Preferences.LastSyncAt, exception.Message));
        }
    }

    private void MacSnapshotChanged(object sender, FileSystemEventArgs e) =>
        ScheduleRemoteSync(onlyIfMacChanged: true);

    private void Poll()
    {
        if (!Preferences.IsEnabled || string.IsNullOrWhiteSpace(Preferences.FolderPath)) return;
        try
        {
            if (_watcher is null) ConfigureWatcher();
            var path = Path.Combine(SyncEngine.ResolveSyncDirectory(Preferences.FolderPath), SyncEngine.MacFileName);
            if (!File.Exists(path)) return;
            var info = new FileInfo(path);
            if (info.LastWriteTimeUtc != _observedMacWriteTimeUtc || info.Length != _observedMacLength)
            {
                ScheduleRemoteSync(TimeSpan.Zero, onlyIfMacChanged: true);
            }
        }
        catch
        {
            // Polling is only a fallback. The next activation or poll retries.
        }
    }

    private void UpdateObservedMacWriteTime()
    {
        if (string.IsNullOrWhiteSpace(Preferences.FolderPath)) return;
        var path = Path.Combine(SyncEngine.ResolveSyncDirectory(Preferences.FolderPath), SyncEngine.MacFileName);
        if (!File.Exists(path))
        {
            _observedMacWriteTimeUtc = DateTime.MinValue;
            _observedMacLength = -1;
            return;
        }
        var info = new FileInfo(path);
        _observedMacWriteTimeUtc = info.LastWriteTimeUtc;
        _observedMacLength = info.Length;
    }

    private bool MacSnapshotSignatureChanged()
    {
        if (string.IsNullOrWhiteSpace(Preferences.FolderPath)) return false;
        var path = Path.Combine(SyncEngine.ResolveSyncDirectory(Preferences.FolderPath), SyncEngine.MacFileName);
        if (!File.Exists(path)) return false;
        var info = new FileInfo(path);
        return info.LastWriteTimeUtc != _observedMacWriteTimeUtc || info.Length != _observedMacLength;
    }

    private Task RunOnUiThreadAsync(Func<Task> operation)
    {
        if (_dispatcherQueue.HasThreadAccess) return operation();
        var completion = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        if (!_dispatcherQueue.TryEnqueue(async () =>
        {
            try { await operation(); completion.TrySetResult(); }
            catch (Exception exception) { completion.TrySetException(exception); }
        }))
        {
            completion.TrySetException(new InvalidOperationException("无法切换到 UI 线程应用同步结果。"));
        }
        return completion.Task;
    }

    private void StoreBooksChanged(object? sender, EventArgs e)
    {
        if (!_suppressScheduling) ScheduleLocalPublish();
    }

    private void StoreProgressPersisted(object? sender, EventArgs e)
    {
        if (!_suppressScheduling) ScheduleLocalPublish();
    }

    private void UpdateState(FolderSyncState state)
    {
        State = state;
        StateChanged?.Invoke(this, state);
    }

    public async ValueTask DisposeAsync()
    {
        if (_disposed) return;
        _disposed = true;
        _store.BooksChanged -= StoreBooksChanged;
        _store.ProgressPersisted -= StoreProgressPersisted;
        _localDebounceCancellation?.Cancel();
        _localDebounceCancellation?.Dispose();
        _remoteDebounceCancellation?.Cancel();
        _remoteDebounceCancellation?.Dispose();
        _watcher?.Dispose();
        _pollTimer.Dispose();
        _lifetimeCancellation.Cancel();
        // A disconnected cloud provider can leave a Windows file-system call blocked in
        // native code, where CancellationToken cannot interrupt it. Never hold app shutdown
        // hostage to that operation. The process will reclaim the gate if it is still busy.
        if (await _syncGate.WaitAsync(TimeSpan.FromSeconds(1)).ConfigureAwait(false))
        {
            _syncGate.Release();
            _syncGate.Dispose();
        }
        _lifetimeCancellation.Dispose();
    }
}
