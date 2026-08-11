namespace YYReader.Windows.Core.Models;

public sealed record ReaderPreferences(
    string FontFamily = "serif",
    double FontSize = 20,
    double LineSpacing = 0.40,
    double ParagraphSpacing = 0.60,
    double ContentWidthEm = 48,
    bool ParagraphIndent = true,
    bool ContinuousReading = false,
    bool PrefetchNextChapter = true,
    string Theme = "system")
{
    public static ReaderPreferences Defaults { get; } = new();

    public ReaderPreferences Normalized() => this with
    {
        FontSize = Math.Clamp(FontSize, 14, 36),
        LineSpacing = Math.Clamp(LineSpacing, 0.20, 0.65),
        ParagraphSpacing = Math.Clamp(ParagraphSpacing, 0.35, 0.90),
        ContentWidthEm = Math.Clamp(ContentWidthEm, ReaderLayout.MinimumContentWidthEm, ReaderLayout.MaximumContentWidthEm)
    };
}
