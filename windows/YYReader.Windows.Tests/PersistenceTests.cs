using Microsoft.VisualStudio.TestTools.UnitTesting;
using YYReader.Windows.Core.Persistence;
using YYReader.Windows.Core.Parsing;

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
}
