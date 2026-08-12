namespace YYReader.Windows.Core.Reading;

public sealed class ReaderContinuousLoadState(TimeSpan? retryDelay = null)
{
    private readonly TimeSpan _retryDelay = retryDelay ?? TimeSpan.FromSeconds(4);
    private string? _attemptedAfterChapterUrl;
    private string? _nearEndChapterUrl;
    private bool _attemptedDuringNearEndVisit;
    private DateTimeOffset _retryAt;

    public void ObserveNearEnd(string? chapterUrl, bool isNearEnd)
    {
        if (!isNearEnd || string.IsNullOrWhiteSpace(chapterUrl))
        {
            _nearEndChapterUrl = null;
            _attemptedDuringNearEndVisit = false;
            return;
        }

        if (!string.Equals(_nearEndChapterUrl, chapterUrl, StringComparison.Ordinal))
        {
            _nearEndChapterUrl = chapterUrl;
            _attemptedDuringNearEndVisit = false;
        }
    }

    public bool TryBegin(string? chapterUrl, DateTimeOffset now, bool explicitRetry = false)
    {
        if (string.IsNullOrWhiteSpace(chapterUrl)
            || (!explicitRetry && (chapterUrl == _attemptedAfterChapterUrl
                || _attemptedDuringNearEndVisit
                || now < _retryAt)))
        {
            return false;
        }

        _attemptedAfterChapterUrl = chapterUrl;
        _nearEndChapterUrl = chapterUrl;
        _attemptedDuringNearEndVisit = true;
        return true;
    }

    public void MarkFailed(DateTimeOffset now)
    {
        _attemptedAfterChapterUrl = null;
        _retryAt = now + _retryDelay;
    }

    public void Reset()
    {
        _attemptedAfterChapterUrl = null;
        _nearEndChapterUrl = null;
        _attemptedDuringNearEndVisit = false;
        _retryAt = DateTimeOffset.MinValue;
    }
}
