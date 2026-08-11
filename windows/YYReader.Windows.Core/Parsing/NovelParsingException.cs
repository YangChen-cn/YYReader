namespace YYReader.Windows.Core.Parsing;

public enum NovelParsingErrorKind
{
    UnsupportedUrl,
    NoReadableContent,
    MissingCatalog,
    PaginationLimit,
    PaginationLoop,
    CatalogRefreshTimedOut
}

public sealed class NovelParsingException : Exception
{
    public NovelParsingException(NovelParsingErrorKind kind)
        : this(kind, MessageFor(kind))
    {
    }

    public NovelParsingException(NovelParsingErrorKind kind, string message)
        : base(message)
    {
        Kind = kind;
    }

    public NovelParsingErrorKind Kind { get; }

    private static string MessageFor(NovelParsingErrorKind kind) => kind switch
    {
        NovelParsingErrorKind.UnsupportedUrl => "只支持 HTTP 或 HTTPS 小说网页。",
        NovelParsingErrorKind.NoReadableContent => "没有识别到可阅读的章节正文。",
        NovelParsingErrorKind.MissingCatalog => "没有识别到小说目录页。",
        NovelParsingErrorKind.PaginationLimit => "网页分页数量异常，已停止继续加载。",
        NovelParsingErrorKind.PaginationLoop => "网页分页出现循环，已停止继续加载。",
        NovelParsingErrorKind.CatalogRefreshTimedOut => "目录刷新耗时过长，已自动停止。已缓存章节不受影响，请稍后重试。",
        _ => "小说页面解析失败。"
    };
}
