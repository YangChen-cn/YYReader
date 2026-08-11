using Microsoft.VisualStudio.TestTools.UnitTesting;
using YYReader.Windows.Core.Parsing;
using YYReader.Windows.Core.Persistence;
using YYReader.Windows.Core.Services;
using YYReader.Windows.Core.Models;

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

    private static void DeleteDatabase(string path)
    {
        if (File.Exists(path)) File.Delete(path);
        if (File.Exists($"{path}-wal")) File.Delete($"{path}-wal");
        if (File.Exists($"{path}-shm")) File.Delete($"{path}-shm");
    }
}
