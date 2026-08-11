using System.Text;
using System.Text.RegularExpressions;
using AngleSharp.Dom;
using AngleSharp.Html.Parser;
using YYReader.Windows.Core.Models;

namespace YYReader.Windows.Core.Parsing;

public static class HtmlParsingSupport
{
    private static readonly HashSet<string> BlockTags = new(StringComparer.OrdinalIgnoreCase)
    {
        "article", "div", "h1", "h2", "h3", "h4", "h5", "h6", "li", "p", "section"
    };

    private static readonly HashSet<string> IgnoredTags = new(StringComparer.OrdinalIgnoreCase)
    {
        "form", "iframe", "noscript", "script", "style"
    };

    public static IDocument ParseDocument(LoadedHtml loaded) =>
        new HtmlParser().ParseDocument(loaded.Html);

    public static Uri? AbsoluteUrl(IElement element, Uri baseUri)
    {
        var href = element.GetAttribute("href")?.Trim();
        if (string.IsNullOrWhiteSpace(href)
            || href.StartsWith("javascript:", StringComparison.OrdinalIgnoreCase)
            || href.StartsWith("mailto:", StringComparison.OrdinalIgnoreCase)
            || href.StartsWith("data:", StringComparison.OrdinalIgnoreCase))
        {
            return null;
        }

        return Uri.TryCreate(baseUri, href, out var url) && url is not null
            ? UrlCanonicalizer.Canonicalize(url)
            : null;
    }

    public static Uri? Link(IDocument document, IEnumerable<string> labels, Uri baseUri)
    {
        var wanted = labels.ToHashSet(StringComparer.Ordinal);
        return document.QuerySelectorAll("a")
            .Select(anchor => (anchor, label: Normalize(anchor.TextContent)))
            .Where(pair => wanted.Contains(pair.label))
            .Select(pair => AbsoluteUrl(pair.anchor, baseUri))
            .FirstOrDefault(url => url is not null);
    }

    public static IReadOnlyList<string> Paragraphs(IElement element)
    {
        var paragraphs = new List<string>();
        var current = new StringBuilder();
        Walk(element, current, paragraphs);
        Flush(current, paragraphs);
        return paragraphs;
    }

    public static string Normalize(string text)
    {
        var value = text.Replace('\u00a0', ' ').Replace('\u3000', ' ');
        value = Regex.Replace(value, @"\s+", " ", RegexOptions.CultureInvariant);
        return value.Trim();
    }

    public static string? FirstCapture(string pattern, string value)
    {
        var match = Regex.Match(value, pattern, RegexOptions.CultureInvariant);
        return match.Success && match.Groups.Count > 1 ? match.Groups[1].Value : null;
    }

    public static int? ChapterNumber(string title)
    {
        var value = FirstCapture(@"第\s*(\d+)\s*[章回节]", title);
        return int.TryParse(value, out var number) ? number : null;
    }

    public static bool IsSameOrigin(Uri candidate, Uri origin) =>
        UrlCanonicalizer.IsSameOrigin(candidate, origin);

    private static void Walk(INode node, StringBuilder current, ICollection<string> paragraphs)
    {
        if (node is IText text)
        {
            current.Append(text.Data);
            return;
        }

        if (node is not IElement element)
        {
            return;
        }

        if (IgnoredTags.Contains(element.LocalName)
            || IsAdvertisement(element))
        {
            return;
        }

        if (element.LocalName.Equals("br", StringComparison.OrdinalIgnoreCase))
        {
            Flush(current, paragraphs);
            return;
        }

        foreach (var child in element.ChildNodes)
        {
            Walk(child, current, paragraphs);
        }

        if (BlockTags.Contains(element.LocalName))
        {
            Flush(current, paragraphs);
        }
    }

    private static bool IsAdvertisement(IElement element)
    {
        var id = element.Id;
        var classes = string.Join(' ', element.ClassList);
        return IsAdvertisementToken(id) || classes.Split(' ').Any(value => IsAdvertisementToken(value));
    }

    private static bool IsAdvertisementToken(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return false;
        }

        var normalized = value.Trim().ToLowerInvariant();
        return normalized is "ad" or "ads" or "advertisement"
            || normalized.StartsWith("ad-", StringComparison.Ordinal)
            || normalized.StartsWith("ads-", StringComparison.Ordinal)
            || normalized.StartsWith("advertisement-", StringComparison.Ordinal);
    }

    private static void Flush(StringBuilder current, ICollection<string> paragraphs)
    {
        var value = Normalize(current.ToString());
        if (value.Length > 0)
        {
            paragraphs.Add(value);
        }

        current.Clear();
    }
}
