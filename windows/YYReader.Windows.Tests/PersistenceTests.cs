using Microsoft.VisualStudio.TestTools.UnitTesting;
using YYReader.Windows.Core.Persistence;
using YYReader.Windows.Core.Parsing;
using YYReader.Windows.Core.Sync;

namespace YYReader.Windows.Tests;

[TestClass]
public sealed class PersistenceTests
{
    [TestMethod]
    public async Task SqliteStoresBookChapterAndProgressAndCascadesDelete()
    {
        var path = Path.Combine(Path.GetTempPath(), $"yyreader-test-{Guid.NewGuid():N}.db");
        try
        {
            var repository = new SqliteLibraryRepository(path);
            await repository.InitializeAsync();
            var chapterUrl = new Uri("https://example.com/book/1.html");
            var result = new NovelImportResult(
                "测试小说",
                "测试作者",
                new Uri("https://example.com/book/"),
                new Uri("https://example.com/book/"),
                true,
                [new ChapterSeed("第1章", chapterUrl, 1)],
                true,
                "第1章",
                chapterUrl,
                "第一段\n第二段\n第三段",
                null,
                null);

            var book = await repository.UpsertImportAsync(result);
            await repository.SaveProgressAsync(book.Id, chapterUrl.AbsoluteUri, 1, 0.5, DateTimeOffset.UtcNow);
            var loaded = (await repository.GetBooksAsync()).Single();

            Assert.AreEqual("测试小说", loaded.Title);
            Assert.AreEqual(1, loaded.Chapters.Count);
            Assert.AreEqual(1, loaded.Chapters[0].ParagraphIndex);
            Assert.AreEqual(0.5, loaded.Chapters[0].Progress, 0.0001);
            Assert.IsTrue(loaded.Chapters[0].IsAvailableOffline);
            Assert.IsFalse(loaded.Chapters[0].IsCached, "书架查询不应把正文加载进 RAM");

            var storedBody = await repository.LoadChapterBodyAsync(book.Id, chapterUrl.AbsoluteUri);
            Assert.AreEqual("第一段\n\n第二段\n\n第三段", storedBody);
            loaded.Chapters[0].ReplaceBodyText(storedBody, loaded.Chapters[0].CachedAt);
            CollectionAssert.AreEqual(new[] { "第一段", "第二段", "第三段" }, loaded.Chapters[0].Paragraphs.ToArray());

            await repository.DeleteBookAsync(book.Id);
            Assert.AreEqual(0, (await repository.GetBooksAsync()).Count);
        }
        finally
        {
            if (File.Exists(path)) File.Delete(path);
            if (File.Exists($"{path}-wal")) File.Delete($"{path}-wal");
            if (File.Exists($"{path}-shm")) File.Delete($"{path}-shm");
        }
    }

    [TestMethod]
    public async Task DynamicPreviousChapterKeepsExplicitSortIndexAfterReload()
    {
        await AssertDynamicChapterSortIndexAsync(99, "previous.html", "动态上一章");
    }

    [TestMethod]
    public async Task DynamicNextChapterKeepsExplicitSortIndexAfterReload()
    {
        await AssertDynamicChapterSortIndexAsync(101, "next.html", "动态下一章");
    }

    private static async Task AssertDynamicChapterSortIndexAsync(int sortIndex, string pathName, string title)
    {
        var path = Path.Combine(Path.GetTempPath(), $"yyreader-sort-test-{Guid.NewGuid():N}.db");
        try
        {
            var repository = new SqliteLibraryRepository(path);
            await repository.InitializeAsync();
            var currentUrl = new Uri("https://example.com/book/current.html");
            var book = await repository.UpsertImportAsync(new NovelImportResult(
                "测试小说",
                "测试作者",
                new Uri("https://example.com/book/"),
                new Uri("https://example.com/book/"),
                true,
                [new ChapterSeed("当前章", currentUrl, 100)],
                true,
                "当前章",
                currentUrl,
                "当前正文",
                null,
                null));
            var dynamicUrl = new Uri($"https://example.com/book/{pathName}");
            await repository.SaveChapterAsync(book.Id, new ChapterLoadResult(
                title,
                "测试小说",
                "测试作者",
                new Uri("https://example.com/book/"),
                dynamicUrl,
                "动态正文",
                null,
                null), sortIndex);

            var reloadedRepository = new SqliteLibraryRepository(path);
            var reloaded = (await reloadedRepository.GetBooksAsync()).Single();
            var chapter = reloaded.Chapters.Single(candidate => candidate.SourceUrl == dynamicUrl.AbsoluteUri);

            Assert.AreEqual(sortIndex, chapter.SortIndex);
            Assert.AreEqual(100, reloaded.Chapters.Single(candidate => candidate.SourceUrl == currentUrl.AbsoluteUri).SortIndex);
        }
        finally
        {
            if (File.Exists(path)) File.Delete(path);
            if (File.Exists($"{path}-wal")) File.Delete($"{path}-wal");
            if (File.Exists($"{path}-shm")) File.Delete($"{path}-shm");
        }
    }

