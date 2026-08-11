using Microsoft.VisualStudio.TestTools.UnitTesting;
using YYReader.Windows.Core.Models;
using YYReader.Windows.Core.Parsing;
using YYReader.Windows.Core.Services;

namespace YYReader.Windows.Tests;

[TestClass]
public sealed class ParserTests
{
    [TestMethod]
    public void ParsesGenericSemanticChapterAndRelativeNavigation()
    {
        var url = new Uri("https://example.com/book/3.html");
        var page = new GenericNovelAdapter().ParseChapterPage(new LoadedHtml(
            url,
            url,
            ReadFixture("generic_chapter"),
            HtmlRetrievalKind.UrlSession));

        Assert.AreEqual("第三章 雨夜", page.Title);
        Assert.AreEqual("某作者", page.Author);
        Assert.AreEqual(3, page.Paragraphs.Count);
        Assert.AreEqual("https://example.com/book/2.html", page.PreviousChapterUrl!.AbsoluteUri);
        Assert.AreEqual("https://example.com/book/4.html", page.NextChapterUrl!.AbsoluteUri);
    }

    [TestMethod]
    public void ParsesQidiyChapterAndRemovesPaginationNoise()
    {
        var url = new Uri("https://www.qidiy.com/book/100/1.html");
        var page = new QidiySourceAdapter().ParseChapterPage(new LoadedHtml(
            url,
            url,
            ReadFixture("qidiy_chapter_1"),
            HtmlRetrievalKind.UrlSession));

        CollectionAssert.AreEqual(new[] { "第一段测试文字。", "第二段测试文字。" }, page.Paragraphs.ToArray());
        Assert.AreEqual("https://www.qidiy.com/book/100/1/2.html", page.NextPageUrl!.AbsoluteUri);
        Assert.AreEqual("https://www.qidiy.com/book/100/", page.CatalogUrl!.AbsoluteUri);
    }

    [TestMethod]
    public void CatalogOrderRemainsDomOrderWhenDisplayedNumbersRestart()
    {
        var url = new Uri("https://example.com/book/");
        var page = new GenericNovelAdapter().ParseCatalogPage(new LoadedHtml(
            url,
            url,
            """
            <h1>顺序测试</h1>
            <nav class="chapters">
              <a href="main-1.html">第1章 正文一</a>
              <a href="main-2.html">第2章 正文二</a>
              <a href="extra-1.html">第1章 番外一</a>
              <a href="extra-2.html">第2章 番外二</a>
            </nav>
            """,
            HtmlRetrievalKind.UrlSession));

        CollectionAssert.AreEqual(
            new[] { "第1章 正文一", "第2章 正文二", "第1章 番外一", "第2章 番外二" },
            page.Chapters.Select(chapter => chapter.Title).ToArray());
        CollectionAssert.AreEqual(new[] { 1, 2, 3, 4 }, page.Chapters.Select(chapter => chapter.SortIndex).ToArray());
    }

    [TestMethod]
    public async Task CoordinatorMergesTwoPageChapterAndPreservesPreviousNext()
    {
        var chapter1 = new Uri("https://www.qidiy.com/book/100/1.html");
        var chapter2 = new Uri("https://www.qidiy.com/book/100/1/2.html");
        var catalog = new Uri("https://www.qidiy.com/book/100/");
        var loader = new DictionaryHtmlLoader(new Dictionary<Uri, string>
        {
            [chapter1] = ReadFixture("qidiy_chapter_1"),
            [chapter2] = ReadFixture("qidiy_chapter_2"),
            [catalog] = ReadFixture("qidiy_catalog_1")
        });
        var coordinator = new NovelImportCoordinator(loader);

        var result = await coordinator.ImportNovelAsync(chapter1);

        Assert.AreEqual("测试小说", result.BookTitle);
        Assert.AreEqual("测试作者", result.Author);
        Assert.AreEqual("第一段测试文字。\n\n第二段测试文字。\n\n第三段测试文字。\n\n第四段测试文字。", result.BodyText);
        Assert.AreEqual("https://www.qidiy.com/book/100/2.html", result.NextChapterUrl!.AbsoluteUri);
        CollectionAssert.AreEqual(new[] { 1, 2 }, result.Catalog.Select(chapter => chapter.SortIndex).ToArray());
    }

