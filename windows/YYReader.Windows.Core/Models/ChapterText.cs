namespace YYReader.Windows.Core.Models;

public static class ChapterText
{
    public static string NormalizeBodyText(string bodyText)
    {
        var lines = bodyText
            .Replace("\r\n", "\n", StringComparison.Ordinal)
            .Replace('\r', '\n')
            .Split('\n', StringSplitOptions.RemoveEmptyEntries)
            .Select(line => line.Trim())
            .Where(line => line.Length > 0);

        return string.Join("\n\n", lines);
    }

    public static IReadOnlyList<string> ToParagraphs(string? bodyText)
    {
        if (string.IsNullOrWhiteSpace(bodyText))
        {
            return Array.Empty<string>();
        }

        return bodyText
            .Replace("\r\n", "\n", StringComparison.Ordinal)
            .Replace('\r', '\n')
            .Split("\n\n", StringSplitOptions.RemoveEmptyEntries)
            .Select(paragraph => paragraph.Trim())
            .Where(paragraph => paragraph.Length > 0)
            .ToArray();
    }
}
