namespace YYReader.Windows.Core.Sync;

public enum WatchdogStatus
{
    Completed,
    Busy,
    TimedOut
}

public sealed record WatchdogResult<T>(WatchdogStatus Status, T? Value = default);

public sealed class RecoverableSyncWatchdog
{
    private readonly object _lock = new();
    private long _generation;
    private bool _occupied;

    public async Task<WatchdogResult<T>> RunAsync<T>(
        Func<CancellationToken, Task<T>> operation,
        TimeSpan timeout,
        CancellationToken cancellationToken = default)
    {
        long generation;
        lock (_lock)
        {
            if (_occupied) return new(WatchdogStatus.Busy);
            _occupied = true;
            generation = ++_generation;
        }

        using var operationCancellation = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        Task<T>? operationTask = null;
        try
        {
            operationTask = operation(operationCancellation.Token);
            var timeoutTask = Task.Delay(timeout, cancellationToken);
            var completed = await Task.WhenAny(operationTask, timeoutTask).ConfigureAwait(false);
            if (completed == operationTask)
            {
                return new(WatchdogStatus.Completed, await operationTask.ConfigureAwait(false));
            }

            operationCancellation.Cancel();
            ObserveAbandonedTask(operationTask);
            cancellationToken.ThrowIfCancellationRequested();
            return new(WatchdogStatus.TimedOut);
        }
        finally
        {
            lock (_lock)
            {
                if (_generation == generation)
                {
                    _occupied = false;
                }
            }
        }
    }

    private static void ObserveAbandonedTask(Task task) =>
        _ = task.ContinueWith(
            completed => _ = completed.Exception,
            CancellationToken.None,
            TaskContinuationOptions.OnlyOnFaulted | TaskContinuationOptions.ExecuteSynchronously,
            TaskScheduler.Default);
}

public sealed class SingleFlightProbeGuard
{
    private int _inFlight;
    private long _automaticProbeNotBeforeUtcTicks;

    public bool TryBegin(DateTimeOffset now, bool bypassBackoff = false)
    {
        if (!bypassBackoff && now.UtcTicks < Interlocked.Read(ref _automaticProbeNotBeforeUtcTicks)) return false;
        return Interlocked.CompareExchange(ref _inFlight, 1, 0) == 0;
    }

    public void Complete() => Volatile.Write(ref _inFlight, 0);

    public void DelayAutomaticProbesUntil(DateTimeOffset retryAt) =>
        Interlocked.Exchange(ref _automaticProbeNotBeforeUtcTicks, retryAt.UtcTicks);

    public bool IsInFlight => Volatile.Read(ref _inFlight) != 0;
}
