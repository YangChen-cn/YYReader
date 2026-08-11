namespace YYReader.Windows.Core.Services;

public enum HtmlLoadErrorKind
{
    InvalidResponse,
    HttpStatus,
    RateLimited,
    VerificationRequired,
    VerificationFailed,
    VerificationTimedOut,
    RequestTimedOut,
    UndecodableText
}

public sealed class HtmlLoadException : Exception
{
    public HtmlLoadException(
        HtmlLoadErrorKind kind,
        string? message = null,
        int? statusCode = null,
        int? retryAfterSeconds = null)
        : base(message ?? MessageFor(kind, statusCode, retryAfterSeconds))
    {
        Kind = kind;
        StatusCode = statusCode;
        RetryAfterSeconds = retryAfterSeconds;
    }

    public HtmlLoadErrorKind Kind { get; }
    public int? StatusCode { get; }
    public int? RetryAfterSeconds { get; }

    private static string MessageFor(HtmlLoadErrorKind kind, int? statusCode, int? retryAfterSeconds) => kind switch
    {
        HtmlLoadErrorKind.InvalidResponse => "网站返回了无法识别的响应。",
        HtmlLoadErrorKind.HttpStatus => $"网页请求失败（HTTP {statusCode}）。",
        HtmlLoadErrorKind.RateLimited => retryAfterSeconds is null
            ? "网站请求过于频繁，请稍后手动重试。"
            : $"网站请求过于频繁，请在约 {retryAfterSeconds} 秒后手动重试。",
        HtmlLoadErrorKind.VerificationRequired => "网站要求完成浏览器验证。",
        HtmlLoadErrorKind.VerificationFailed => "网站验证失败。",
        HtmlLoadErrorKind.VerificationTimedOut => "网站验证等待超时，导入已停止。请稍后重试。",
        HtmlLoadErrorKind.RequestTimedOut => "网页长时间没有完成加载，操作已停止。请稍后重试。",
        HtmlLoadErrorKind.UndecodableText => "无法识别网页的文字编码。",
        _ => "网页加载失败。"
    };
}