    [TestMethod]
    public async Task CatalogRefreshPreservesBodyProgressAndCurrentChapterWhileAddingNewChapters()
    {
        var path = Path.Combine(Path.GetTempPath(), $"yyreader-catalog-test-{Guid.NewGuid():N}.db");
        try
        {
            var repository = new SqliteLibraryRepository(path);
            await repository.InitializeAsync();
            var firstUrl = new Uri("https://example.com/book/1.html");
            var secondUrl = new Uri("https://example.com/book/2.html");
            var book = await repository.UpsertImportAsync(new NovelImportResult(
                "旧书名", "旧作者", new Uri("https://example.com/book/"), new Uri("https://example.com/book/"), true,
                [new ChapterSeed("旧标题", firstUrl, 1)], true, "旧标题", firstUrl, "离线正文", null, secondUrl));
            await repository.SaveProgressAsync(book.Id, firstUrl.AbsoluteUri, 3, 0.6, DateTimeOffset.UtcNow);

            var refreshed = await repository.UpsertCatalogAsync(book.Id, new ParsedBookCatalog(
                "新书名", "新作者",
                [new ChapterSeed("更新标题", firstUrl, 1), new ChapterSeed("新增章节", secondUrl, 2)], null));

            Assert.AreEqual("新书名", refreshed.Title);
            Assert.AreEqual(firstUrl.AbsoluteUri, refreshed.CurrentChapterUrl);
            Assert.AreEqual(2, refreshed.Chapters.Count);
            Assert.AreEqual("更新标题", refreshed.Chapters[0].Title);
            Assert.AreEqual(3, refreshed.Chapters[0].ParagraphIndex);
            Assert.AreEqual(0.6, refreshed.Chapters[0].Progress, 0.0001);
            Assert.IsTrue(refreshed.Chapters[0].IsAvailableOffline);
            Assert.AreEqual("离线正文", await repository.LoadChapterBodyAsync(book.Id, firstUrl.AbsoluteUri));
        }
        finally
        {
            if (File.Exists(path)) File.Delete(path);
            if (File.Exists($"{path}-wal")) File.Delete($"{path}-wal");
            if (File.Exists($"{path}-shm")) File.Delete($"{path}-shm");
        }
    }

    [TestMethod]
    public async Task SyncDeletionCreatesTombstoneAndStaleRemoteCannotRestoreBook()
    {
        var path = Path.Combine(Path.GetTempPath(), $"yyreader-sync-delete-{Guid.NewGuid():N}.db");
        try
        {
            var repository = new SqliteLibraryRepository(path);
            await repository.InitializeAsync();
            var chapterUrl = new Uri("https://example.com/book/1.html");
            var book = await repository.UpsertImportAsync(new NovelImportResult(
                "测试", "作者", new Uri("https://example.com/book/"), new Uri("https://example.com/book/"), true,
                [new ChapterSeed("第一章", chapterUrl, 1)], true, "第一章", chapterUrl, "正文", null, null));
            var stale = await repository.BuildSyncSnapshotAsync("windows");

            await repository.DeleteBookAsync(book.Id);
            await repository.ApplySyncSnapshotAsync(stale);

            Assert.AreEqual(0, (await repository.GetBooksAsync()).Count);
            Assert.IsNotNull((await repository.BuildSyncSnapshotAsync("windows")).Books.Single().DeletedAt);
        }
        finally
        {
            if (File.Exists(path)) File.Delete(path);
        }
    }

    [TestMethod]
    public async Task SyncUpdatesProgressWithoutReplacingCachedBody()
    {
        var path = Path.Combine(Path.GetTempPath(), $"yyreader-sync-progress-{Guid.NewGuid():N}.db");
        try
        {
            var repository = new SqliteLibraryRepository(path);
            await repository.InitializeAsync();
            var chapterUrl = new Uri("https://example.com/book/1.html");
            var book = await repository.UpsertImportAsync(new NovelImportResult(
                "旧标题", "作者", new Uri("https://example.com/book/"), new Uri("https://example.com/book/"), true,
                [new ChapterSeed("第一章", chapterUrl, 1)], true, "第一章", chapterUrl, "离线正文", null, null));
            await repository.ApplySyncSnapshotAsync(new SyncSnapshot
            {
                Device = "mac",
                UpdatedAt = DateTimeOffset.UtcNow,
                Books = [new SyncSnapshotBook
                {
                    SourceUrl = book.SourceBookUrl, Title = "新标题", Author = "作者", CurrentChapterUrl = chapterUrl.AbsoluteUri,
                    ParagraphIndex = 8, Progress = 0.75, LastReadAt = DateTimeOffset.UtcNow.AddMinutes(1), UpdatedAt = DateTimeOffset.UtcNow
                }]
            });

            var reloaded = (await repository.GetBooksAsync()).Single();
            Assert.AreEqual("新标题", reloaded.Title);
            Assert.AreEqual(8, reloaded.CurrentChapter!.ParagraphIndex);
            Assert.AreEqual("离线正文", await repository.LoadChapterBodyAsync(book.Id, chapterUrl.AbsoluteUri));
        }
        finally
        {
            if (File.Exists(path)) File.Delete(path);
        }
    }
}
