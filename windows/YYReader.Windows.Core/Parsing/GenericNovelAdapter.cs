using System.Text.Json;
using System.Text.RegularExpressions;
using AngleSharp.Dom;
using YYReader.Windows.Core.Models;

namespace YYReader.Windows.Core.Parsing;

public sealed class GenericNovelAdapter : INovelSourceAdapter
{
    public bool CanHandle(LoadedHtml document) => true;

    public ParsedChapterPage ParseChapterPage(LoadedHtml loaded)
    {
        var document = HtmlParsingSupport.ParseDocument(loaded);
        var candidate = BestContentCandidate(document)
            ?? throw new NovelParsingException(NovelParsingErrorKind.NoReadableContent);
        var paragraphs = HtmlParsingSupport.Paragraphs(candidate)
            .Where(paragraph => paragraph.Length > 1)
            .ToArray();
        if (string.Concat(paragraphs).Length < 60)
        {
            throw new NovelParsingException(NovelParsingErrorKind.NoReadableContent);
        }

        var title = ChapterTitle(document);
        var metadata = Metadata(document);
        return new ParsedChapterPage(
            title,
            metadata.BookTitle,
            metadata.Author,
            paragraphs,
            NavigationUrl(document, ["目录", "章节列表", "返回目录", "全部章节"], null, loaded.FinalUri),
            NavigationUrl(document, ["上一章", "上一章节", "前一章"], "prev", loaded.FinalUri),
            NavigationUrl(document, ["下一章", "下一章节", "后一章"], "next", loaded.FinalUri),
            NavigationUrl(document, ["下一页", "下页"], null, loaded.FinalUri));
    }

    public ParsedBookCatalog ParseCatalogPage(LoadedHtml loaded)
    {
        var document = HtmlParsingSupport.ParseDocument(loaded);
        var metadata = Metadata(document);
        var headingTitle = document.QuerySelector("h1")?.TextContent.Trim();
        var title = string.IsNullOrWhiteSpace(metadata.BookTitle) ? headingTitle : metadata.BookTitle;
        title = string.IsNullOrWhiteSpace(title) ? "未命名小说" : title;

        var seeds = ChapterSeeds(document, loaded.FinalUri);
        if (seeds.Count == 0)
        {
            throw new NovelParsingException(NovelParsingErrorKind.MissingCatalog);
        }

        return new ParsedBookCatalog(
            title,
            string.IsNullOrWhiteSpace(metadata.Author) ? "未知作者" : metadata.Author,
            seeds,
            NavigationUrl(document, ["下一页", "下页"], null, loaded.FinalUri));
    }

    private static IElement? BestContentCandidate(IDocument document)
    {
        var selectors = "article, main, [id*=content], [class*=content], [id*=chapter], [class*=chapter], [id*=read], [class*=read]";
        var candidates = document.QuerySelectorAll(selectors).ToArray();
        var hasNavigation = HasChapterNavigation(document);
        var hasTitle = IsLikelyChapterTitle(ChapterTitle(document));
        var best = candidates
            .Select(candidate => (candidate, score: Score(candidate)))
            .OrderByDescending(pair => pair.score)
            .FirstOrDefault();

        if (best.candidate is null)
        {
            return null;
        }

        return best.score > 100 || (best.score >= 60 && hasTitle && hasNavigation)
            ? best.candidate
            : null;
    }

    private static bool HasChapterNavigation(IDocument document)
    {
        var labels = new HashSet<string>(["上一章", "上一章节", "前一章", "下一章", "下一章节", "后一章"]);
        return document.QuerySelectorAll("a")
            .Select(anchor => HtmlParsingSupport.Normalize(anchor.TextContent))
            .Any(labels.Contains);
    }

    private static int Score(IElement element)
    {
        var textLength = element.TextContent.Length;
        var linkLength = element.QuerySelectorAll("a").Sum(anchor => anchor.TextContent.Length);
        var paragraphCount = element.QuerySelectorAll("p, br").Length;
        return textLength - linkLength * 2 + paragraphCount * 30;
    }

    private static string ChapterTitle(IDocument document)
    {
        var heading = document.QuerySelector("h1")?.TextContent.Trim();
        if (!string.IsNullOrWhiteSpace(heading))
        {
            return heading;
        }

        var title = document.Title ?? string.Empty;
        var first = Regex.Split(title, @"[_｜|\-]").FirstOrDefault()?.Trim();
        return string.IsNullOrWhiteSpace(first) ? "未命名章节" : first;
    }

    private static (string? BookTitle, string? Author) Metadata(IDocument document)
    {
        var pageTitle = document.Title ?? string.Empty;
        var ogTitle = document.QuerySelector("meta[property='og:title']")?.GetAttribute("content");
        var author = document.QuerySelector("meta[name='author']")?.GetAttribute("content")
            ?? JsonLdValue("author", document)
            ?? HtmlParsingSupport.FirstCapture(@"作者\s*[：:]\s*([^\s]+)", document.Body?.TextContent ?? string.Empty);
        var bookTitle = JsonLdValue("isPartOf", document)
            ?? (ogTitle ?? string.Empty).Split('_').Skip(1).FirstOrDefault()
            ?? pageTitle.Split('_').Skip(1).FirstOrDefault();
        return (Clean(bookTitle), Clean(author));
    }

