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
    private readonly Func<Task> _remoteChangesApplied;
    private readonly FolderSyncPreferencesStore _preferencesStore = new();
    private static readonly TimeSpan SyncWatchdogTimeout = TimeSpan.FromSeconds(10);
    private static readonly TimeSpan ProbeBackoff = TimeSpan.FromMinutes(3);
    private readonly RecoverableSyncWatchdog _syncWatchdog = new();
    private readonly SingleFlightProbeGuard _probeGuard = new();
    private readonly CancellationTokenSource _lifetimeCancellation = new();
    private readonly Timer _pollTimer;
    private CancellationTokenSource? _localDebounceCancellation;
    private CancellationTokenSource? _remoteDebounceCancellation;
    private FileSystemWatcher? _watcher;
    private readonly object _signatureLock = new();
    private DateTime _observedMacWriteTimeUtc;
    private long _observedMacLength = -1;
    private bool _disposed;
    private bool _suppressScheduling;
    private int _forceRemoteRetry;

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
            (snapshot, token) => _repository.ApplySyncSnapshotAsync(snapshot, token));
        _pollTimer = new Timer(_ => QueuePoll(), null, Timeout.Infinite, Timeout.Infinite);
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
        await ConfigureWatcherAsync(bypassBackoff: false, cancellationToken).ConfigureAwait(false);
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
        await ConfigureWatcherAsync(bypassBackoff: true, cancellationToken).ConfigureAwait(false);
        if (enabled) ScheduleRemoteSync(TimeSpan.Zero, onlyIfMacChanged: false);
    }

    public void OnAppActivated()
    {
        if (!Preferences.IsEnabled) return;
        ScheduleRemoteSync(TimeSpan.Zero, onlyIfMacChanged: true);
        // A full remote synchronization also publishes the local snapshot. Keep the separate
        // local publish debounce as a fallback without racing it for the recoverable gate.
        ScheduleLocalPublish();
    }

    private void ScheduleLocalPublish(TimeSpan? delay = null)
    {
        if (_disposed || !Preferences.IsEnabled || string.IsNullOrWhiteSpace(Preferences.FolderPath)) return;
        _localDebounceCancellation?.Cancel();
        _localDebounceCancellation?.Dispose();
        var cancellation = new CancellationTokenSource();
        _localDebounceCancellation = cancellation;
        _ = Task.Run(
            () => PublishLocalAfterDelayAsync(delay ?? TimeSpan.FromMilliseconds(1500), cancellation));
    }

    private void ScheduleRemoteSync(TimeSpan? delay = null, bool onlyIfMacChanged = true)
    {
        if (_disposed || !Preferences.IsEnabled || string.IsNullOrWhiteSpace(Preferences.FolderPath)) return;
        _remoteDebounceCancellation?.Cancel();
        _remoteDebounceCancellation?.Dispose();
        var cancellation = new CancellationTokenSource();
        _remoteDebounceCancellation = cancellation;
        _ = Task.Run(
            () => SynchronizeRemoteAfterDelayAsync(
                delay ?? TimeSpan.FromMilliseconds(350),
                onlyIfMacChanged,
                cancellation));
    }

    public Task SynchronizeNowAsync(CancellationToken cancellationToken = default) =>
        SynchronizeRemoteCoreAsync(userInitiated: true, cancellationToken);

    private async Task SynchronizeRemoteCoreAsync(bool userInitiated, CancellationToken cancellationToken = default)
    {
        if (!Preferences.IsEnabled || string.IsNullOrWhiteSpace(Preferences.FolderPath)) return;
        using var linkedCancellation = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken, _lifetimeCancellation.Token);
        var operationToken = linkedCancellation.Token;
        try
        {
            UpdateState(new(true, Preferences.LastSyncAt, ShouldNotify: userInitiated));
            _suppressScheduling = true;
            try { await RunOnUiThreadAsync(() => _store.FlushPendingProgressAsync(operationToken)); }
            finally { _suppressScheduling = false; }
            var watched = await _syncWatchdog.RunAsync(
                token => Task.Run(() => Engine.SynchronizeAsync(Preferences.FolderPath, token), token),
                SyncWatchdogTimeout,
                operationToken).ConfigureAwait(false);
            if (watched.Status == WatchdogStatus.Busy)
            {
                UpdateState(new(false, Preferences.LastSyncAt, ShouldNotify: userInitiated));
                return;
            }
            if (watched.Status == WatchdogStatus.TimedOut)
            {
                MarkFolderTemporarilyUnavailable();
                return;
            }

            var result = watched.Value!;
            Interlocked.Exchange(ref _forceRemoteRetry, 0);
            var now = DateTimeOffset.UtcNow;
            Preferences = Preferences with { LastSyncAt = now };
            await _preferencesStore.SaveAsync(Preferences, operationToken);
            await UpdateObservedMacWriteTimeAsync(operationToken).ConfigureAwait(false);
            if (result.Application.Changed)
            {
                _suppressScheduling = true;
                try { await RunOnUiThreadAsync(_remoteChangesApplied); }
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
    }

    private async Task PublishLocalCoreAsync(CancellationToken cancellationToken)
    {
        if (!Preferences.IsEnabled || string.IsNullOrWhiteSpace(Preferences.FolderPath)) return;
        using var linkedCancellation = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken, _lifetimeCancellation.Token);
        try
        {
            _suppressScheduling = true;
            try { await RunOnUiThreadAsync(() => _store.FlushPendingProgressAsync(linkedCancellation.Token)); }
            finally { _suppressScheduling = false; }
            var watched = await _syncWatchdog.RunAsync(
                token => Task.Run(() => Engine.PublishLocalAsync(Preferences.FolderPath, token), token),
                SyncWatchdogTimeout,
                linkedCancellation.Token).ConfigureAwait(false);
            if (watched.Status == WatchdogStatus.TimedOut) MarkFolderTemporarilyUnavailable();
        }
        catch (OperationCanceledException)
        {
        }
        catch (Exception exception)
        {
            UpdateState(new(false, Preferences.LastSyncAt, exception.Message, ShouldNotify: true));
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
            if (onlyIfMacChanged && Volatile.Read(ref _forceRemoteRetry) == 0)
            {
                var probe = await RunProbeAsync(
                    MacSnapshotSignatureChangedCore,
                    bypassBackoff: false,
                    scheduled.Token).ConfigureAwait(false);
                if (!probe.Completed || !probe.Value) return;
            }
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

    private async Task ConfigureWatcherAsync(bool bypassBackoff, CancellationToken cancellationToken = default) =>
        _ = await RunProbeAsync(
            () =>
            {
                ConfigureWatcherCore();
                return true;
            },
            bypassBackoff,
            cancellationToken).ConfigureAwait(false);

    private void ConfigureWatcherCore()
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
            UpdateObservedMacWriteTimeCore();
        }
        catch (Exception exception)
        {
            UpdateState(new(false, Preferences.LastSyncAt, exception.Message));
        }
    }

    private void MacSnapshotChanged(object sender, FileSystemEventArgs e) =>
        ScheduleRemoteSync(onlyIfMacChanged: true);

    private void QueuePoll()
    {
        if (_disposed) return;
        _ = RunProbeAsync(
            () =>
            {
                PollFolderIo();
                return true;
            },
            bypassBackoff: false,
            _lifetimeCancellation.Token);
    }

    private void PollFolderIo()
    {
        if (!Preferences.IsEnabled || string.IsNullOrWhiteSpace(Preferences.FolderPath)) return;
        try
        {
            if (_watcher is null) ConfigureWatcherCore();
            var signature = ReadMacSnapshotSignatureCore(Preferences.FolderPath);
            bool changed;
            lock (_signatureLock)
            {
                changed = signature.Exists
                    && (signature.LastWriteTimeUtc != _observedMacWriteTimeUtc
                        || signature.Length != _observedMacLength);
            }
            if (changed) ScheduleRemoteSync(TimeSpan.Zero, onlyIfMacChanged: true);
        }
        catch
        {
            // Polling is only a fallback. The next activation or poll retries.
        }
    }

    private async Task UpdateObservedMacWriteTimeAsync(CancellationToken cancellationToken = default) =>
        _ = await RunProbeAsync(
            () =>
            {
                UpdateObservedMacWriteTimeCore();
                return true;
            },
            bypassBackoff: true,
            cancellationToken).ConfigureAwait(false);

    private void UpdateObservedMacWriteTimeCore()
    {
        if (string.IsNullOrWhiteSpace(Preferences.FolderPath)) return;
        var signature = ReadMacSnapshotSignatureCore(Preferences.FolderPath);
        lock (_signatureLock)
        {
            _observedMacWriteTimeUtc = signature.LastWriteTimeUtc;
            _observedMacLength = signature.Length;
        }
    }

    private bool MacSnapshotSignatureChangedCore()
    {
        if (string.IsNullOrWhiteSpace(Preferences.FolderPath)) return false;
        var signature = ReadMacSnapshotSignatureCore(Preferences.FolderPath);
        if (!signature.Exists) return false;
        lock (_signatureLock)
        {
            return signature.LastWriteTimeUtc != _observedMacWriteTimeUtc
                || signature.Length != _observedMacLength;
        }
    }

    private static MacSnapshotSignature ReadMacSnapshotSignatureCore(string folderPath)
    {
        var path = Path.Combine(SyncEngine.ResolveSyncDirectory(folderPath), SyncEngine.MacFileName);
        if (!File.Exists(path)) return MacSnapshotSignature.Missing;
        var info = new FileInfo(path);
        return new(true, info.LastWriteTimeUtc, info.Length);
    }

    private readonly record struct MacSnapshotSignature(bool Exists, DateTime LastWriteTimeUtc, long Length)
    {
        public static MacSnapshotSignature Missing { get; } = new(false, DateTime.MinValue, -1);
    }

    private async Task<ProbeResult<T>> RunProbeAsync<T>(
        Func<T> probe,
        bool bypassBackoff,
        CancellationToken cancellationToken)
    {
        if (!_probeGuard.TryBegin(DateTimeOffset.UtcNow, bypassBackoff)) return new(false, default);
        var probeTask = Task.Run(probe);
        var releaseHere = true;
        try
        {
            var completed = await Task.WhenAny(
                probeTask,
                Task.Delay(SyncWatchdogTimeout, cancellationToken)).ConfigureAwait(false);
            if (completed == probeTask) return new(true, await probeTask.ConfigureAwait(false));

            releaseHere = false;
            ObserveProbeCompletion(probeTask);
            cancellationToken.ThrowIfCancellationRequested();
            _probeGuard.DelayAutomaticProbesUntil(DateTimeOffset.UtcNow.Add(ProbeBackoff));
            Interlocked.Exchange(ref _forceRemoteRetry, 1);
            MarkFolderTemporarilyUnavailable();
            return new(false, default);
        }
        finally
        {
            if (releaseHere) _probeGuard.Complete();
        }
    }

    private void ObserveProbeCompletion(Task probeTask) =>
        _ = probeTask.ContinueWith(
            completedProbe =>
            {
                _ = completedProbe.Exception;
                _probeGuard.Complete();
            },
            CancellationToken.None,
            TaskContinuationOptions.ExecuteSynchronously,
            TaskScheduler.Default);

    private void MarkFolderTemporarilyUnavailable()
    {
        Interlocked.Exchange(ref _forceRemoteRetry, 1);
        UpdateState(new(false, Preferences.LastSyncAt, "同步文件夹暂不可用", ShouldNotify: true));
    }

    private readonly record struct ProbeResult<T>(bool Completed, T? Value);

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
        var watcher = Interlocked.Exchange(ref _watcher, null);
        if (watcher is not null) _ = Task.Run(watcher.Dispose);
        _pollTimer.Dispose();
        _lifetimeCancellation.Cancel();
        await Task.CompletedTask;
        _lifetimeCancellation.Dispose();
    }
}
