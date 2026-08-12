using System.Collections.Concurrent;
using YYReader.Windows.Core.Models;
using YYReader.Windows.Core.Parsing;

namespace YYReader.Windows.Core.Services;

public sealed class HybridHtmlLoader : IRenderedDomFallbackLoading
{
    private readonly IHtmlDocumentLoader _staticLoader;
    private readonly IRenderedDomFallbackLoading _browserLoader;
    private readonly ConcurrentDictionary<string, byte> _browserPreferredHosts = new(StringComparer.OrdinalIgnoreCase);

    public HybridHtmlLoader(IHtmlDocumentLoader staticLoader, IRenderedDomFallbackLoading browserLoader)
    {
        _staticLoader = staticLoader;
        _browserLoader = browserLoader;
    }

    public IReadOnlyCollection<string> BrowserPreferredHosts => _browserPreferredHosts.Keys.ToArray();

    public void BeginOperation()
    {
        _staticLoader.BeginOperation();
        _browserLoader.BeginOperation();
    }

    public async Task<LoadedHtml> LoadAsync(Uri url, CancellationToken cancellationToken = default)
    {
        if (!UrlCanonicalizer.IsHttp(url))
        {
            throw new NovelParsingException(NovelParsingErrorKind.UnsupportedUrl);
        }

        if (_browserPreferredHosts.ContainsKey(url.DnsSafeHost))
        {
            return await _browserLoader.LoadAsync(url, cancellationToken).ConfigureAwait(false);
        }

        try
        {
            return await _staticLoader.LoadAsync(url, cancellationToken).ConfigureAwait(false);
        }
        catch (HtmlLoadException ex) when (ShouldUseBrowserFallback(ex))
        {
            _browserPreferredHosts.TryAdd(url.DnsSafeHost, 0);
            return await _browserLoader.LoadAsync(url, cancellationToken).ConfigureAwait(false);
        }
    }

    public Task<LoadedHtml> LoadRenderedDomAsync(Uri url, CancellationToken cancellationToken = default) =>
        _browserLoader.LoadRenderedDomAsync(url, cancellationToken);

    public void PromoteRenderedDomHost(Uri url) => _browserPreferredHosts.TryAdd(url.DnsSafeHost, 0);

    private static bool ShouldUseBrowserFallback(HtmlLoadException exception) =>
        exception.Kind == HtmlLoadErrorKind.VerificationRequired
        || (exception.Kind == HtmlLoadErrorKind.HttpStatus && exception.StatusCode == 403);
}
