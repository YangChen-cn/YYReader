using Microsoft.UI.Dispatching;
using YYReader.Windows.Core.Persistence;
using YYReader.Windows.Core.Sync;

namespace YYReader.Windows.Services;

public sealed record FolderSyncState(
    bool IsSyncing = false,
    DateTimeOffset? LastSyncAt = null,
    string? ErrorMessage = null);

public sealed class FolderSyncService : IAsyncDisposable
{
    private readonly SqliteLibraryRepository _repository;
    private readonly LibraryStore _store;
    private readonly DispatcherQueue _dispatcherQueue;
    private readonly Func<Task> _remoteChangesApplied;
    private readonly FolderSyncPreferencesStore _preferencesStore = new();
    private readonly SemaphoreSlim _syncGate = new(1, 1);
    private readonly CancellationTokenSource _lifetimeCancellation = new();
    private readonly Timer _pollTimer;
    private CancellationTokenSource? _debounceCancellation;
    private FileSystemWatcher? _watcher;
    private DateTime _observedMacWriteTimeUtc;
    private bool _disposed;
    private bool _suppressScheduling;

    public FolderSyncService(
        SqliteLibraryRepository repository,
        LibraryStore store,
        DispatcherQueue dispatcherQueue,
        Func<Task> remoteChangesApplied)
    {
        _repository = repository;
        _store = store;
        _dispatcherQueue = dispatcherQueue;
        _remoteChangesApplied = remoteChangesApplied;
        Engine = new SyncEngine(
            token => _repository.BuildSyncSnapshotAsync("windows", token),
            async (snapshot, token) => _remoteChangedDuringSync = await _repository.ApplySyncSnapshotAsync(snapshot, token));
        _pollTimer = new Timer(_ => Poll(), null, Timeout.Infinite, Timeout.Infinite);
        _store.PropertyChanged += StoreChanged;
        _store.BooksChanged += StoreBooksChanged;
    }

    private bool _remoteChangedDuringSync;
    public SyncEngine Engine { get; }
    public FolderSyncPreferences Preferences { get; private set; } = new();
    public FolderSyncState State { get; private set; } = new();
    public event EventHandler<FolderSyncState>? StateChanged;

    public async Task InitializeAsync(CancellationToken cancellationToken = default)
    {
        Preferences = await _preferencesStore.LoadAsync(cancellationToken);
        ConfigureWatcher();
        _pollTimer.Change(TimeSpan.FromMinutes(1), TimeSpan.FromMinutes(1));
        if (Preferences.IsEnabled) ScheduleSync(TimeSpan.Zero);
    }

    public async Task ConfigureAsync(bool enabled, string? folderPath, CancellationToken cancellationToken = default)
    {
        Preferences = Preferences with
        {
            IsEnabled = enabled,
            FolderPath = string.IsNullOrWhiteSpace(folderPath) ? null : Path.GetFullPath(folderPath)
        };
        await _preferencesStore.SaveAsync(Preferences, cancellationToken);
        ConfigureWatcher();
        if (enabled) ScheduleSync(TimeSpan.Zero);
    }

    public void OnAppActivated()
    {
        if (Preferences.IsEnabled) ScheduleSync(TimeSpan.Zero);
    }

    public void ScheduleSync(TimeSpan? delay = null)
    {
        if (_disposed || !Preferences.IsEnabled || string.IsNullOrWhiteSpace(Preferences.FolderPath)) return;
        _debounceCancellation?.Cancel();
        _debounceCancellation?.Dispose();
        var cancellation = new CancellationTokenSource();
        _debounceCancellation = cancellation;
        _ = SynchronizeAfterDelayAsync(delay ?? TimeSpan.FromMilliseconds(1500), cancellation);
    }

    public async Task SynchronizeNowAsync(CancellationToken cancellationToken = default)
    {
        if (!Preferences.IsEnabled || string.IsNullOrWhiteSpace(Preferences.FolderPath)) return;
        using var linkedCancellation = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken, _lifetimeCancellation.Token);
        var operationToken = linkedCancellation.Token;
        if (!await _syncGate.WaitAsync(0, operationToken)) return;
        try
        {
            UpdateState(new(true, Preferences.LastSyncAt));
            await RunOnUiThreadAsync(() => _store.FlushPendingProgressAsync(operationToken));
            _remoteChangedDuringSync = false;
            await Engine.SynchronizeAsync(Preferences.FolderPath, operationToken);
            var now = DateTimeOffset.UtcNow;
            Preferences = Preferences with { LastSyncAt = now };
            await _preferencesStore.SaveAsync(Preferences, operationToken);
            UpdateObservedMacWriteTime();
            if (_remoteChangedDuringSync)
            {
                _suppressScheduling = true;
                try { await RunOnUiThreadAsync(_remoteChangesApplied); }
                finally { _suppressScheduling = false; }
            }
            UpdateState(new(false, now));
        }
        catch (OperationCanceledException)
        {
            UpdateState(new(false, Preferences.LastSyncAt));
        }
        catch (Exception exception)
        {
            UpdateState(new(false, Preferences.LastSyncAt, exception.Message));
        }
        finally
        {
            _syncGate.Release();
        }
    }

    private async Task SynchronizeAfterDelayAsync(TimeSpan delay, CancellationTokenSource scheduled)
    {
        try
        {
            await Task.Delay(delay, scheduled.Token);
            if (ReferenceEquals(_debounceCancellation, scheduled))
            {
                _debounceCancellation = null;
                await SynchronizeNowAsync(scheduled.Token);
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

    private void MacSnapshotChanged(object sender, FileSystemEventArgs e) => ScheduleSync();

    private void Poll()
    {
        if (!Preferences.IsEnabled || string.IsNullOrWhiteSpace(Preferences.FolderPath)) return;
        try
        {
            if (_watcher is null) ConfigureWatcher();
            var path = Path.Combine(SyncEngine.ResolveSyncDirectory(Preferences.FolderPath), SyncEngine.MacFileName);
            var writeTime = File.Exists(path) ? File.GetLastWriteTimeUtc(path) : DateTime.MinValue;
            if (writeTime > _observedMacWriteTimeUtc) ScheduleSync(TimeSpan.Zero);
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
        _observedMacWriteTimeUtc = File.Exists(path) ? File.GetLastWriteTimeUtc(path) : DateTime.MinValue;
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

    private void StoreChanged(object? sender, System.ComponentModel.PropertyChangedEventArgs e)
    {
        if (!_suppressScheduling) ScheduleSync();
    }

    private void StoreBooksChanged(object? sender, EventArgs e)
    {
        if (!_suppressScheduling) ScheduleSync();
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
        _store.PropertyChanged -= StoreChanged;
        _store.BooksChanged -= StoreBooksChanged;
        _debounceCancellation?.Cancel();
        _debounceCancellation?.Dispose();
        _watcher?.Dispose();
        _pollTimer.Dispose();
        _lifetimeCancellation.Cancel();
        await _syncGate.WaitAsync();
        _syncGate.Release();
        _syncGate.Dispose();
        _lifetimeCancellation.Dispose();
    }
}
