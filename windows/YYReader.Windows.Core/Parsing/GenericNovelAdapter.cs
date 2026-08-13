using System.Text.Json;
using System.Text.RegularExpressions;
using AngleSharp.Dom;
using YYReader.Windows.Core.Models;

namespace YYReader.Windows.Core.Parsing;

public sealed class GenericNovelAdapter : INovelSourceAdapter
{
    private static readonly string[] DedicatedContentSelectors =
    [
        "[itemprop=articleBody]", "#content", "#chaptercontent", "#chapter-content", "#nr1",
        ".chapter-content", ".read-content", ".post-content", ".entry-content", ".content"
    ];

    private static readonly string[] ChapterTitleSelectors =
    [
        "[itemprop=headline]", "h1.title", "#nr_title", ".post-title",
        ".reader-main > h1", ".kfyd > h2", ".title > h1", "article h1"
    ];

    public bool CanHandle(LoadedHtml document) => true;

    public ParsedChapterPage ParseChapterPage(LoadedHtml loaded)
    {
        var document = HtmlParsingSupport.ParseDocument(loaded);
        var candidate = BestContentCandidate(document)
            ?? throw new NovelParsingException(NovelParsingErrorKind.NoReadableContent);
        var paragraphs = HtmlParsingSupport.Paragraphs(candidate)
            .Select(CleanedParagraph)
            .Where(paragraph => paragraph is not null)
            .Cast<string>()
            .ToArray();
        if (string.Concat(paragraphs).Length < 60)
        {
            throw new NovelParsingException(NovelParsingErrorKind.NoReadableContent);
        }

        var metadata = Metadata(document);
        return new ParsedChapterPage(
            ChapterTitle(document),
            metadata.BookTitle,
            metadata.Author,
            paragraphs,
            NavigationUrl(
                document,
                ["目录", "章节列表", "返回目录", "全部章节"],
                null,
                ["a#index_url", "a#bookname", "a[href*='/novel/chapters/']", ".bcrumb a[rel='category tag']"],
                loaded.FinalUri),
            NavigationUrl(document, ["上一章", "上一章节", "前一章"], "prev", [".prev_page a"], loaded.FinalUri),
            NavigationUrl(document, ["下一章", "下一章节", "后一章"], "next", [".next_page_links a"], loaded.FinalUri),
            NavigationUrl(document, ["下一页", "下页"], null, [], loaded.FinalUri));
    }

    public ParsedBookCatalog ParseCatalogPage(LoadedHtml loaded)
    {
        var document = HtmlParsingSupport.ParseDocument(loaded);
        var metadata = Metadata(document);
        var title = metadata.BookTitle ?? CatalogHeading(document) ?? "未命名小说";
        var seeds = ChapterSeeds(document, loaded.FinalUri);
        if (seeds.Count == 0)
        {
            throw new NovelParsingException(NovelParsingErrorKind.MissingCatalog);
        }

        return new ParsedBookCatalog(
            title,
            metadata.Author ?? "未知作者",
            seeds,
            NavigationUrl(
                document,
                ["下一页", "下页", "全部章节", "完整目录", "查看全部章节"],
                null,
                [],
                loaded.FinalUri));
    }

    private static IElement? BestContentCandidate(IDocument document)
    {
        var dedicated = BestScored(document.QuerySelectorAll(string.Join(", ", DedicatedContentSelectors)));
        if (dedicated.Element is not null && dedicated.Score >= 60)
        {
            return dedicated.Element;
        }

        // A long catalog often has an outer id/class containing "content" or "read".
        // Without a reliable narrow body container it must not be treated as a chapter.
        if (LikelyChapterAnchorCount(document) >= 8)
        {
            return null;
        }

        var semantic = BestScored(document.QuerySelectorAll("article, main"));
        if (semantic.Element is not null && semantic.Score >= 60)
        {
            return semantic.Element;
        }

        var candidates = document.QuerySelectorAll(
            "article, main, [id*=content], [class*=content], [id*=chapter], [class*=chapter], [id*=read], [class*=read]");
        var best = BestScored(candidates);
        if (best.Element is null)
        {
            return null;
        }

        var hasNavigation = HasChapterNavigation(document);
        var hasTitle = IsLikelyChapterTitle(ChapterTitle(document));
        return best.Score > 100 || (best.Score >= 60 && hasTitle && hasNavigation)
            ? best.Element
            : null;
    }

