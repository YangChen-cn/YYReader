using System.Net;
using System.Text.Json;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml.Controls;
using Microsoft.Web.WebView2.Core;
using global::Windows.Foundation;
using YYReader.Windows.Core.Models;
using YYReader.Windows.Core.Parsing;
using YYReader.Windows.Core.Services;

namespace YYReader.Windows.Services;

public sealed class WebView2HtmlLoader : IRenderedDomFallbackLoading
{
    private readonly WebView2 _webView;
    private readonly DispatcherQueue _dispatcherQueue;
    private readonly HttpHtmlLoader _staticLoader;
    private readonly string _userDataFolder;
    private readonly SemaphoreSlim _loadGate = new(1, 1);
    private readonly Dictionary<string, int> _verificationAttempts = new(StringComparer.OrdinalIgnoreCase);
    private CoreWebView2? _coreWebView;

    public WebView2HtmlLoader(WebView2 webView, HttpHtmlLoader staticLoader)
    {
        _webView = webView;
        _dispatcherQueue = webView.DispatcherQueue;
        _staticLoader = staticLoader;
        _userDataFolder = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "YYReader",
            "WebView2");
        Directory.CreateDirectory(_userDataFolder);
    }

    public Func<Uri, Task<bool>>? VerificationRequested { get; set; }

    public void BeginOperation() => _verificationAttempts.Clear();

    public Task<LoadedHtml> LoadAsync(Uri url, CancellationToken cancellationToken = default) =>
        LoadRenderedDomAsync(url, cancellationToken);

    public async Task<LoadedHtml> LoadRenderedDomAsync(Uri url, CancellationToken cancellationToken = default)
    {
        if (!UrlCanonicalizer.IsHttp(url))
        {
            throw new NovelParsingException(NovelParsingErrorKind.UnsupportedUrl);
        }

        await _loadGate.WaitAsync(cancellationToken).ConfigureAwait(true);
        try
        {
            return await RunOnUiThreadAsync(
                () => LoadRenderedDomOnUiThreadAsync(url, cancellationToken),
                cancellationToken).ConfigureAwait(false);
        }
        finally
        {
            _loadGate.Release();
        }
    }

    public void PromoteRenderedDomHost(Uri url)
    {
    }

    private async Task<LoadedHtml> LoadRenderedDomOnUiThreadAsync(
        Uri url,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        await EnsureCoreWebViewAsync().ConfigureAwait(true);
        var finalUri = await NavigateAsync(url, cancellationToken).ConfigureAwait(true);
        var html = await ReadHtmlAsync().ConfigureAwait(true);

        if (HtmlChallengeDetector.IsChallenge(html))
        {
            var host = finalUri.DnsSafeHost;
            var attempt = _verificationAttempts.GetValueOrDefault(host) + 1;
            _verificationAttempts[host] = attempt;
            if (attempt > 1 || VerificationRequested is null)
            {
                throw new HtmlLoadException(
                    HtmlLoadErrorKind.VerificationFailed,
                    "同一次操作中网站重复要求人工验证，已停止以避免验证循环。");
            }

            var completed = await VerificationRequested(finalUri).ConfigureAwait(true);
            if (!completed)
            {
                throw new HtmlLoadException(HtmlLoadErrorKind.VerificationFailed, "已取消网站验证。");
            }

            html = await ReadHtmlAsync().ConfigureAwait(true);
            if (HtmlChallengeDetector.IsChallenge(html))
            {
                throw new HtmlLoadException(HtmlLoadErrorKind.VerificationFailed, "验证完成后网页仍未提供正文。");
            }
        }

        await SynchronizeCookiesAsync(finalUri).ConfigureAwait(true);
        return new LoadedHtml(url, finalUri, html, HtmlRetrievalKind.WebView2);
    }

    private Task<T> RunOnUiThreadAsync<T>(
        Func<Task<T>> operation,
        CancellationToken cancellationToken)
    {
        if (_dispatcherQueue.HasThreadAccess)
        {
            return operation();
        }

        cancellationToken.ThrowIfCancellationRequested();
        var completion = new TaskCompletionSource<T>(TaskCreationOptions.RunContinuationsAsynchronously);
        if (!_dispatcherQueue.TryEnqueue(async () =>
            {
                try
                {
                    cancellationToken.ThrowIfCancellationRequested();
                    completion.TrySetResult(await operation().ConfigureAwait(true));
                }
                catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
                {
                    completion.TrySetCanceled(cancellationToken);
                }
                catch (Exception ex)
                {
                    completion.TrySetException(ex);
                }
            }))
        {
            completion.TrySetException(new InvalidOperationException("无法切换到 WebView2 所在的 UI 线程。"));
        }

        return completion.Task;
    }

    private async Task EnsureCoreWebViewAsync()
    {
        if (_coreWebView is not null)
        {
            return;
        }

        var environment = await CoreWebView2Environment.CreateWithOptionsAsync(null, _userDataFolder, null);
        await _webView.EnsureCoreWebView2Async(environment);
        _coreWebView = _webView.CoreWebView2
            ?? throw new InvalidOperationException("WebView2 初始化失败。");
        _coreWebView.Settings.IsStatusBarEnabled = false;
        _coreWebView.Settings.AreDefaultContextMenusEnabled = true;
    }

    private async Task<Uri> NavigateAsync(Uri url, CancellationToken cancellationToken)
    {
        var completion = new TaskCompletionSource<CoreWebView2NavigationCompletedEventArgs>(
            TaskCreationOptions.RunContinuationsAsynchronously);
        TypedEventHandler<WebView2, CoreWebView2NavigationCompletedEventArgs> handler = (_, args) =>
            completion.TrySetResult(args);
        _webView.NavigationCompleted += handler;
        try
        {
            _webView.Source = url;
            var result = await completion.Task.WaitAsync(TimeSpan.FromSeconds(30), cancellationToken).ConfigureAwait(true);
            if (!result.IsSuccess)
            {
                throw new HtmlLoadException(HtmlLoadErrorKind.InvalidResponse, result.WebErrorStatus.ToString());
            }
            return _webView.Source ?? url;
        }
        catch (TimeoutException)
        {
            throw new HtmlLoadException(HtmlLoadErrorKind.RequestTimedOut);
        }
        finally
        {
            _webView.NavigationCompleted -= handler;
        }
    }

    private async Task<string> ReadHtmlAsync()
    {
        var json = await _coreWebView!.ExecuteScriptAsync("document.documentElement.outerHTML");
        var html = JsonSerializer.Deserialize<string>(json);
        return string.IsNullOrWhiteSpace(html)
            ? throw new HtmlLoadException(HtmlLoadErrorKind.InvalidResponse)
            : html;
    }

    private async Task SynchronizeCookiesAsync(Uri url)
    {
        var cookies = await _coreWebView!.CookieManager.GetCookiesAsync(url.AbsoluteUri);
        var translated = new List<Cookie>();
        foreach (var cookie in cookies)
        {
            try
            {
                translated.Add(new Cookie(cookie.Name, cookie.Value, cookie.Path, cookie.Domain));
            }
            catch (CookieException)
            {
            }
        }
        _staticLoader.AddCookies(translated);
    }
}
