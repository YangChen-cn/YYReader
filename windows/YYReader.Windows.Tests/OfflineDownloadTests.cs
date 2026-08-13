using Microsoft.VisualStudio.TestTools.UnitTesting;
using YYReader.Windows.Core.Parsing;
using YYReader.Windows.Core.Persistence;
using YYReader.Windows.Core.Services;
using YYReader.Windows.Core.Models;
using YYReader.Windows.Services;

namespace YYReader.Windows.Tests;

[TestClass]
public sealed class OfflineDownloadTests
{
    [TestMethod]
    public async Task CancellationKeepsEveryChapterCompletedBeforeCancellation()
    {
        var path = Path.Combine(Path.GetTempPath(), $"yyreader-download-test-{Guid.NewGuid():N}.db");
        try
        {
            var (repository, book) = await CreateBookAsync(path);
            OfflineDownloadManager? manager = null;
            manager = new OfflineDownloadManager(repository, async (url, cancellationToken) =>
            {
                if (url.AbsolutePath.EndsWith("3.html", StringComparison.Ordinal))
                {
                    await Task.Delay(Timeout.InfiniteTimeSpan, cancellationToken);
                }
                return ChapterResult(url, $"{url.Segments[^1]} 正文");
            });
            manager.StateChanged += (_, state) =>
            {
                if (state.CurrentChapter == "第3章") manager.Cancel();
            };

            var result = await manager.DownloadAsync(book, book.Chapters[0], OfflineDownloadScope.AllChapters);
            var reloaded = (await repository.GetBooksAsync()).Single();

            Assert.IsTrue(result.WasCancelled);
            Assert.IsTrue(reloaded.Chapters[1].IsAvailableOffline);
            Assert.AreEqual("2.html 正文", await repository.LoadChapterBodyAsync(book.Id, reloaded.Chapters[1].SourceUrl));
            Assert.IsFalse(reloaded.Chapters[2].IsAvailableOffline);
            Assert.IsFalse(book.Chapters[1].IsAvailableOffline, "下载器不应从后台线程直接修改 UI model");
        }
        finally
        {
            DeleteDatabase(path);
        }
    }

    [TestMethod]
    public async Task ClearingOfflineCacheKeepsBookChapterMetadataAndProgress()
    {
        var path = Path.Combine(Path.GetTempPath(), $"yyreader-clear-cache-test-{Guid.NewGuid():N}.db");
        try
        {
            var (repository, book) = await CreateBookAsync(path);
            await repository.SaveProgressAsync(book.Id, book.Chapters[0].SourceUrl, 2, 0.5, DateTimeOffset.UtcNow);
            var manager = new OfflineDownloadManager(repository, (url, _) => Task.FromResult(ChapterResult(url, "正文")));

            await manager.ClearOfflineCacheAsync(book);
            var reloaded = (await repository.GetBooksAsync()).Single();

            Assert.AreEqual(3, reloaded.Chapters.Count);
            Assert.AreEqual(2, reloaded.Chapters[0].ParagraphIndex);
            Assert.AreEqual(0.5, reloaded.Chapters[0].Progress, 0.0001);
            Assert.IsFalse(reloaded.Chapters.Any(chapter => chapter.IsAvailableOffline));
            Assert.IsNull(await repository.LoadChapterBodyAsync(book.Id, book.Chapters[0].SourceUrl));
            Assert.IsTrue(book.Chapters[0].IsAvailableOffline, "清理器不应从后台线程直接修改 UI model");
        }
        finally
        {
            DeleteDatabase(path);
        }
    }

    [TestMethod]
    public async Task EntireBookDownloadRefreshesCompleteCatalogBeforePlanning()
    {
        var path = Path.Combine(Path.GetTempPath(), $"yyreader-download-catalog-{Guid.NewGuid():N}.db");
        try
        {
            var repository = new SqliteLibraryRepository(path);
            await repository.InitializeAsync();
            var landing = new Uri("https://example.com/book/full/");
            var complete = new Uri("https://example.com/book/full/list/");
            var first = new Uri("https://example.com/book/full/1.html");
            var second = new Uri("https://example.com/book/full/2.html");
            var third = new Uri("https://example.com/book/full/3.html");
            await repository.UpsertImportAsync(new NovelImportResult(
                "全本下载测试", "作者", landing, landing, true,
                [new ChapterSeed("第3章 最新预览", third, 1)],
                false, "第3章 最新预览", third, "已缓存的第三章正文", second, null));
            var loader = new DownloadCatalogLoader(new Dictionary<Uri, string>
            {
                [landing] = """
                    <h1>全本下载测试</h1><meta name="author" content="作者">
                    <div class="chapter-list"><a href="3.html"><h4>第3章 最新预览</h4><small>免费</small></a></div>
                    <a href="list/">全部章节</a>
                    """,
                [complete] = """
                    <h1>全本下载测试</h1><meta name="author" content="作者"><div class="chapter-list">
                      <a href="../1.html"><h4>第1章 开始</h4><small>免费</small></a>
                      <a href="../2.html"><h4>第2章 继续</h4><small>免费</small></a>
                      <a href="../3.html"><h4>第3章 最新预览</h4><small>免费</small></a>
                    </div>
                    """,
                [first] = GenericChapter("第1章 开始", "第一章的自造离线正文内容足够长，用于验证完整目录刷新后能够按新目录下载。"),
                [second] = GenericChapter("第2章 继续", "第二章的自造离线正文内容同样足够长，用于验证下载计划包含新增章节。")
            });
            var coordinator = new NovelImportCoordinator(loader);
            var store = new LibraryStore(repository, coordinator);
            await store.InitializeAsync();
            var book = store.Books.Single();
            store.SelectBook(book);

            Assert.IsTrue(await store.PrepareOfflineDownloadAsync(book, OfflineDownloadScope.AllChapters));
            var manager = new OfflineDownloadManager(repository, coordinator);
            var result = await manager.DownloadAsync(book, book.CurrentChapter!, OfflineDownloadScope.AllChapters);

            CollectionAssert.AreEqual(
                new[] { landing, complete, first, second },
                loader.RequestedUris.ToArray());
            CollectionAssert.AreEqual(
                new[] { "第1章 开始", "第2章 继续", "第3章 最新预览" },
                book.Chapters.OrderBy(chapter => chapter.SortIndex).Select(chapter => chapter.Title).ToArray());
            Assert.AreEqual(3, result.Total);
            Assert.AreEqual(3, result.Completed);
            Assert.AreEqual(0, result.Failed);
        }
        finally
        {
            DeleteDatabase(path);
        }
    }

