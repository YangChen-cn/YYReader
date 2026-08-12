using Microsoft.VisualStudio.TestTools.UnitTesting;
using YYReader.Windows.Core.Models;
using YYReader.Windows.Core.Parsing;
using YYReader.Windows.Core.Reading;
using YYReader.Windows.Core.Persistence;
using YYReader.Windows.Core.Services;
using YYReader.Windows.Services;

namespace YYReader.Windows.Tests;

[TestClass]
public sealed class ContinuousReadingTests
{
    [TestMethod]
    public async Task GenericTailProbeAttachesNextChapterWithoutRefreshingCatalog()
    {
        var catalogUrl = new Uri("https://example.com/book/");
        var chapter100Url = new Uri("https://example.com/book/100.html");
        var chapter101Url = new Uri("https://example.com/book/101.html");
        var loader = new TailProbeLoader(catalogUrl, chapter100Url, chapter101Url, qidiy: false);
        var (store, databasePath) = await CreateStoreAsync(loader, catalogUrl, chapter100Url);

        try
        {
            var statuses = new List<NextChapterPreparationStatus>();
            var result = await store.PrepareNextChapterAsync(
                explicitRetry: false,
                status => statuses.Add(status));

            Assert.AreEqual(NextChapterPreparationStatus.Attached, result.Status);
            Assert.AreEqual(chapter101Url.AbsoluteUri, result.Chapter!.SourceUrl);
            Assert.IsTrue(store.ReaderSession.Entries.Any(entry => entry.Chapter.SourceUrl == chapter101Url.AbsoluteUri));
            CollectionAssert.Contains(statuses, NextChapterPreparationStatus.CheckingLatest);
            Assert.AreNotEqual(NextChapterPreparationStatus.ConfirmedLatest, result.Status);
            Assert.AreEqual(0, loader.CatalogRequests);
            Assert.AreEqual(1, loader.TailRequests);
            Assert.AreEqual(1, loader.NextRequests);
        }
        finally
        {
            await store.DisposeAsync();
            DeleteDatabase(databasePath);
        }
    }

    [TestMethod]
    public async Task QidiyTailProbeAttachesNextChapterWithoutRefreshingCatalog()
    {
        var catalogUrl = new Uri("https://www.qidiy.com/book/42/");
        var chapter100Url = new Uri("https://www.qidiy.com/book/42/100.html");
        var chapter101Url = new Uri("https://www.qidiy.com/book/42/101.html");
        var loader = new TailProbeLoader(catalogUrl, chapter100Url, chapter101Url, qidiy: true);
        var (store, databasePath) = await CreateStoreAsync(loader, catalogUrl, chapter100Url);

        try
        {
            var result = await store.PrepareNextChapterAsync();

            Assert.AreEqual(NextChapterPreparationStatus.Attached, result.Status);
            Assert.AreEqual(chapter101Url.AbsoluteUri, result.Chapter!.SourceUrl);
            Assert.AreEqual(0, loader.CatalogRequests);
            Assert.AreEqual(1, loader.TailRequests);
            Assert.AreEqual(1, loader.NextRequests);
        }
        finally
        {
            await store.DisposeAsync();
            DeleteDatabase(databasePath);
        }
    }

    [TestMethod]
    public async Task SuccessfulTailProbeWithoutNextConfirmsLatestWithoutRefreshingCatalog()
    {
        var catalogUrl = new Uri("https://example.com/book/");
        var chapter100Url = new Uri("https://example.com/book/100.html");
        var loader = new TailProbeLoader(catalogUrl, chapter100Url, nextUrl: null, qidiy: false);
        var (store, databasePath) = await CreateStoreAsync(loader, catalogUrl, chapter100Url);

        try
        {
            var result = await store.PrepareNextChapterAsync();

            Assert.AreEqual(NextChapterPreparationStatus.ConfirmedLatest, result.Status);
            Assert.AreEqual(0, loader.CatalogRequests);
            Assert.AreEqual(1, loader.TailRequests);
        }
        finally
        {
            await store.DisposeAsync();
            DeleteDatabase(databasePath);
        }
    }