    private static List<ChapterSeed> ChapterSeeds(IDocument document, Uri baseUri)
    {
        var selectors = new[]
        {
            "[id*=catalog]", "[class*=catalog]", "[id*=chapter]", "[class*=chapter]",
            "[id*=list]", "[class*=list]", "ul", "ol"
        };
        var allowed = new HashSet<string>(StringComparer.Ordinal);
        foreach (var selector in selectors)
        {
            foreach (var container in document.QuerySelectorAll(selector))
            {
                var seeds = ChapterSeeds(container.QuerySelectorAll("a"), baseUri);
                if (seeds.Count >= 2)
                {
                    foreach (var seed in seeds)
                    {
                        allowed.Add(seed.Url.AbsoluteUri);
                    }
                }
            }
        }

        return allowed.Count > 0
            ? ChapterSeeds(document.QuerySelectorAll("a"), baseUri, allowed)
            : ChapterSeeds(document.QuerySelectorAll("a"), baseUri);
    }

    private static List<ChapterSeed> ChapterSeeds(
        IEnumerable<IElement> anchors,
        Uri baseUri,
        ISet<string>? allowed = null)
    {
        var seen = new HashSet<string>(StringComparer.Ordinal);
        var result = new List<ChapterSeed>();
        foreach (var anchor in anchors)
        {
            var title = HtmlParsingSupport.Normalize(anchor.TextContent);
            var url = HtmlParsingSupport.AbsoluteUrl(anchor, baseUri);
            if (!IsLikelyChapterTitle(title)
                || url is null
                || !HtmlParsingSupport.IsSameOrigin(url, baseUri)
                || (allowed is not null && !allowed.Contains(url.AbsoluteUri))
                || !seen.Add(url.AbsoluteUri))
            {
                continue;
            }

            result.Add(new ChapterSeed(title, UrlCanonicalizer.CanonicalizeChapter(url), result.Count + 1));
        }

        return result;
    }

    private static bool IsLikelyChapterTitle(string title) =>
        Regex.IsMatch(title, @"第.+[章回节]", RegexOptions.CultureInvariant)
        || new[] { "序章", "楔子", "引子", "尾声", "后记", "番外" }.Any(title.Contains);

    private static Uri? NavigationUrl(
        IDocument document,
        IEnumerable<string> labels,
        string? rel,
        Uri baseUri)
    {
        if (rel is not null)
        {
            var anchor = document.QuerySelectorAll("a")
                .FirstOrDefault(candidate =>
                    candidate.GetAttribute("rel")?.Split(' ', StringSplitOptions.RemoveEmptyEntries)
                        .Contains(rel, StringComparer.OrdinalIgnoreCase) == true);
            var related = anchor is null ? null : HtmlParsingSupport.AbsoluteUrl(anchor, baseUri);
            if (related is not null)
            {
                return related;
            }
        }

        return HtmlParsingSupport.Link(document, labels, baseUri);
    }

    private static string? JsonLdValue(string key, IDocument document)
    {
        foreach (var script in document.QuerySelectorAll("script[type='application/ld+json']"))
        {
            try
            {
                using var json = JsonDocument.Parse(script.TextContent);
                var value = FindJsonValue(key, json.RootElement);
                if (!string.IsNullOrWhiteSpace(value))
                {
                    return value;
                }
            }
            catch (JsonException)
            {
                // A malformed JSON-LD block should not prevent semantic HTML parsing.
            }
        }

        return null;
    }

    private static string? FindJsonValue(string key, JsonElement element)
    {
        if (element.ValueKind == JsonValueKind.Object)
        {
            foreach (var property in element.EnumerateObject())
            {
                if (property.NameEquals(key))
                {
                    if (property.Value.ValueKind == JsonValueKind.String)
                    {
                        return property.Value.GetString();
                    }

                    if (property.Value.ValueKind == JsonValueKind.Object
                        && property.Value.TryGetProperty("name", out var name)
                        && name.ValueKind == JsonValueKind.String)
                    {
                        return name.GetString();
                    }
                }

                var nested = FindJsonValue(key, property.Value);
                if (!string.IsNullOrWhiteSpace(nested))
                {
                    return nested;
                }
            }
        }
        else if (element.ValueKind == JsonValueKind.Array)
        {
            foreach (var item in element.EnumerateArray())
            {
                var nested = FindJsonValue(key, item);
                if (!string.IsNullOrWhiteSpace(nested))
                {
                    return nested;
                }
            }
        }

        return null;
    }

    private static string? Clean(string? value) =>
        string.IsNullOrWhiteSpace(value) ? null : value.Trim();
}