    [TestMethod]
    public void ChallengeDetectorDoesNotTreatNormalHtmlAsChallenge()
    {
        Assert.IsTrue(HtmlChallengeDetector.IsChallenge("<title>Just a moment...</title><div class='cf-chl-test'></div>"));
        Assert.IsFalse(HtmlChallengeDetector.IsChallenge("<article>普通正文</article>"));
    }

    [TestMethod]
    public async Task CatalogRefreshRetriesOneTransientPageFailure()
    {
        var first = new Uri("https://example.com/book/");
        var second = new Uri("https://example.com/book/page-2/");
        var loader = new TransientCatalogLoader(first, second, failSecondPageOnce: true);
        var coordinator = new NovelImportCoordinator(loader);

        var catalog = await coordinator.RefreshCatalogAsync(first);

        Assert.AreEqual(2, catalog.Chapters.Count);
        Assert.AreEqual(2, loader.SecondPageAttempts);
    }

    [TestMethod]
    public async Task CatalogRefreshFailureIncludesPageNumberAndFriendlyCause()
    {
        var first = new Uri("https://example.com/book/");
        var second = new Uri("https://example.com/book/page-2/");
        var loader = new TransientCatalogLoader(first, second, failSecondPageOnce: false);
        var coordinator = new NovelImportCoordinator(loader);

        var error = await Assert.ThrowsExceptionAsync<HtmlLoadException>(
            () => coordinator.RefreshCatalogAsync(first));

        StringAssert.Contains(error.Message, "目录第 2 页加载失败");
        StringAssert.Contains(error.Message, "浏览器未能完成网页加载");
        Assert.AreEqual(2, loader.SecondPageAttempts);
    }

    private static string ReadFixture(string name) =>
        File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "Fixtures", $"{name}.html"));

    private sealed class DictionaryHtmlLoader(IReadOnlyDictionary<Uri, string> documents) : IHtmlDocumentLoader
    {
        public List<Uri> RequestedUris { get; } = new();

        public void BeginOperation()
        {
        }

        public Task<LoadedHtml> LoadAsync(Uri url, CancellationToken cancellationToken = default)
        {
            cancellationToken.ThrowIfCancellationRequested();
            RequestedUris.Add(url);
            if (!documents.TryGetValue(url, out var html))
            {
                throw new HtmlLoadException(HtmlLoadErrorKind.HttpStatus, statusCode: 404);
            }
            return Task.FromResult(new LoadedHtml(url, url, html, HtmlRetrievalKind.UrlSession));
        }
    }

    private sealed class TransientCatalogLoader(Uri first, Uri second, bool failSecondPageOnce) : IHtmlDocumentLoader
    {
        public int SecondPageAttempts { get; private set; }

        public void BeginOperation()
        {
        }

        public Task<LoadedHtml> LoadAsync(Uri url, CancellationToken cancellationToken = default)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (url == first)
            {
                return Task.FromResult(new LoadedHtml(url, url, CatalogPage(
                    "<a href='/book/1.html'>第1章</a>",
                    "<a href='/book/page-2/'>下一页</a>"), HtmlRetrievalKind.UrlSession));
            }

            SecondPageAttempts++;
            if (url != second || !failSecondPageOnce || SecondPageAttempts == 1)
            {
                throw new HtmlLoadException(
                    HtmlLoadErrorKind.InvalidResponse,
                    "浏览器未能完成网页加载，可能是网站临时限制，请稍后重试。");
            }

            return Task.FromResult(new LoadedHtml(url, url, CatalogPage(
                "<a href='/book/2.html'>第2章</a>",
                ""), HtmlRetrievalKind.UrlSession));
        }

        private static string CatalogPage(string chapters, string navigation) => $$"""
            <html><body>
              <h1>分页测试</h1>
              <ul class="section-list">{{chapters}}</ul>
              {{navigation}}
            </body></html>
            """;
    }
}
