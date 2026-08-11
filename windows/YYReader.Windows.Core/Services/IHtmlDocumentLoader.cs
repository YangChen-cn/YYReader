using YYReader.Windows.Core.Parsing;

namespace YYReader.Windows.Core.Services;

public interface IHtmlDocumentLoader
{
    void BeginOperation();
    Task<LoadedHtml> LoadAsync(Uri url, CancellationToken cancellationToken = default);
}

public interface IRenderedDomFallbackLoading : IHtmlDocumentLoader
{
    Task<LoadedHtml> LoadRenderedDomAsync(Uri url, CancellationToken cancellationToken = default);
    void PromoteRenderedDomHost(Uri url);
}
