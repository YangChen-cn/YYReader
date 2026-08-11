namespace YYReader.Windows.Core.Services;

public sealed class HostRateLimiter
{
    private readonly object _gate = new();
    private readonly TimeSpan _defaultMinimumDelay;
    private readonly Dictionary<string, TimeSpan> _hostMinimumDelays;
    private readonly Dictionary<string, DateTimeOffset> _nextAvailable = new(StringComparer.OrdinalIgnoreCase);

    public HostRateLimiter(
        TimeSpan? defaultMinimumDelay = null,
        IReadOnlyDictionary<string, TimeSpan>? hostMinimumDelays = null)
    {
        _defaultMinimumDelay = defaultMinimumDelay ?? TimeSpan.FromSeconds(1);
        _hostMinimumDelays = hostMinimumDelays is null
            ? new Dictionary<string, TimeSpan>(StringComparer.OrdinalIgnoreCase)
            : hostMinimumDelays.ToDictionary(pair => pair.Key, pair => pair.Value, StringComparer.OrdinalIgnoreCase);
    }

    public void SetMinimumDelay(string host, TimeSpan delay)
    {
        lock (_gate)
        {
            _hostMinimumDelays[host] = delay;
        }
    }

    public async Task WaitAsync(Uri url, CancellationToken cancellationToken = default)
    {
        var host = url.DnsSafeHost;
        DateTimeOffset scheduled;
        lock (_gate)
        {
            var now = DateTimeOffset.UtcNow;
            var delay = _hostMinimumDelays.GetValueOrDefault(host, _defaultMinimumDelay);
            scheduled = _nextAvailable.TryGetValue(host, out var current) && current > now ? current : now;
            _nextAvailable[host] = scheduled.Add(delay);
        }

        var wait = scheduled - DateTimeOffset.UtcNow;
        if (wait > TimeSpan.Zero)
        {
            await Task.Delay(wait, cancellationToken).ConfigureAwait(false);
        }
    }
}
