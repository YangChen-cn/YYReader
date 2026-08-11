namespace YYReader.Windows.Core.Models;

public static class ReaderPageScroll
{
    public const double PageFraction = 0.88;
    public const double SmallStep = 112;

    public static double PageDistance(double viewportHeight) => Math.Max(viewportHeight, 0) * PageFraction;

    public static bool ShouldLoadNext(double verticalOffset, double scrollableHeight, double viewportHeight)
    {
        if (viewportHeight <= 0)
        {
            return false;
        }

        var remainingDistance = Math.Max(scrollableHeight - verticalOffset, 0);
        var preloadDistance = Math.Max(viewportHeight * 1.25, 480);
        return remainingDistance <= preloadDistance;
    }

    public static double DestinationY(double currentY, double viewportHeight, double contentHeight, double distance)
    {
        var maximumY = Math.Max(contentHeight - viewportHeight, 0);
        return Math.Clamp(currentY + distance, 0, maximumY);
    }
}
