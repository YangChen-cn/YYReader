namespace YYReader.Windows.Core.Reading;

public enum ReaderContinuousLoadPhase
{
    Idle,
    LoadingNext,
    CheckingLatest,
    Ready,
    Attached,
    ConfirmedLatest,
    Failed
}

public sealed class ReaderContinuousLoadState(TimeSpan? retryDelay = null, int maximumAutomaticChain = 3)
{
    private readonly TimeSpan _retryDelay = retryDelay ?? TimeSpan.FromSeconds(4);
    private string? _attemptedAfterChapterUrl;
    private string? _nearEndChapterUrl;
    private bool _attemptedDuringNearEndVisit;
    private int _automaticAttemptsDuringNearEndVisit;
    private DateTimeOffset _retryAt;

    public ReaderContinuousLoadPhase Phase { get; private set; } = ReaderContinuousLoadPhase.Idle;

    public void ObserveNearEnd(string? chapterUrl, bool isNearEnd)
    {
        if (!isNearEnd || string.IsNullOrWhiteSpace(chapterUrl))
        {
            _nearEndChapterUrl = null;
            _attemptedDuringNearEndVisit = false;
            _automaticAttemptsDuringNearEndVisit = 0;
            _attemptedAfterChapterUrl = null;
            _retryAt = DateTimeOffset.MinValue;
            Phase = ReaderContinuousLoadPhase.Idle;
            return;
        }

        if (!string.Equals(_nearEndChapterUrl, chapterUrl, StringComparison.Ordinal))
        {
            _nearEndChapterUrl = chapterUrl;
            _attemptedDuringNearEndVisit = false;
            _attemptedAfterChapterUrl = null;
            _retryAt = DateTimeOffset.MinValue;
            Phase = ReaderContinuousLoadPhase.Idle;
        }
    }

    public bool TryBegin(string? chapterUrl, DateTimeOffset now, bool explicitRetry = false)
    {
        if (string.IsNullOrWhiteSpace(chapterUrl)
            || (!explicitRetry && (chapterUrl == _attemptedAfterChapterUrl
                || _attemptedDuringNearEndVisit
                || _automaticAttemptsDuringNearEndVisit >= maximumAutomaticChain
                || now < _retryAt)))
        {
            return false;
        }

        _attemptedAfterChapterUrl = chapterUrl;
        _nearEndChapterUrl = chapterUrl;
        _attemptedDuringNearEndVisit = true;
        if (!explicitRetry)
        {
            _automaticAttemptsDuringNearEndVisit++;
        }
        Phase = ReaderContinuousLoadPhase.LoadingNext;
        return true;
    }

    public void MarkCheckingLatest() => Phase = ReaderContinuousLoadPhase.CheckingLatest;

    public void MarkLoadingNext() => Phase = ReaderContinuousLoadPhase.LoadingNext;

    public void MarkReady() => Phase = ReaderContinuousLoadPhase.Ready;

    public void MarkAttached() => Phase = ReaderContinuousLoadPhase.Attached;

    public void MarkConfirmedLatest() => Phase = ReaderContinuousLoadPhase.ConfirmedLatest;

    public void MarkFailed(DateTimeOffset now)
    {
        _attemptedAfterChapterUrl = null;
        _retryAt = now + _retryDelay;
        Phase = ReaderContinuousLoadPhase.Failed;
    }

    public void Reset()
    {
        _attemptedAfterChapterUrl = null;
        _nearEndChapterUrl = null;
        _attemptedDuringNearEndVisit = false;
        _automaticAttemptsDuringNearEndVisit = 0;
        _retryAt = DateTimeOffset.MinValue;
        Phase = ReaderContinuousLoadPhase.Idle;
    }
}
