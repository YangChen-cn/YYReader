namespace YYReader.Windows.Core.Models;

public sealed record ReaderAnchor(
    string ChapterUrl,
    int ParagraphIndex,
    double ViewportRelativeOffset = 0)
{
    public ReaderAnchor Normalized(int paragraphCount) => this with
    {
        ParagraphIndex = paragraphCount <= 0
            ? 0
            : Math.Clamp(ParagraphIndex, 0, paragraphCount - 1),
        ViewportRelativeOffset = Math.Clamp(ViewportRelativeOffset, 0, 1)
    };
}