    [TestMethod]
    public async Task TailProbeFailureDoesNotRefreshCatalogAndPreservesCause()
    {
        var catalogUrl = new Uri("https://example.com/book/");
        var chapter100Url = new Uri("https://example.com/book/100.html");
        var loader = new TailProbeLoader(
            catalogUrl, chapter100Url, nextUrl: null, qidiy: false, failTail: true);
        var (store, databasePath) = await CreateStoreAsync(loader, catalogUrl, chapter100Url);

        try
        {
            var result = await store.PrepareNextChapterAsync();

            Assert.AreEqual(NextChapterPreparationStatus.Failed, result.Status);
            StringAssert.Contains(result.Message, "HTTP 403");
            Assert.AreEqual(0, loader.CatalogRequests);
            Assert.AreEqual(1, loader.TailRequests);
        }
        finally
        {
            await store.DisposeAsync();
            DeleteDatabase(databasePath);
        }
    }

    [TestMethod]
    public async Task SameBookCatalogRefreshIsSingleFlight()
    {
        var catalogUrl = new Uri("https://example.com/book/");
        var chapter100Url = new Uri("https://example.com/book/100.html");
        var loader = new CatalogLoader(catalogUrl, chapter100Url, includeNewChapter: false, catalogDelay: TimeSpan.FromMilliseconds(120));
        var (store, databasePath) = await CreateStoreAsync(loader, catalogUrl, chapter100Url);

        try
        {
            var results = await Task.WhenAll(
                store.RefreshSelectedCatalogAsync(),
                store.RefreshSelectedCatalogAsync());

            CollectionAssert.AreEqual(new[] { true, true }, results);
            Assert.AreEqual(1, loader.CatalogRequests);
        }
        finally
        {
            await store.DisposeAsync();
            DeleteDatabase(databasePath);
        }
    }

    [TestMethod]
    public void ContinuationStateDoesNotReprobeAfterLatestOrFailureUntilRearmed()
    {
        var state = new ReaderContinuousLoadState();
        var now = DateTimeOffset.Parse("2026-08-12T00:00:00Z");
        const string chapterUrl = "https://example.com/book/100.html";

        state.ObserveNearEnd(chapterUrl, isNearEnd: true);
        Assert.IsTrue(state.TryBegin(chapterUrl, now));
        state.MarkCheckingLatest();
        state.MarkConfirmedLatest();
        Assert.AreEqual(ReaderContinuousLoadPhase.ConfirmedLatest, state.Phase);
        Assert.IsFalse(state.TryBegin(chapterUrl, now.AddMinutes(1)));

        state.MarkFailed(now);
        Assert.AreEqual(ReaderContinuousLoadPhase.Failed, state.Phase);
        Assert.IsFalse(state.TryBegin(chapterUrl, now.AddMinutes(1)));
        Assert.IsTrue(state.TryBegin(chapterUrl, now.AddMinutes(1), explicitRetry: true));

        state.ObserveNearEnd(chapterUrl, isNearEnd: false);
        state.ObserveNearEnd(chapterUrl, isNearEnd: true);
        Assert.IsTrue(state.TryBegin(chapterUrl, now.AddMinutes(1)));
    }

    [TestMethod]
    public void AppendedTailDoesNotStartAnotherProbeFromLayoutViewChanged()
    {
        var state = new ReaderContinuousLoadState();
        var now = DateTimeOffset.Parse("2026-08-12T00:00:00Z");
        const string chapter100 = "https://example.com/book/100.html";
        const string chapter101 = "https://example.com/book/101.html";

        state.ObserveNearEnd(chapter100, isNearEnd: true);
        Assert.IsTrue(state.TryBegin(chapter100, now));
        state.MarkAttached();

        state.ObserveNearEnd(chapter101, isNearEnd: true);
        Assert.AreEqual(ReaderContinuousLoadPhase.Attached, state.Phase);
        Assert.IsFalse(state.TryBegin(chapter101, now.AddSeconds(1)),
            "append 引发的布局 ViewChanged 不能在同一次 near-end visit 启动下一轮");

        state.ObserveNearEnd(chapter101, isNearEnd: false);
        state.ObserveNearEnd(chapter101, isNearEnd: true);
        Assert.IsTrue(state.TryBegin(chapter101, now.AddSeconds(1)));
    }

