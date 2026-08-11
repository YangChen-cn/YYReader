namespace YYReader.Windows.Core.Models;

public static class ReaderPosition
{
    public static int RestoreParagraphIndex(int? savedIndex, double? progress, int paragraphCount)
    {
        if (paragraphCount <= 0)
        {
            return 0;
        }

        if (savedIndex is >= 0 && savedIndex < paragraphCount)
        {
            return savedIndex.Value;
        }

        var fallbackProgress = Math.Clamp(progress ?? 0, 0, 1);
        return (int)Math.Round(fallbackProgress * (paragraphCount - 1), MidpointRounding.AwayFromZero);
    }

    public static double ProgressForParagraph(int paragraphIndex, int paragraphCount)
    {
        if (paragraphCount <= 1)
        {
            return 0;
        }

        return Math.Clamp((double)Math.Max(paragraphIndex, 0) / (paragraphCount - 1), 0, 1);
    }
}
