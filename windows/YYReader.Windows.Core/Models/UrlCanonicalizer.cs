using System.Text;
using System.Text.RegularExpressions;

namespace YYReader.Windows.Core.Models;

public static partial class UrlCanonicalizer
{
    private static readonly string[] ExplicitBookCollections =
    {
        "book", "books", "novel", "novels", "serial", "fiction", "story", "stories"
    };

    public static Uri? NormalizeInput(string input)
    {
        var trimmed = input.Trim();
        if (trimmed.Length == 0)
        {
            return null;
        }

        var candidate = trimmed.Contains("://", StringComparison.Ordinal)
            ? trimmed
            : $"https://{trimmed}";
        return Uri.TryCreate(candidate, UriKind.Absolute, out var uri)
               && IsHttp(uri)
            ? Canonicalize(uri)
            : null;
    }

    public static Uri Canonicalize(string value)
    {
        if (!Uri.TryCreate(value, UriKind.Absolute, out var uri))
        {
            throw new UriFormatException($"Invalid URL: {value}");
        }

        return Canonicalize(uri);
    }

    public static Uri Canonicalize(Uri uri)
    {
        var builder = new UriBuilder(uri)
        {
            Scheme = uri.Scheme.ToLowerInvariant(),
            Host = uri.DnsSafeHost.ToLowerInvariant(),
            Fragment = string.Empty
        };

        if ((builder.Scheme == Uri.UriSchemeHttp && builder.Port == 80)
            || (builder.Scheme == Uri.UriSchemeHttps && builder.Port == 443))
        {
            builder.Port = -1;
        }

        if (builder.Path.Length == 0)
        {
            builder.Path = "/";
        }

        return builder.Uri;
    }

    public static Uri CanonicalizeChapter(string value) =>
        CanonicalizeChapter(Canonicalize(value));

    public static Uri CanonicalizeChapter(Uri uri)
    {
        var canonical = Canonicalize(uri);
        var match = ChapterPageSuffixRegex().Match(canonical.AbsolutePath);
        if (!match.Success)
        {
            return canonical;
        }

        var builder = new UriBuilder(canonical)
        {
            Path = $"{match.Groups[1].Value}.html"
        };
        return builder.Uri;
    }

    public static Uri SourceBookIdentityForChapter(Uri chapterUrl, string? bookTitle, string? author)
    {
        var canonicalChapter = CanonicalizeChapter(chapterUrl);
        var segments = canonicalChapter.AbsolutePath
            .Split('/', StringSplitOptions.RemoveEmptyEntries);

        if (segments.Length >= 3
            && ExplicitBookCollections.Contains(segments[^3], StringComparer.OrdinalIgnoreCase))
        {
            var builder = new UriBuilder(canonicalChapter)
            {
                Path = $"/{string.Join('/', segments.Take(segments.Length - 1))}/",
                Query = string.Empty,
                Fragment = string.Empty
            };
            return builder.Uri;
        }

        var fallback = new UriBuilder("yyreader-book", canonicalChapter.DnsSafeHost)
        {
            Path = $"/{NormalizeIdentityComponent(bookTitle ?? "未命名小说")}/{NormalizeIdentityComponent(author ?? "未知作者")}",
            Query = string.Empty,
            Fragment = string.Empty
        };
        return fallback.Uri;
    }

    public static bool IsHttp(Uri uri) =>
        uri.Scheme.Equals(Uri.UriSchemeHttp, StringComparison.OrdinalIgnoreCase)
        || uri.Scheme.Equals(Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase);

    public static bool IsSameOrigin(Uri candidate, Uri origin)
    {
        static int EffectivePort(Uri value) =>
            value.IsDefaultPort
                ? value.Scheme.Equals(Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase) ? 443 : 80
                : value.Port;

        return string.Equals(candidate.Scheme, origin.Scheme, StringComparison.OrdinalIgnoreCase)
            && string.Equals(candidate.DnsSafeHost, origin.DnsSafeHost, StringComparison.OrdinalIgnoreCase)
            && EffectivePort(candidate) == EffectivePort(origin);
    }

    private static string NormalizeIdentityComponent(string value) =>
        string.Join(' ', value
            .Replace('\u00a0', ' ')
            .Replace('\u3000', ' ')
            .Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries))
            .Normalize(NormalizationForm.FormKC);

    [GeneratedRegex(@"^(.*\/\d+\/\d+)/\d+\.html$", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex ChapterPageSuffixRegex();
}