    [TestMethod]
    public void ContinuationStatusUsesFixedLayoutDimensionsAndNoVisibilityToggle()
    {
        var xaml = File.ReadAllText(Path.Combine(
            AppContext.BaseDirectory,
            "..", "..", "..", "..", "..", "windows", "YYReader.Windows", "Views", "ReaderPage.xaml"));

        StringAssert.Contains(xaml, "Width=\"300\" Height=\"72\"");
        StringAssert.Contains(xaml, "TextWrapping=\"NoWrap\"");
        Assert.IsFalse(xaml.Contains("ContinuationRetryButton Content=\"重试\" Visibility=", StringComparison.Ordinal));
        Assert.IsFalse(xaml.Contains("ContinuationProgress Visibility=", StringComparison.Ordinal));
    }

    [TestMethod]
    public void CatalogMarksDiskCachedChaptersWithStableIndicatorSpace()
    {
        var xaml = File.ReadAllText(Path.Combine(
            AppContext.BaseDirectory,
            "..", "..", "..", "..", "..", "windows", "YYReader.Windows", "Views", "ReaderPage.xaml"));

        StringAssert.Contains(xaml, "ColumnDefinitions=\"10,*\"");
        StringAssert.Contains(xaml, "OfflineIndicatorOpacity(IsAvailableOffline)");
        Assert.IsFalse(xaml.Contains("OfflineIndicatorOpacity(IsCached)", StringComparison.Ordinal));
    }

    [TestMethod]
    public void AppendingNextChapterDoesNotRestoreVerticalOffset()
    {
        var source = File.ReadAllText(Path.Combine(
            AppContext.BaseDirectory,
            "..", "..", "..", "..", "..", "windows", "YYReader.Windows", "Views", "ReaderPage.xaml.cs"));
        var methodStart = source.IndexOf("private async Task LoadNextContinuousChapterAsync", StringComparison.Ordinal);
        var methodEnd = source.IndexOf("private async void ContinuationRetry_Click", methodStart, StringComparison.Ordinal);
        var method = source[methodStart..methodEnd];

        Assert.IsFalse(method.Contains("ChangeView", StringComparison.Ordinal));
        Assert.IsFalse(method.Contains("stableOffset", StringComparison.Ordinal));
    }

    private static async Task<(LibraryStore Store, string DatabasePath)> CreateStoreAsync(
        IHtmlDocumentLoader loader,
        Uri catalogUrl,
        Uri currentChapterUrl)
    {
        var databasePath = Path.Combine(Path.GetTempPath(), $"yyreader-continuous-{Guid.NewGuid():N}.db");
        var repository = new SqliteLibraryRepository(databasePath);
        await repository.InitializeAsync();
        await repository.UpsertImportAsync(new NovelImportResult(
            "测试小说",
            "测试作者",
            catalogUrl,
            catalogUrl,
            true,
            [new ChapterSeed("第100章", currentChapterUrl, 100)],
            true,
            "第100章",
            currentChapterUrl,
            "当前章节正文。",
            null,
            null));

        var store = new LibraryStore(repository, new NovelImportCoordinator(loader));
        await store.InitializeAsync();
        store.SelectBook(store.Books.Single());
        Assert.IsTrue(await store.EnsureSelectedChapterLoadedAsync());
        return (store, databasePath);
    }

    private static void DeleteDatabase(string path)
    {
        foreach (var suffix in new[] { "", "-wal", "-shm" })
        {
            var candidate = path + suffix;
            if (File.Exists(candidate)) File.Delete(candidate);
        }
    }

    private sealed class TailProbeLoader(
        Uri catalogUrl,
        Uri tailUrl,
        Uri? nextUrl,
        bool qidiy,
        bool failTail = false) : IHtmlDocumentLoader
    {
        public int CatalogRequests { get; private set; }
        public int TailRequests { get; private set; }
        public int NextRequests { get; private set; }

        public void BeginOperation()
        {
        }

        public Task<LoadedHtml> LoadAsync(Uri url, CancellationToken cancellationToken = default)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (url == catalogUrl)
            {
                CatalogRequests++;
                throw new AssertFailedException("连续阅读章末探测不得刷新完整目录");
            }

            if (url == tailUrl)
            {
                TailRequests++;
                if (failTail)
                {
                    throw new HtmlLoadException(HtmlLoadErrorKind.HttpStatus, statusCode: 403);
                }
                return Task.FromResult(new LoadedHtml(
                    url, url, ChapterPage("第100章", nextUrl), HtmlRetrievalKind.UrlSession));
            }

            if (url == nextUrl)
            {
                NextRequests++;
                return Task.FromResult(new LoadedHtml(
                    url, url, ChapterPage("第101章 新章", null), HtmlRetrievalKind.UrlSession));
            }

            throw new HtmlLoadException(HtmlLoadErrorKind.HttpStatus, statusCode: 404);
        }

