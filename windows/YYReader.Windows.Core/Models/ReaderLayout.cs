namespace YYReader.Windows.Core.Models;

public static class ReaderLayout
{
    public const double MinimumContentWidthEm = 20;
    public const double DefaultContentWidthEm = 48;
    public const double MaximumContentWidthEm = 80;

    public static double EffectiveContentWidth(double preferredWidthEm, double fontSize, double viewportWidth)
    {
        var widthEm = Math.Clamp(preferredWidthEm, MinimumContentWidthEm, MaximumContentWidthEm);
        var preferredWidth = widthEm * Math.Max(fontSize, 1);
        var horizontalMargin = viewportWidth >= 900 ? 52 : 40;
        var availableWidth = Math.Max(viewportWidth - horizontalMargin * 2, 1);
        return Math.Min(preferredWidth, availableWidth);
    }
}
