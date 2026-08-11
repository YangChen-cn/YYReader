using System.Text.RegularExpressions;
using AngleSharp.Dom;
using YYReader.Windows.Core.Models;

namespace YYReader.Windows.Core.Parsing;

public sealed class QidiySourceAdapter : INovelSourceAdapter
{
    public bool CanHandle(LoadedHtml document)
    {
        var host = document.FinalUri.DnsSafeHost.ToLowerInvariant();
        return host == "qidiy.com" || host.EndsWith(".qidiy.com", StringComparison.Ordinal);
    }

    public ParsedChapterPage ParseChapterPage(LoadedHtml loaded)
    {
        var document = HtmlParsingSupport.ParseDocument(loaded);
        var content = document.QuerySelector("#content");
        var heading = document.QuerySelector("h1.title");
        if (content is null || heading is null)
        {
            throw new NovelParsingException(NovelParsingErrorKind.NoReadableContent);
        }

        var rawTitle = HtmlParsingSupport.Normalize(heading.TextContent);
        var title = Regex.Replace(rawTitle, @"\s*[（(]第\d+/\d+页[）)]\s*$", string.Empty).Trim();
        var paragraphs = CleanChapterParagraphs(HtmlParsingSupport.Paragraphs(content), title);
        if (paragraphs.Count == 0)
        {
            throw new NovelParsingException(NovelParsingErrorKind.NoReadableContent);
        }

        var catalogUrl = HtmlParsingSupport.Link(document, ["章节列表", "目录"], loaded.FinalUri);
        var previous = HtmlParsingSupport.Link(document, ["上一章"], loaded.FinalUri);
        var next = HtmlParsingSupport.Link(document, ["下一章"], loaded.FinalUri);
        var nextPage = HtmlParsingSupport.Link(document, ["下一页"], loaded.FinalUri);
        var bookLink = document.QuerySelectorAll("a")
            .Select(anchor => (anchor, url: HtmlParsingSupport.AbsoluteUrl(anchor, loaded.FinalUri)))
            .FirstOrDefault(pair => pair.url is not null
                && Regex.IsMatch(pair.url.AbsolutePath, @"^/book/\d+/?$", RegexOptions.CultureInvariant)
                && !new[] { "上一章", "下一章", "章节列表", "开始阅读" }.Contains(HtmlParsingSupport.Normalize(pair.anchor.TextContent)));
        var bookTitle = bookLink.anchor is null ? null : HtmlParsingSupport.Normalize(bookLink.anchor.TextContent);

        return new ParsedChapterPage(
            title,
            string.IsNullOrWhiteSpace(bookTitle) ? null : bookTitle,
            null,
            paragraphs,
            catalogUrl,
            previous is not null && previous == catalogUrl ? null : previous,
            next,
            nextPage);
    }

    public ParsedBookCatalog ParseCatalogPage(LoadedHtml loaded)
    {
        var document = HtmlParsingSupport.ParseDocument(loaded);
        var title = document.QuerySelectorAll("h1")
            .FirstOrDefault(heading => !heading.ClassList.Contains("logo"))
            ?.TextContent.Trim();
        if (string.IsNullOrWhiteSpace(title))
        {
            throw new NovelParsingException(NovelParsingErrorKind.MissingCatalog);
        }

        var authorText = document.QuerySelectorAll("p")
            .Select(paragraph => HtmlParsingSupport.Normalize(paragraph.TextContent))
            .FirstOrDefault(text => Regex.IsMatch(text, @"^作者[：:]", RegexOptions.CultureInvariant));
        var author = string.IsNullOrWhiteSpace(authorText)
            ? "未知作者"
            : Regex.Replace(authorText, @"^作者[：:]\s*", string.Empty).Trim();

        var sections = document.QuerySelectorAll("ul.section-list")
            .Select(section => ChapterSeeds(section, loaded.FinalUri))
            .Where(section => section.Count > 0)
            .ToArray();
        var chapters = sections.OrderByDescending(section => section.Count)
            .ThenBy(section => section.Select(seed => HtmlParsingSupport.ChapterNumber(seed.Title) ?? int.MaxValue).DefaultIfEmpty(int.MaxValue).Min())
            .FirstOrDefault() ?? new List<ChapterSeed>();

        return new ParsedBookCatalog(
            title,
            author,
            chapters,
            HtmlParsingSupport.Link(document, ["下一页"], loaded.FinalUri));
    }

    private static List<ChapterSeed> ChapterSeeds(IElement section, Uri baseUri)
    {
        var seen = new HashSet<string>(StringComparer.Ordinal);
        var result = new List<ChapterSeed>();
        foreach (var anchor in section.QuerySelectorAll("a"))
        {
            var title = HtmlParsingSupport.Normalize(anchor.TextContent);
            var url = HtmlParsingSupport.AbsoluteUrl(anchor, baseUri);
            if (!Regex.IsMatch(title, @"第.+[章回节]", RegexOptions.CultureInvariant)
                || url is null
                || !HtmlParsingSupport.IsSameOrigin(url, baseUri)
                || !seen.Add(url.AbsoluteUri))
            {
                continue;
            }

            result.Add(new ChapterSeed(title, UrlCanonicalizer.CanonicalizeChapter(url), result.Count + 1));
        }

        return result;
    }

    private static List<string> CleanChapterParagraphs(IEnumerable<string> paragraphs, string title)
    {
        var pageMarker = $"{Regex.Escape(title)}\\s*\\(第\\d+/\\d+页\\)\\s*";
        return paragraphs
            .Select(paragraph => Regex.Replace(paragraph, @"read\d+\(\);?", string.Empty, RegexOptions.IgnoreCase))
            .Select(paragraph => Regex.Replace(paragraph, pageMarker, string.Empty))
            .Select(paragraph => Regex.Replace(paragraph, @"[（(]本章未完[^）)]*[）)]", string.Empty))
            .Select(HtmlParsingSupport.Normalize)
            .Where(paragraph => paragraph.Length > 0 && !paragraph.Contains("加入书签，方便阅读", StringComparison.Ordinal))
            .ToList();
    }
}
