namespace YYReader.Windows.Core.Reading;

public sealed class ReaderContinuousLoadState(TimeSpan? retryDelay = null)
{
    private readonly TimeSpan _retryDelay = retryDelay ?? TimeSpan.FromSeconds(4);
    private string? _attemptedAfterChapterUrl;
    private DateTimeOffset _retryAt;

    public bool TryBegin(string? chapterUrl, DateTimeOffset now, bool explicitRetry = false)
    {
        if (string.IsNullOrWhiteSpace(chapterUrl)
            || (!explicitRetry && (chapterUrl == _attemptedAfterChapterUrl || now < _retryAt)))
        {
            return false;
        }

        _attemptedAfterChapterUrl = chapterUrl;
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
        _retryAt = DateTimeOffset.MinValue;
    }
}
