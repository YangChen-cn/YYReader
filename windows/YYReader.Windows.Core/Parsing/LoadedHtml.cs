namespace YYReader.Windows.Core.Parsing;

public sealed record LoadedHtml(
    Uri RequestedUri,
    Uri FinalUri,
    string Html,
    HtmlRetrievalKind RetrievalKind);

public enum HtmlRetrievalKind
{
    UrlSession,
    WebView2
}
