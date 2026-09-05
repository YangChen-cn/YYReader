using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Documents;
using Microsoft.UI.Xaml.Media;

namespace YYReader.Windows.Views;

internal static class AcademicTypography
{
    // Explicit per-script runs avoid DirectWrite's sans-serif CJK fallback from Times.
    public static FontFamily Chinese { get; } = new("SimSun");
    public static FontFamily Latin { get; } = new("Times New Roman");
    public static FontFamily Math { get; } = new("Cambria Math");

    public static void SetBody(TextBlock block, string text)
    {
        block.Inlines.Clear();
        block.Inlines.Add(new Run { Text = "\u3000\u3000", FontFamily = Chinese });
        for (var start = 0; start < text.Length;)
        {
            var latin = text[start] <= '\u024f';
            var end = start + 1;
            while (end < text.Length && (text[end] <= '\u024f') == latin) end++;
            block.Inlines.Add(new Run { Text = text[start..end], FontFamily = latin ? Latin : Chinese });
            start = end;
        }
    }
}