    [TestMethod]
    public async Task LoadingPlaceholderChapterPromotesDiscoveredCatalogForRefresh()
    {
        var path = Path.Combine(Path.GetTempPath(), $"yyreader-catalog-promotion-{Guid.NewGuid():N}.db");
        try
        {
            var repository = new SqliteLibraryRepository(path);
            await repository.InitializeAsync();
            var chapterUrl = new Uri("https://www.yeduji.com/book/155532/4294446.html");
            var catalogUrl = new Uri("https://www.yeduji.com/book/155532/");
            await repository.UpsertImportAsync(new NovelImportResult(
                "临时书名", "未知作者", catalogUrl, chapterUrl, false,
                [new ChapterSeed("当前章节", chapterUrl, 1)],
                false, "当前章节", chapterUrl, "临时正文", null, null));
            await repository.ClearChapterBodiesAsync((await repository.GetBooksAsync()).Single().Id);

            var loader = new DownloadCatalogLoader(new Dictionary<Uri, string>
            {
                [chapterUrl] = """
                    <title>娱乐春秋（加料福利版） - 序言 - 夜读集 小说 在线阅读</title>
                    <meta name="description" content="《娱乐春秋（加料福利版）》是由作者 姬叉 创作的网络小说。">
                    <h1 class="title">序言</h1>
                    <div class="content">
                      <p>第一段自造正文具有足够长度，用于验证旧书籍记录可以恢复目录能力。</p>
                      <p>第二段自造正文继续补充内容，章节加载完成后应允许用户刷新完整目录。</p>
                    </div>
                    <a href="/book/155532/">返回目录</a>
                    <a href="/book/155532/4294433.html">下一章</a>
                    """
            });
            var store = new LibraryStore(repository, new NovelImportCoordinator(loader));
            await store.InitializeAsync();
            var book = store.Books.Single();
            store.SelectBook(book);

            Assert.IsTrue(await store.EnsureSelectedChapterLoadedAsync());
            Assert.IsTrue(book.HasCatalog);
            Assert.AreEqual(catalogUrl.AbsoluteUri, book.CatalogUrl);
            Assert.AreEqual("娱乐春秋（加料福利版）", book.Title);
            Assert.AreEqual("姬叉", book.Author);

            var persisted = (await repository.GetBooksAsync()).Single();
            Assert.IsTrue(persisted.HasCatalog);
            Assert.AreEqual(catalogUrl.AbsoluteUri, persisted.CatalogUrl);
            Assert.AreEqual("娱乐春秋（加料福利版）", persisted.Title);
            Assert.AreEqual("姬叉", persisted.Author);
        }
        finally
        {
            DeleteDatabase(path);
        }
    }

    private static async Task<(SqliteLibraryRepository Repository, Book Book)> CreateBookAsync(string path)
    {
        var repository = new SqliteLibraryRepository(path);
        await repository.InitializeAsync();
        var urls = Enumerable.Range(1, 3).Select(index => new Uri($"https://example.com/book/{index}.html")).ToArray();
        var book = await repository.UpsertImportAsync(new NovelImportResult(
            "下载测试", "作者", new Uri("https://example.com/book/"), new Uri("https://example.com/book/"), true,
            urls.Select((url, index) => new ChapterSeed($"第{index + 1}章", url, index + 1)).ToArray(),
            true, "第1章", urls[0], "已缓存首章", null, urls[1]));
        return (repository, book);
    }

    private static ChapterLoadResult ChapterResult(Uri url, string body) =>
        new(url.Segments[^1], "下载测试", "作者", new Uri("https://example.com/book/"), url, body, null, null);

    private static string GenericChapter(string title, string body) => $$"""
        <title>{{title}}_全本下载测试</title><h1>{{title}}</h1>
        <article>{{body}}{{body}}</article>
        """;

    private sealed class DownloadCatalogLoader(IReadOnlyDictionary<Uri, string> documents) : IHtmlDocumentLoader
    {
        public List<Uri> RequestedUris { get; } = new();

        public void BeginOperation()
        {
        }

        public Task<LoadedHtml> LoadAsync(Uri url, CancellationToken cancellationToken = default)
        {
            cancellationToken.ThrowIfCancellationRequested();
            RequestedUris.Add(url);
            return documents.TryGetValue(url, out var html)
                ? Task.FromResult(new LoadedHtml(url, url, html, HtmlRetrievalKind.UrlSession))
                : Task.FromException<LoadedHtml>(new HtmlLoadException(HtmlLoadErrorKind.HttpStatus, statusCode: 404));
        }
    }

    private static void DeleteDatabase(string path)
    {
        if (File.Exists(path)) File.Delete(path);
        if (File.Exists($"{path}-wal")) File.Delete($"{path}-wal");
        if (File.Exists($"{path}-shm")) File.Delete($"{path}-shm");
    }
}
