using YYReader.Windows.Core.Models;

namespace YYReader.Windows.Core.Reading;

public sealed class ReaderContinuousAttachmentState
{
    private PendingAttachment? _pending;

    public bool IsScrolling { get; private set; }
    public bool HasPending => _pending is not null;
    public int Generation { get; private set; }

    public void SetScrolling(bool isScrolling) => IsScrolling = isScrolling;

    public bool Queue(Chapter chapter, string expectedTailUrl, int generation)
    {
        if (generation != Generation || _pending is not null)
        {
            return false;
        }

        _pending = new PendingAttachment(chapter, expectedTailUrl, generation);
        return true;
    }

    public bool TryTake(out Chapter? chapter, out string? expectedTailUrl)
    {
        chapter = null;
        expectedTailUrl = null;
        if (IsScrolling || _pending is not { } pending || pending.Generation != Generation)
        {
            return false;
        }

        _pending = null;
        chapter = pending.Chapter;
        expectedTailUrl = pending.ExpectedTailUrl;
        return true;
    }

    public int Reset()
    {
        _pending = null;
        IsScrolling = false;
        return ++Generation;
    }

    private sealed record PendingAttachment(Chapter Chapter, string ExpectedTailUrl, int Generation);
}