        private string ChapterPage(string title, Uri? successor)
        {
            var nextLink = successor is null
                ? ""
                : qidiy
                    ? $"<a href='{successor.AbsoluteUri}'>下一章</a>"
                    : $"<a rel='next' href='{successor.AbsoluteUri}'>后一章</a>";
            return qidiy
                ? $$"""
                    <html><head><title>{{title}}</title></head><body>
                      <a href="{{catalogUrl.AbsoluteUri}}">章节列表</a>
                      <a href="https://www.qidiy.com/book/42/">测试小说</a>
                      <h1 class="title">{{title}}</h1>
                      <div id="content">
                        <p>这是用于启迪连续阅读回归测试的自造正文，确保正文密度足够并且不会依赖真实网站内容。</p>
                        <p>第二段自造正文用于验证尾章链接探测能够直接接入下一章，不会扫描多页目录。</p>
                      </div>
                      {{nextLink}}
                    </body></html>
                    """
                : $$"""
                    <html><head><title>{{title}}</title></head><body>
                      <h1>{{title}}</h1>
                      <article>
                        <p>这是用于通用连续阅读回归测试的自造正文，确保正文密度足够并且不会依赖真实网站内容。</p>
                        <p>第二段自造正文用于验证 rel next 导航能够直接接入下一章，不会扫描多页目录。</p>
                      </article>
                      {{nextLink}}
                    </body></html>
                    """;
        }
    }

    private sealed class CatalogLoader(
        Uri catalogUrl,
        Uri currentChapterUrl,
        bool includeNewChapter,
        bool failCatalog = false,
        TimeSpan? catalogDelay = null,
        bool failChapter = false) : IHtmlDocumentLoader
    {
        public int CatalogRequests { get; private set; }

        public void BeginOperation()
        {
        }

        public Task<LoadedHtml> LoadAsync(Uri url, CancellationToken cancellationToken = default)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (url == catalogUrl)
            {
                CatalogRequests++;
                if (failCatalog)
                {
                    throw new HtmlLoadException(HtmlLoadErrorKind.HttpStatus, statusCode: 503);
                }

                if (catalogDelay is { } delay)
                {
                    return DelayedCatalogAsync(url, delay);
                }

                var chapters = includeNewChapter
                    ? "<a href='/book/100.html'>第100章</a><a href='/book/101.html'>第101章</a><a href='/book/102.html'>第102章</a>"
                    : "<a href='/book/100.html'>第100章</a>";
                return Task.FromResult(new LoadedHtml(url, url, CatalogPage(chapters), HtmlRetrievalKind.UrlSession));
            }

            if (url == currentChapterUrl)
            {
                if (failChapter)
                {
                    throw new HtmlLoadException(HtmlLoadErrorKind.HttpStatus, statusCode: 403);
                }
                return Task.FromResult(new LoadedHtml(url, url, ChapterPage("第100章"), HtmlRetrievalKind.UrlSession));
            }

            return Task.FromResult(new LoadedHtml(url, url, ChapterPage("第101章 新章"), HtmlRetrievalKind.UrlSession));
        }

        private async Task<LoadedHtml> DelayedCatalogAsync(Uri url, TimeSpan delay)
        {
            await Task.Delay(delay);
            var chapters = includeNewChapter
                ? "<a href='/book/100.html'>第100章</a><a href='/book/101.html'>第101章</a><a href='/book/102.html'>第102章</a>"
                : "<a href='/book/100.html'>第100章</a>";
            return new LoadedHtml(url, url, CatalogPage(chapters), HtmlRetrievalKind.UrlSession);
        }

        private static string CatalogPage(string chapters) => $$"""
            <html><head><title>测试小说</title></head><body>
              <h1>测试小说</h1>
              <nav class="chapters">{{chapters}}</nav>
            </body></html>
            """;

        private static string ChapterPage(string title) => $$"""
            <html><head><title>{{title}}</title></head><body>
              <h1>{{title}}</h1>
              <article>
                <p>这是用于连续阅读回归测试的自造正文，确保正文密度足够并且不会依赖真实网站内容。</p>
                <p>第二段自造正文用于验证目录刷新后下一章可以被加载、缓存并接入当前阅读会话。</p>
              </article>
            </body></html>
            """;
    }
}
