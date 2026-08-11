using System.Net;
using System.Net.Http.Headers;
using System.Text;
using YYReader.Windows.Core.Models;
using YYReader.Windows.Core.Parsing;

namespace YYReader.Windows.Core.Services;

public sealed class HttpHtmlLoader : IHtmlDocumentLoader
{
    private readonly HttpClient _client;
    private readonly HostRateLimiter _rateLimiter;

    public HttpHtmlLoader(HttpClient? client = null, HostRateLimiter? rateLimiter = null)
    {
        CookieContainer = new CookieContainer();
        if (client is null)
        {
            var handler = new HttpClientHandler
            {
                AutomaticDecompression = DecompressionMethods.All,
                CookieContainer = CookieContainer,
                UseCookies = true,
                AllowAutoRedirect = true
            };
            _client = new HttpClient(handler)
            {
                Timeout = TimeSpan.FromSeconds(60)
            };
        }
        else
        {
            _client = client;
        }

        _client.DefaultRequestHeaders.Accept.Add(new MediaTypeWithQualityHeaderValue("text/html"));
        _client.DefaultRequestHeaders.Accept.Add(new MediaTypeWithQualityHeaderValue("application/xhtml+xml"));
        _client.DefaultRequestHeaders.AcceptLanguage.ParseAdd("zh-CN,zh;q=0.9,en;q=0.7");
        if (!_client.DefaultRequestHeaders.UserAgent.Any())
        {
            _client.DefaultRequestHeaders.UserAgent.ParseAdd("YYReader.Windows/1.0");
        }

        _rateLimiter = rateLimiter ?? new HostRateLimiter();
        Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);
    }

    public CookieContainer CookieContainer { get; }

    public void BeginOperation()
    {
    }

    public async Task<LoadedHtml> LoadAsync(Uri url, CancellationToken cancellationToken = default)
    {
        if (!UrlCanonicalizer.IsHttp(url))
        {
            throw new NovelParsingException(NovelParsingErrorKind.UnsupportedUrl);
        }

        await _rateLimiter.WaitAsync(url, cancellationToken).ConfigureAwait(false);
        using var request = new HttpRequestMessage(HttpMethod.Get, url);
        using var response = await _client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cancellationToken)
            .ConfigureAwait(false);

        if (response.Headers.TryGetValues("cf-mitigated", out var challengeHeaders)
            && challengeHeaders.Any(value => value.Equals("challenge", StringComparison.OrdinalIgnoreCase)))
        {
            throw new HtmlLoadException(HtmlLoadErrorKind.VerificationRequired);
        }

        var retryAfter = RetryAfterSeconds(response.Headers.RetryAfter);
        if ((int)response.StatusCode == 429)
        {
            throw new HtmlLoadException(HtmlLoadErrorKind.RateLimited, retryAfterSeconds: retryAfter);
        }

        var bytes = await response.Content.ReadAsByteArrayAsync(cancellationToken).ConfigureAwait(false);
        if ((int)response.StatusCode == 403 && HtmlChallengeDetector.IsChallenge(DecodeUtf8Sample(bytes)))
        {
            throw new HtmlLoadException(HtmlLoadErrorKind.VerificationRequired);
        }

        if (!response.IsSuccessStatusCode)
        {
            throw new HtmlLoadException(HtmlLoadErrorKind.HttpStatus, statusCode: (int)response.StatusCode);
        }

        var html = Decode(bytes, response.Content.Headers.ContentType?.CharSet);
        if (html is null)
        {
            throw new HtmlLoadException(HtmlLoadErrorKind.UndecodableText);
        }
        if (HtmlChallengeDetector.IsChallenge(html))
        {
            throw new HtmlLoadException(HtmlLoadErrorKind.VerificationRequired);
        }

        var finalUri = response.RequestMessage?.RequestUri ?? url;
        return new LoadedHtml(url, finalUri, html, HtmlRetrievalKind.UrlSession);
    }

    public void AddCookies(IEnumerable<Cookie> cookies)
    {
        foreach (var cookie in cookies)
        {
            try
            {
                CookieContainer.Add(cookie);
            }
            catch (CookieException)
            {
                // A cookie that cannot be represented by CookieContainer is not required for parsing.
            }
        }
    }

    private static string? Decode(byte[] bytes, string? charset)
    {
        var encodingName = charset?.Trim().Trim('"').ToLowerInvariant();
        Encoding encoding;
        try
        {
            encoding = encodingName switch
            {
                "gbk" or "gb2312" or "gb18030" => Encoding.GetEncoding("gb18030"),
                "big5" => Encoding.GetEncoding("big5"),
                "iso-8859-1" or "latin1" => Encoding.Latin1,
                _ => new UTF8Encoding(false, true)
            };
            return encoding.GetString(bytes);
        }
        catch (DecoderFallbackException)
        {
            return Encoding.UTF8.GetString(bytes);
        }
    }

    private static string DecodeUtf8Sample(byte[] bytes) =>
        Encoding.UTF8.GetString(bytes, 0, Math.Min(bytes.Length, 16_384));

    private static int? RetryAfterSeconds(RetryConditionHeaderValue? retryAfter)
    {
        if (retryAfter is null)
        {
            return null;
        }

        if (retryAfter.Delta is { } delta)
        {
            return Math.Max(0, (int)Math.Ceiling(delta.TotalSeconds));
        }
        if (retryAfter.Date is { } date)
        {
            return Math.Max(0, (int)Math.Ceiling((date - DateTimeOffset.UtcNow).TotalSeconds));
        }

        return null;
    }
}