    private static (IElement? Element, int Score) BestScored(IEnumerable<IElement> elements) =>
        elements
            .Select(element => (Element: element, Score: Score(element)))
            .OrderByDescending(candidate => candidate.Score)
            .FirstOrDefault();

    private static int LikelyChapterAnchorCount(IDocument document) =>
        document.QuerySelectorAll("a")
            .Count(anchor => IsLikelyChapterTitle(ChapterTitleFromAnchor(anchor)));

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
        foreach (var selector in ChapterTitleSelectors)
        {
            var heading = document.QuerySelector(selector)?.TextContent;
            if (!string.IsNullOrWhiteSpace(heading))
            {
                return CleanedChapterTitle(heading);
            }
        }

        foreach (var heading in document.QuerySelectorAll("h1, h2"))
        {
            var text = HtmlParsingSupport.Normalize(heading.TextContent);
            if (IsLikelyChapterTitle(text))
            {
                return CleanedChapterTitle(text);
            }
        }

        var first = Regex.Split(document.Title ?? string.Empty, @"[_｜|\-]").FirstOrDefault();
        return string.IsNullOrWhiteSpace(first) ? "未命名章节" : CleanedChapterTitle(first);
    }

    private static (string? BookTitle, string? Author) Metadata(IDocument document)
    {
        var pageTitle = document.Title ?? string.Empty;
        var ogTitle = MetaContent("og:title", document);
        // Keep Chinese book-title quotes intact here; NormalizeMetadata trims a leading
        // 《 from full description sentences before the decorated-title matcher sees it.
        var description = document.QuerySelector("meta[name='description']")?.GetAttribute("content");
        var author = FirstNonempty(
            MetaContent("author", document),
            MetaContent("og:novel:author", document),
            JsonLdValue("author", document),
            VisibleAuthor(document));
        var bookTitle = FirstNonempty(
            MetaContent("og:novel:book_name", document),
            JsonLdValue("isPartOf", document),
            VisibleBookTitle(document),
            BookTitleFromDecoratedTitle(description),
            BookTitleFromDecoratedTitle(ogTitle),
            BookTitleFromDecoratedTitle(pageTitle));
        return (bookTitle, author);
    }

    private static string? VisibleAuthor(IDocument document)
    {
        var text = document.Body?.TextContent ?? string.Empty;
        var description = MetaContent("description", document) ?? string.Empty;
        var html = document.DocumentElement?.OuterHtml ?? string.Empty;
        return FirstNonempty(
            document.QuerySelector("#author")?.TextContent,
            LinkedAuthor(document),
            ScopedAuthor(document),
            HtmlParsingSupport.FirstCapture(@"由作者\s*([^，,。\s]+)\s*创作", description),
            HtmlParsingSupport.FirstCapture(@"提供(?:了)?([^，,。\s]+)创作", description),
            HtmlParsingSupport.FirstCapture(@"作者\s*([^，,。\s]+)", description),
            HtmlParsingSupport.FirstCapture(@"lastread\.set\([^;]+,'([^']+)'\s*,\s*'[^']*'\s*\)", html),
            HtmlParsingSupport.FirstCapture(@"作者\s*[：:]\s*([^\s|，,。]{1,16})(?:\s|[|，,。])", text));
    }

    private static string? LinkedAuthor(IDocument document)
    {
        foreach (var anchor in document.QuerySelectorAll("a[href*='/author/'], a[href*='/zuojia/']"))
        {
            var value = HtmlParsingSupport.Normalize(anchor.TextContent);
            if (value.Length > 0 && value is not ("作者" or "作家目录"))
            {
                return value;
            }
        }
        return null;
    }

    private static string? ScopedAuthor(IDocument document)
    {
        foreach (var element in document.QuerySelectorAll(
                     ".book-describe p, .bookname, .info p, .border_b, [class*=book-info]"))
        {
            var author = HtmlParsingSupport.FirstCapture(@"作者\s*[：:]\s*([^|，,。]+)", element.TextContent);
            var normalized = NormalizeMetadata(author);
            if (normalized is not null)
            {
                return normalized;
            }
        }
        return null;
    }

    private static string? VisibleBookTitle(IDocument document)
    {
        foreach (var selector in new[]
                 {
                     "#bookname", ".book-describe h1", ".bookname h1", ".info .top h1", ".novel_info h1"
                 })
        {
            var element = document.QuerySelector(selector);
            if (element is null)
            {
                continue;
            }
            var ownText = OwnText(element);
            var value = string.IsNullOrWhiteSpace(ownText) ? element.TextContent : ownText;
            if (!string.IsNullOrWhiteSpace(value))
            {
                return value;
            }
        }

        return document.QuerySelectorAll(
                ".breadcrumb a[href*='/book/'], .breadcrumb a[href*='/read/'], " +
                ".breadcrumb a[href*='/novel/chapters/'], .bcrumb a[rel='category tag']")
            .LastOrDefault()?.TextContent;
    }

    private static string? CatalogHeading(IDocument document)
    {
        var visible = NormalizeMetadata(VisibleBookTitle(document));
        if (visible is not null)
        {
            return visible;
        }

        foreach (var element in document.QuerySelectorAll("h1:not(#logo) > a, h1:not(#logo)"))
        {
            var ownText = OwnText(element);
            var value = NormalizeMetadata(string.IsNullOrWhiteSpace(ownText) ? element.TextContent : ownText);
            if (value is not null)
            {
                return value;
            }
        }
        return null;
    }

    private static string OwnText(IElement element) =>
        HtmlParsingSupport.Normalize(string.Concat(element.ChildNodes.OfType<IText>().Select(text => text.Data)));

    private static string? MetaContent(string name, IDocument document) =>
        NormalizeMetadata(document.QuerySelector($"meta[name='{name}'], meta[property='{name}']")?.GetAttribute("content"));

    private static string? BookTitleFromDecoratedTitle(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return null;
        }
        var quoted = HtmlParsingSupport.FirstCapture("《([^》]+)》", value);
        if (!string.IsNullOrWhiteSpace(quoted))
        {
            return quoted;
        }
        var prefix = HtmlParsingSupport.FirstCapture(@"^(.+?)\s+第\s*\d+\s*[章回节]", value);
        if (!string.IsNullOrWhiteSpace(prefix))
        {
            return prefix;
        }
        var pieces = value.Split('_');
        return pieces.Length > 1 ? pieces[1] : null;
    }

    private static string? FirstNonempty(params string?[] values) =>
        values.Select(NormalizeMetadata).FirstOrDefault(value => value is not null);

    private static string? NormalizeMetadata(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return null;
        }
        var normalized = HtmlParsingSupport.Normalize(value).Trim('《', '》');
        return normalized.Length == 0 ? null : normalized;
    }

    private static string CleanedChapterTitle(string title) =>
        Regex.Replace(
            HtmlParsingSupport.Normalize(title),
            @"\s*[（(]第\s*\d+\s*页\s*/\s*共\s*\d+\s*页[）)]\s*$",
            string.Empty,
            RegexOptions.CultureInvariant);

    private static string? CleanedParagraph(string paragraph)
    {
        var text = HtmlParsingSupport.Normalize(paragraph);
        if (text.Length <= 1 || IsChapterNavigationParagraph(text) || IsReaderModeNotice(text))
        {
            return null;
        }

        var noise = new[]
        {
            "本站最新网址", "您阅读的小说来自", "小主，这个章节后面还有",
            "加入书签，方便阅读", "点击下一页继续阅读"
        };
        if (noise.Any(text.Contains))
        {
            return null;
        }
        if (text.Length < 80 && text.Contains("落`霞", StringComparison.Ordinal)
            && text.Contains("读`书", StringComparison.Ordinal))
        {
            return null;
        }
        if (text.Length > 20 && text.EndsWith("落霞", StringComparison.Ordinal))
        {
            text = text[..^2].Trim();
        }
        return text;
    }

    private static bool IsChapterNavigationParagraph(string text)
    {
        var compact = Regex.Replace(text, @"\s+", string.Empty, RegexOptions.CultureInvariant);
        if (Regex.IsMatch(
                compact,
                @"^(?:上一章|下一章|上一章节|下一章节|前一章|后一章)[：:].+$",
                RegexOptions.CultureInvariant))
        {
            return true;
        }

        var labels = new[]
        {
            "上一章节", "下一章节", "返回目录", "章节目录", "全部章节",
            "上一章", "下一章", "前一章", "后一章",
            "上一页", "下一页", "上页", "下页", "目录", "书页", "首页"
        };
        var remainder = text;
        foreach (var label in labels)
        {
            remainder = remainder.Replace(label, string.Empty, StringComparison.Ordinal);
        }
        if (remainder.Length == text.Length)
        {
            return false;
        }
        return remainder.All(character => char.IsWhiteSpace(character)
            || char.IsPunctuation(character)
            || char.IsSymbol(character));
    }

    private static bool IsReaderModeNotice(string text)
    {
        var compact = Regex.Replace(text.Replace("/", string.Empty).Replace("\\", string.Empty), @"\s+", string.Empty);
        return compact.Contains("浏览器", StringComparison.Ordinal)
            && compact.Contains("阅读模式", StringComparison.Ordinal)
            && compact.Contains("退出", StringComparison.Ordinal)
            && compact.Contains("转码阅读", StringComparison.Ordinal);
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
            var title = ChapterTitleFromAnchor(anchor);
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
        || new[] { "序章", "序言", "楔子", "引子", "尾声", "后记", "番外" }.Any(title.Contains);

    private static string ChapterTitleFromAnchor(IElement anchor)
    {
        var heading = anchor.QuerySelector("h1, h2, h3, h4, h5, h6");
        var title = heading?.TextContent;
        return HtmlParsingSupport.Normalize(string.IsNullOrWhiteSpace(title) ? anchor.TextContent : title);
    }

    private static Uri? NavigationUrl(
        IDocument document,
        IEnumerable<string> labels,
        string? rel,
        IEnumerable<string> fallbackSelectors,
        Uri baseUri)
    {
        if (rel is not null)
        {
            var relatedAnchor = document.QuerySelectorAll("a")
                .FirstOrDefault(candidate => candidate.GetAttribute("rel")
                    ?.Split(' ', StringSplitOptions.RemoveEmptyEntries)
                    .Contains(rel, StringComparer.OrdinalIgnoreCase) == true);
            var related = relatedAnchor is null ? null : HtmlParsingSupport.AbsoluteUrl(relatedAnchor, baseUri);
            if (related is not null)
            {
                return related;
            }
        }

        var labelArray = labels.ToArray();
        var exact = HtmlParsingSupport.Link(document, labelArray, baseUri);
        if (exact is not null)
        {
            return exact;
        }

        foreach (var anchor in document.QuerySelectorAll("a"))
        {
            var compactLabel = Regex.Replace(HtmlParsingSupport.Normalize(anchor.TextContent), @"\s+", string.Empty);
            if (labelArray.Any(label => compactLabel.StartsWith(
                    Regex.Replace(label, @"\s+", string.Empty),
                    StringComparison.Ordinal)))
            {
                var url = HtmlParsingSupport.AbsoluteUrl(anchor, baseUri);
                if (url is not null)
                {
                    return url;
                }
            }
        }

        foreach (var selector in fallbackSelectors)
        {
            var anchor = document.QuerySelector(selector);
            var url = anchor is null ? null : HtmlParsingSupport.AbsoluteUrl(anchor, baseUri);
            if (url is not null)
            {
                return url;
            }
        }
        return null;
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
}
