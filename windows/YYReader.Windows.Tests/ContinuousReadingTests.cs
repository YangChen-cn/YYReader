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
    public async Task GenericTailProbePreparesNextChapterWithoutRefreshingCatalog()
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

            Assert.AreEqual(NextChapterPreparationStatus.Ready, result.Status);
            Assert.AreEqual(chapter101Url.AbsoluteUri, result.Chapter!.SourceUrl);
            Assert.IsFalse(store.ReaderSession.Entries.Any(entry => entry.Chapter.SourceUrl == chapter101Url.AbsoluteUri));
            Assert.IsTrue(store.AttachPreparedNextChapter(chapter100Url.AbsoluteUri, result.Chapter));
            Assert.IsFalse(store.AttachPreparedNextChapter(chapter100Url.AbsoluteUri, result.Chapter),
                "ready 章节只能 attach 一次");
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
    public async Task QidiyTailProbePreparesNextChapterWithoutRefreshingCatalog()
    {
        var catalogUrl = new Uri("https://www.qidiy.com/book/42/");
        var chapter100Url = new Uri("https://www.qidiy.com/book/42/100.html");
        var chapter101Url = new Uri("https://www.qidiy.com/book/42/101.html");
        var loader = new TailProbeLoader(catalogUrl, chapter100Url, chapter101Url, qidiy: true);
        var (store, databasePath) = await CreateStoreAsync(loader, catalogUrl, chapter100Url);

        try
        {
            var result = await store.PrepareNextChapterAsync();

            Assert.AreEqual(NextChapterPreparationStatus.Ready, result.Status);
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
    public void ShortChapterTailRearmsOncePerTailWithBoundedAutomaticChain()
    {
        var state = new ReaderContinuousLoadState();
        var now = DateTimeOffset.Parse("2026-08-12T00:00:00Z");
        const string chapter100 = "https://example.com/book/100.html";
        const string chapter101 = "https://example.com/book/101.html";
        const string chapter102 = "https://example.com/book/102.html";
        const string chapter103 = "https://example.com/book/103.html";

        state.ObserveNearEnd(chapter100, isNearEnd: true);
        Assert.IsTrue(state.TryBegin(chapter100, now));
        state.MarkAttached();

        state.ObserveNearEnd(chapter101, isNearEnd: true);
        Assert.IsTrue(state.TryBegin(chapter101, now.AddSeconds(1)));
        Assert.IsFalse(state.TryBegin(chapter101, now.AddSeconds(1)), "同一个 tail 不能重复请求");
        state.MarkAttached();

        state.ObserveNearEnd(chapter102, isNearEnd: true);
        Assert.IsTrue(state.TryBegin(chapter102, now.AddSeconds(2)), "短 B 后应能继续准备 C");
        state.MarkAttached();

        state.ObserveNearEnd(chapter103, isNearEnd: true);
        Assert.IsFalse(state.TryBegin(chapter103, now.AddSeconds(3)), "一次 near-end visit 最多自动补三章");

        state.ObserveNearEnd(chapter103, isNearEnd: false);
        state.ObserveNearEnd(chapter103, isNearEnd: true);
        Assert.IsTrue(state.TryBegin(chapter103, now.AddSeconds(4)));
    }

    [TestMethod]
    public void ReadyAttachmentWaitsForIdleAndCannotApplyTwiceOrAfterReset()
    {
        var state = new ReaderContinuousAttachmentState();
        var chapter = new Chapter(
            "https://example.com/101.html", "第101章", 101, "正文", cachedAt: DateTimeOffset.UtcNow);

        var firstViewChange = state.ObserveViewChanged();
        Assert.IsTrue(state.Queue(chapter, "https://example.com/100.html", state.Generation));
        Assert.IsFalse(state.Queue(chapter, "https://example.com/100.html", state.Generation));
        Assert.IsFalse(state.TryTake(out _, out _), "滚动期间不能 attach");

        var secondViewChange = state.ObserveViewChanged();
        Assert.IsFalse(state.MarkIdle(firstViewChange), "较早的 final event 不能提前结束 debounce");
        Assert.IsFalse(state.TryTake(out _, out _));
        Assert.IsTrue(state.MarkIdle(secondViewChange));
        Assert.IsTrue(state.TryTake(out var ready, out var tail));
        Assert.AreSame(chapter, ready);
        Assert.AreEqual("https://example.com/100.html", tail);
        Assert.IsFalse(state.TryTake(out _, out _), "idle 事件不能重复 attach");

        var oldGeneration = state.Generation;
        Assert.IsTrue(state.Queue(chapter, tail!, oldGeneration));
        state.Reset();
        Assert.IsFalse(state.TryTake(out _, out _), "navigation 后旧 pending 必须失效");
        Assert.IsFalse(state.Queue(chapter, tail!, oldGeneration));
        Assert.AreEqual(TimeSpan.FromMilliseconds(250), ReaderContinuousAttachmentState.IdleDebounce);
    }

    [TestMethod]
    public async Task PrefetchAndContinuousPrepareShareOneChapterLoad()
    {
        var urls = ChapterUrls(2);
        var loader = new PrefetchLoader(urls, blockedUrl: urls[1]);
        var (store, databasePath) = await CreateCatalogStoreAsync(loader, urls);

        try
        {
            await loader.BlockedRequestStarted.Task.WaitAsync(TimeSpan.FromSeconds(5));
            var preparationTask = store.PrepareNextChapterAsync();
            loader.ReleaseBlockedRequest();

            var preparation = await preparationTask;
            await store.PrefetchCompletion;

            Assert.AreEqual(NextChapterPreparationStatus.Ready, preparation.Status);
            Assert.AreEqual(1, loader.RequestCount(urls[1]));
        }
        finally
        {
            await store.DisposeAsync();
            DeleteDatabase(databasePath);
        }
    }

    [TestMethod]
    public async Task IdlePrefetchVisitsAtMostThreeSuccessorsAndSkipsDiskCache()
    {
        var urls = ChapterUrls(5);
        var loader = new PrefetchLoader(urls);
        var (store, databasePath) = await CreateCatalogStoreAsync(loader, urls, diskCachedIndexes: [1]);

        try
        {
            await store.PrefetchCompletion;

            Assert.AreEqual(0, loader.RequestCount(urls[1]), "磁盘已有正文不得重复下载");
            Assert.AreEqual(1, loader.RequestCount(urls[2]));
            Assert.AreEqual(1, loader.RequestCount(urls[3]));
            Assert.AreEqual(0, loader.RequestCount(urls[4]), "一次空闲预取最多检查后续三章");
        }
        finally
        {
            await store.DisposeAsync();
            DeleteDatabase(databasePath);
        }
    }

    [TestMethod]
    public async Task IdlePrefetchStopsAtBookEnd()
    {
        var urls = ChapterUrls(2);
        var loader = new PrefetchLoader(urls);
        var (store, databasePath) = await CreateCatalogStoreAsync(loader, urls);

        try
        {
            await store.PrefetchCompletion;
            Assert.AreEqual(1, loader.TotalRequests);
            Assert.AreEqual(1, loader.RequestCount(urls[1]));
        }
        finally
        {
            await store.DisposeAsync();
            DeleteDatabase(databasePath);
        }
    }

    [TestMethod]
    public async Task ChangingBookCancelsOldPrefetch()
    {
        var urls = ChapterUrls(3);
        var loader = new PrefetchLoader(urls, blockedUrl: urls[1]);
        var (store, databasePath) = await CreateCatalogStoreAsync(loader, urls);

        try
        {
            await loader.BlockedRequestStarted.Task.WaitAsync(TimeSpan.FromSeconds(5));
            var oldPrefetch = store.PrefetchCompletion;
            store.SelectBook(null);
            await oldPrefetch.WaitAsync(TimeSpan.FromSeconds(5));
            await loader.BlockedRequestCancelled.Task.WaitAsync(TimeSpan.FromSeconds(5));
            Assert.AreEqual(0, loader.RequestCount(urls[2]));
        }
        finally
        {
            await store.DisposeAsync();
            DeleteDatabase(databasePath);
        }
    }

    [TestMethod]
    public async Task ChangingChapterCancelsOldPrefetchChain()
    {
        var urls = ChapterUrls(4);
        var loader = new PrefetchLoader(urls, blockedUrl: urls[1]);
        var (store, databasePath) = await CreateCatalogStoreAsync(loader, urls, diskCachedIndexes: [2]);

        try
        {
            await loader.BlockedRequestStarted.Task.WaitAsync(TimeSpan.FromSeconds(5));
            var oldPrefetch = store.PrefetchCompletion;
            var target = store.SelectedBook!.Chapters.Single(chapter => chapter.SourceUrl == urls[2].AbsoluteUri);

            Assert.IsTrue(await store.SelectChapterAsync(target));
            await oldPrefetch.WaitAsync(TimeSpan.FromSeconds(5));
            await loader.BlockedRequestCancelled.Task.WaitAsync(TimeSpan.FromSeconds(5));
        }
        finally
        {
            await store.DisposeAsync();
            DeleteDatabase(databasePath);
        }
    }

    [TestMethod]
    public void HiddenCatalogIsMarkedDirtyInsteadOfReboundAfterAppend()
    {
        var source = File.ReadAllText(Path.Combine(
            AppContext.BaseDirectory,
            "..", "..", "..", "..", "..", "windows", "YYReader.Windows", "Views", "ReaderPage.xaml.cs"));
        var attachStart = source.IndexOf("private void TryAttachPendingContinuousChapter", StringComparison.Ordinal);
        var attachEnd = source.IndexOf("private async void ContinuationRetry_Click", attachStart, StringComparison.Ordinal);
        var attachMethod = source[attachStart..attachEnd];

        StringAssert.Contains(attachMethod, "RefreshCatalogListIfVisible()");
        Assert.IsFalse(attachMethod.Contains("RefreshCatalogList();", StringComparison.Ordinal));
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
    public void AppendingNextChapterRestoresLogicalAnchorWithoutVerticalOffset()
    {
        var source = File.ReadAllText(Path.Combine(
            AppContext.BaseDirectory,
            "..", "..", "..", "..", "..", "windows", "YYReader.Windows", "Views", "ReaderPage.xaml.cs"));
        var methodStart = source.IndexOf("private async Task LoadNextContinuousChapterAsync", StringComparison.Ordinal);
        var methodEnd = source.IndexOf("private async void ContinuationRetry_Click", methodStart, StringComparison.Ordinal);
        var method = source[methodStart..methodEnd];

        var capture = method.IndexOf("var anchor = CaptureReaderAnchor()", StringComparison.Ordinal);
        var append = method.IndexOf("Items.AddRange", StringComparison.Ordinal);
        var restore = method.IndexOf("RestoreReaderAnchor(anchor)", StringComparison.Ordinal);
        Assert.IsTrue(capture >= 0 && append > capture && restore > append);
        StringAssert.Contains(method, "_restoringContinuousAnchor");
        Assert.IsFalse(method.Contains("VerticalOffset", StringComparison.Ordinal));
        Assert.IsFalse(method.Contains("stableOffset", StringComparison.Ordinal));
    }

    private static Uri[] ChapterUrls(int count) => Enumerable.Range(1, count)
        .Select(index => new Uri($"https://example.com/book/{index}.html"))
        .ToArray();

    private static async Task<(LibraryStore Store, string DatabasePath)> CreateCatalogStoreAsync(
        IHtmlDocumentLoader loader,
        IReadOnlyList<Uri> chapterUrls,
        IReadOnlyCollection<int>? diskCachedIndexes = null)
    {
        var databasePath = Path.Combine(Path.GetTempPath(), $"yyreader-prefetch-{Guid.NewGuid():N}.db");
        var repository = new SqliteLibraryRepository(databasePath);
        await repository.InitializeAsync();
        var catalogUrl = new Uri("https://example.com/book/");
        var seeds = chapterUrls.Select((url, index) => new ChapterSeed($"第{index + 1}章", url, index)).ToArray();
        var book = await repository.UpsertImportAsync(new NovelImportResult(
            "预取测试小说",
            "测试作者",
            catalogUrl,
            catalogUrl,
            true,
            seeds,
            true,
            "第1章",
            chapterUrls[0],
            "第一章已经缓存在本地，用于启动阅读会话。",
            null,
            chapterUrls.Count > 1 ? chapterUrls[1] : null));

        foreach (var index in diskCachedIndexes ?? [])
        {
            await repository.SaveChapterAsync(book.Id, new ChapterLoadResult(
                $"第{index + 1}章",
                "预取测试小说",
                "测试作者",
                catalogUrl,
                chapterUrls[index],
                $"第{index + 1}章磁盘缓存正文。",
                index > 0 ? chapterUrls[index - 1] : null,
                index + 1 < chapterUrls.Count ? chapterUrls[index + 1] : null), index);
        }

        var store = new LibraryStore(
            repository,
            new NovelImportCoordinator(loader),
            prefetchIdleDelay: TimeSpan.Zero);
        await store.InitializeAsync();
        store.SelectBook(store.Books.Single());
        Assert.IsTrue(await store.EnsureSelectedChapterLoadedAsync());
        return (store, databasePath);
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

    private sealed class PrefetchLoader(IReadOnlyList<Uri> chapterUrls, Uri? blockedUrl = null) : IHtmlDocumentLoader
    {
        private readonly object _sync = new();
        private readonly Dictionary<string, int> _requests = new(StringComparer.Ordinal);
        private readonly TaskCompletionSource _release = new(TaskCreationOptions.RunContinuationsAsynchronously);

        public TaskCompletionSource BlockedRequestStarted { get; } =
            new(TaskCreationOptions.RunContinuationsAsynchronously);
        public TaskCompletionSource BlockedRequestCancelled { get; } =
            new(TaskCreationOptions.RunContinuationsAsynchronously);

        public int TotalRequests
        {
            get
            {
                lock (_sync) return _requests.Values.Sum();
            }
        }

        public void BeginOperation()
        {
        }

        public int RequestCount(Uri url)
        {
            lock (_sync) return _requests.GetValueOrDefault(url.AbsoluteUri);
        }

        public void ReleaseBlockedRequest() => _release.TrySetResult();

        public async Task<LoadedHtml> LoadAsync(Uri url, CancellationToken cancellationToken = default)
        {
            lock (_sync)
            {
                _requests[url.AbsoluteUri] = _requests.GetValueOrDefault(url.AbsoluteUri) + 1;
            }

            if (url == blockedUrl)
            {
                BlockedRequestStarted.TrySetResult();
                try
                {
                    await _release.Task.WaitAsync(cancellationToken);
                }
                catch (OperationCanceledException)
                {
                    BlockedRequestCancelled.TrySetResult();
                    throw;
                }
            }

            var index = chapterUrls.ToList().FindIndex(candidate => candidate == url);
            if (index < 0)
            {
                throw new HtmlLoadException(HtmlLoadErrorKind.HttpStatus, statusCode: 404);
            }

            var previous = index > 0
                ? $"<a rel='prev' href='{chapterUrls[index - 1].AbsoluteUri}'>上一章</a>"
                : "";
            var next = index + 1 < chapterUrls.Count
                ? $"<a rel='next' href='{chapterUrls[index + 1].AbsoluteUri}'>下一章</a>"
                : "";
            var html = $$"""
                <html><head><title>第{{index + 1}}章</title></head><body>
                  <h1>第{{index + 1}}章</h1>
                  <article>
                    <p>这是串行预取测试使用的自造章节正文，长度足够让通用解析器稳定识别正文内容。</p>
                    <p>第二段用于确认每个章节只会发出一次网络请求，并且不会越过书籍目录末尾。</p>
                  </article>
                  {{previous}}{{next}}
                </body></html>
                """;
            return new LoadedHtml(url, url, html, HtmlRetrievalKind.UrlSession);
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
