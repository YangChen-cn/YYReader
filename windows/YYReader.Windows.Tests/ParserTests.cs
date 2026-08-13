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
    public void GenericParserExtractsOpenGraphBookAndStructuralNavigation()
    {
        var url = new Uri("https://reader.example/novel/pagea/story-author_2.html");
        var page = ParseGenericChapter(url, """
            <head>
              <title>⚡ 《示例小说》 第一幕 开始 - 小说站</title>
              <meta name="og:title" content="《示例小说》 第一幕 开始 - 小说站">
            </head>
            <div class="bread_crumbs"><a href="/novel/chapters/story-author">《示例小说》</a></div>
            <div class="prev_page"><a href="story-author_1.html">序幕</a></div>
            <div class="title"><h1>第一幕 开始</h1></div>
            <div class="content">
              <p>这是正文第一段，包含足够多的文字来确认它是小说内容，而不是页面菜单或者站点导航。</p>
              <p>这是正文第二段，同样只保留适合原生阅读器显示的干净文本内容。</p>
            </div>
            <div class="next_page_links"><a href="story-author_3.html">第二幕 后续</a></div>
            """);

        Assert.AreEqual("第一幕 开始", page.Title);
        Assert.AreEqual("示例小说", page.BookTitle);
        Assert.AreEqual("https://reader.example/novel/chapters/story-author", page.CatalogUrl!.AbsoluteUri);
        Assert.AreEqual("https://reader.example/novel/pagea/story-author_1.html", page.PreviousChapterUrl!.AbsoluteUri);
        Assert.AreEqual("https://reader.example/novel/pagea/story-author_3.html", page.NextChapterUrl!.AbsoluteUri);
    }

    [TestMethod]
    public void GenericParserParsesYedujiChapterAndDiscoversCatalog()
    {
        var url = new Uri("https://www.yeduji.com/book/155532/4294446.html");
        var page = ParseGenericChapter(url, """
            <head>
              <title>娱乐春秋（加料福利版） - 序言 - 夜读集 小说 在线阅读</title>
              <meta name="description" content="《娱乐春秋（加料福利版）》是由作者 姬叉 创作的网络小说。">
            </head>
            <main>
              <h1 class="title">序言</h1>
              <div class="content">
                <p>第一段自造正文具有足够长度，用于验证夜读集章节页面可以被通用解析器稳定识别。</p>
                <p>第二段自造正文继续补充内容，并确保目录链接不会被错误地混入原生阅读正文。</p>
              </div>
              <a href="/book/155532/">返回目录</a>
              <a href="/book/155532/4294433.html">下一章</a>
            </main>
            """);

        Assert.AreEqual("序言", page.Title);
        Assert.AreEqual("娱乐春秋（加料福利版）", page.BookTitle);
        Assert.AreEqual("姬叉", page.Author);
        Assert.AreEqual("https://www.yeduji.com/book/155532/", page.CatalogUrl!.AbsoluteUri);
        Assert.AreEqual("https://www.yeduji.com/book/155532/4294433.html", page.NextChapterUrl!.AbsoluteUri);
        Assert.AreEqual(2, page.Paragraphs.Count);
    }

    [TestMethod]
    public void GenericParserPrefersNarrowBodyAndDescriptionMetadata()
    {
        var url = new Uri("https://example.com/book/75012/3.html");
        var page = ParseGenericChapter(url, """
            <head>
              <title>示例小说 第3章 卡塞尔之门（第1页/共2页）-小说站</title>
              <meta name="description" content="小说站提供了示例作者创作的《示例小说》第3章在线阅读。">
            </head>
            <header><h1><a href="/">小说站</a></h1></header>
            <div class="reader-main">
              <div class="reader-fun">字体 大 中 小 背景颜色 护眼模式</div>
              <h1 class="title">第3章 卡塞尔之门（第1页/共2页）</h1>
              <a id="index_url" href="/book/75012/">章节目录</a>
              <a id="next_url" href="3_2.html">下一页</a>
              <div id="content">
                <p>路上发生了许多事情，这是正文第一段，长度足够用于通用正文候选判断。</p>
                <p>人物继续向前，这是正文第二段，页面上的阅读设置不应被混入这里。</p>
              </div>
            </div>
            """);

        Assert.AreEqual("第3章 卡塞尔之门", page.Title);
        Assert.AreEqual("示例小说", page.BookTitle);
        Assert.AreEqual("示例作者", page.Author);
        Assert.AreEqual(2, page.Paragraphs.Count);
        Assert.IsFalse(string.Concat(page.Paragraphs).Contains("字体 大 中 小", StringComparison.Ordinal));
        Assert.AreEqual("https://example.com/book/75012/3_2.html", page.NextPageUrl!.AbsoluteUri);
    }

    [TestMethod]
    public void GenericParserDoesNotMistakeLongCatalogForChapter()
    {
        var url = new Uri("https://example.com/read/1490/");
        var chapters = string.Concat(Enumerable.Range(1, 10)
            .Select(index => $"<dd><a href='{index}.html'>第{index}章 示例章节</a></dd>"));
        var html = $$"""
            <head>
              <meta property="og:novel:book_name" content="目录示例小说">
              <meta property="og:novel:author" content="目录作者">
            </head>
            <div id="content-list">
              <div class="intro">这里是很长的作品简介，不能被当成小说正文。这里是很长的作品简介，不能被当成小说正文。</div>
              <dl>{{chapters}}</dl>
            </div>
            """;
        var loaded = new LoadedHtml(url, url, html, HtmlRetrievalKind.UrlSession);

        var catalog = new GenericNovelAdapter().ParseCatalogPage(loaded);

        Assert.AreEqual("目录示例小说", catalog.Title);
        Assert.AreEqual("目录作者", catalog.Author);
        Assert.AreEqual(10, catalog.Chapters.Count);
        Assert.ThrowsException<NovelParsingException>(() => new GenericNovelAdapter().ParseChapterPage(loaded));
    }

    [TestMethod]
    public void GenericBookLandingFindsCompleteCatalogAndUsesNestedHeadingTitles()
    {
        var landingUrl = new Uri("https://reader.example/book/155532/");
        var landing = new GenericNovelAdapter().ParseCatalogPage(new LoadedHtml(
            landingUrl,
            landingUrl,
            """
            <meta name="description" content="本书由作者 测试作者 创作"><h1>完整目录测试</h1>
            <div class="chapter-list">
              <a href="766.html"><h4>后记</h4><small>VIP</small></a>
              <a href="765.html"><h4>第766章 终章之后</h4><small>免费</small></a>
            </div>
            <div class="chapter-more"><a href="list/">全部章节</a></div>
            """,
            HtmlRetrievalKind.UrlSession));

        CollectionAssert.AreEqual(
            new[] { "后记", "第766章 终章之后" },
            landing.Chapters.Select(chapter => chapter.Title).ToArray());
        Assert.AreEqual("测试作者", landing.Author);
        Assert.AreEqual("https://reader.example/book/155532/list/", landing.NextPageUrl!.AbsoluteUri);

        var completeUrl = landing.NextPageUrl!;
        var complete = new GenericNovelAdapter().ParseCatalogPage(new LoadedHtml(
            completeUrl,
            completeUrl,
            """
            <h1>完整目录测试</h1><div class="chapter-list">
              <a href="preface.html"><h4>序言</h4><small>免费</small></a>
              <a href="1.html"><h4>第1章 开始</h4><small>免费</small></a>
              <a href="765.html"><h4>第766章 终章之后</h4><small>免费</small></a>
              <a href="766.html"><h4>后记</h4><small>VIP</small></a>
            </div>
            """,
            HtmlRetrievalKind.UrlSession));

        CollectionAssert.AreEqual(
            new[] { "序言", "第1章 开始", "第766章 终章之后", "后记" },
            complete.Chapters.Select(chapter => chapter.Title).ToArray());
    }

    [TestMethod]
    public async Task CompleteCatalogReplacesReverseOrderedLatestPreview()
    {
        var landing = new Uri("https://example.com/book/preview/");
        var complete = new Uri("https://example.com/book/preview/list/");
        var loader = new DictionaryHtmlLoader(new Dictionary<Uri, string>
        {
            [landing] = """
                <h1>目录替换测试</h1><p>作者：测试作者</p><div class="chapter-list">
                  <a href="/book/preview/4.html">后记</a>
                  <a href="/book/preview/3.html">第2章 结束</a>
                </div><a href="list/">全部章节</a>
                """,
            [complete] = """
                <h1>目录替换测试</h1><p>作者：测试作者</p><div class="chapter-list">
                  <a href="/book/preview/0.html">序言</a>
                  <a href="/book/preview/1.html">第1章 开始</a>
                  <a href="/book/preview/3.html">第2章 结束</a>
                  <a href="/book/preview/4.html">后记</a>
                </div>
                """
        });

        var catalog = await new NovelImportCoordinator(loader).RefreshCatalogAsync(landing);

        CollectionAssert.AreEqual(new[] { landing, complete }, loader.RequestedUris.ToArray());
        CollectionAssert.AreEqual(
            new[] { "序言", "第1章 开始", "第2章 结束", "后记" },
            catalog.Chapters.Select(chapter => chapter.Title).ToArray());
        CollectionAssert.AreEqual(new[] { 1, 2, 3, 4 }, catalog.Chapters.Select(chapter => chapter.SortIndex).ToArray());
    }

    [TestMethod]
    public void GenericParserExtractsLandingMetadataAndRemovesWatermarks()
    {
        var catalogUrl = new Uri("https://example.com/series/volume/");
        var catalog = new GenericNovelAdapter().ParseCatalogPage(new LoadedHtml(
            catalogUrl,
            catalogUrl,
            """
            <header><h1 id="logo">小说站</h1></header>
            <div class="book-describe"><h1>示例小说 第三部 下</h1><p>作者：示例作者</p></div>
            <div class="book-list"><a href="1.html">楔子</a><a href="2.html">第一章 开始 · 一</a></div>
            """,
            HtmlRetrievalKind.UrlSession));
        Assert.AreEqual("示例小说 第三部 下", catalog.Title);
        Assert.AreEqual("示例作者", catalog.Author);

        var chapterUrl = new Uri("https://example.com/series/2.html");
        var page = ParseGenericChapter(chapterUrl, """
            <header><h1 id="logo">小说站</h1></header>
            <nav class="bcrumb"><a href="volume/" rel="category tag">示例小说 第三部 下</a></nav>
            <article class="post">
              <h1 id="nr_title">第一章 开始 · 一</h1>
              <div class="nr_set">关灯 护眼 小 中 大 繁 直达底部</div>
              <a href="1.html" rel="prev">上一章</a><a href="3.html" rel="next">下一章</a>
              <div id="nr1">
                <p>正文第一段有足够多的内容，设置选项不应该跟随正文进入原生阅读界面。</p>
                <p>🍐 落`霞-读`书-l u o x i a d u s h u . c o m-</p>
                <p>正文第二段继续讲述故事，并保持为一个独立、干净且稳定的段落。<a href="/">落霞</a></p>
              </div>
            </article>
            """);

        Assert.AreEqual("第一章 开始 · 一", page.Title);
        Assert.AreEqual("示例小说 第三部 下", page.BookTitle);
        Assert.AreEqual(2, page.Paragraphs.Count);
        Assert.IsFalse(string.Concat(page.Paragraphs).Contains("落`霞", StringComparison.Ordinal));
        Assert.IsFalse(page.Paragraphs[^1].EndsWith("落霞", StringComparison.Ordinal));
        Assert.AreEqual("https://example.com/series/3.html", page.NextChapterUrl!.AbsoluteUri);
    }

    [TestMethod]
    public void GenericParserRemovesEmbeddedNavigationAndReaderModeNotices()
    {
        var url = new Uri("https://reader.example/douluodalu2/29797.html");
        var page = ParseGenericChapter(url, """
            <head><title>第二章 苏醒_斗罗大陆Ⅱ绝世唐门</title></head>
            <h1>第二章 苏醒</h1>
            <div id="content">
              <p>上一章：引子 神界！唐三一家</p>
              <p>下一章：第一章 灵眸少年（二）</p>
              <p>如果被/浏/览/器/强/制进入它们的阅/读/模/式了，阅读体/验极/差请退出转/码阅读。</p>
              <p>清晨的阳光落在窗前，少年缓缓睁开眼睛，回想起昨夜发生的事情。</p>
              <div class="chapter-nav"><a href="29796.html">上一章</a> | <a href="index.html">章节目录</a> | <a href="29798.html">下一章</a></div>
              <p>他起身推开房门，远处的钟声响起，崭新的一天就这样开始了。</p>
              <p>故事里曾经提到上一章留下的疑问，但这是一句正常正文，不能被误删。</p>
            </div>
            """);

        Assert.AreEqual(3, page.Paragraphs.Count);
        Assert.IsFalse(page.Paragraphs.Any(paragraph => paragraph.StartsWith("上一章：", StringComparison.Ordinal)));
        Assert.IsFalse(page.Paragraphs.Any(paragraph => paragraph.StartsWith("下一章：", StringComparison.Ordinal)));
        Assert.IsFalse(page.Paragraphs.Any(paragraph => paragraph.Contains("转/码阅读", StringComparison.Ordinal)));
        Assert.IsTrue(page.Paragraphs.Any(paragraph => paragraph.Contains("上一章留下的疑问", StringComparison.Ordinal)));
        Assert.AreEqual("https://reader.example/douluodalu2/29796.html", page.PreviousChapterUrl!.AbsoluteUri);
        Assert.AreEqual("https://reader.example/douluodalu2/29798.html", page.NextChapterUrl!.AbsoluteUri);
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

    [TestMethod]
    public async Task HybridLoaderPreferredHostsAllowParallelPromotionAndReads()
    {
        var loader = new HybridHtmlLoader(new ConstantHtmlLoader(), new ConstantRenderedLoader());
        var urls = Enumerable.Range(0, 200)
            .Select(index => new Uri($"https://host-{index % 12}.example/book/"))
            .ToArray();

        await Task.WhenAll(urls.Select(async url =>
        {
            loader.PromoteRenderedDomHost(url);
            await loader.LoadAsync(url);
            _ = loader.BrowserPreferredHosts.Count;
        }));

        Assert.AreEqual(12, loader.BrowserPreferredHosts.Count);
    }

    [TestMethod]
    public async Task HybridLoaderFallsBackToBrowserForPlainHttp403()
    {
        var staticLoader = new ThrowingHtmlLoader(
            new HtmlLoadException(HtmlLoadErrorKind.HttpStatus, statusCode: 403));
        var browserLoader = new ConstantRenderedLoader();
        var loader = new HybridHtmlLoader(staticLoader, browserLoader);
        var url = new Uri("https://example.com/book/101.html");

        var result = await loader.LoadAsync(url);

        Assert.AreEqual(HtmlRetrievalKind.WebView2, result.RetrievalKind);
        CollectionAssert.Contains(loader.BrowserPreferredHosts.ToList(), url.DnsSafeHost);
    }

    private static string ReadFixture(string name) =>
        File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "Fixtures", $"{name}.html"));

    private static ParsedChapterPage ParseGenericChapter(Uri url, string html) =>
        new GenericNovelAdapter().ParseChapterPage(new LoadedHtml(
            url,
            url,
            html,
            HtmlRetrievalKind.UrlSession));

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

    private sealed class ThrowingHtmlLoader(Exception exception) : IHtmlDocumentLoader
    {
        public void BeginOperation()
        {
        }

        public Task<LoadedHtml> LoadAsync(Uri url, CancellationToken cancellationToken = default) =>
            Task.FromException<LoadedHtml>(exception);
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

    private sealed class ConstantHtmlLoader : IHtmlDocumentLoader
    {
        public void BeginOperation() { }

        public Task<LoadedHtml> LoadAsync(Uri url, CancellationToken cancellationToken = default) =>
            Task.FromResult(new LoadedHtml(url, url, "<html></html>", HtmlRetrievalKind.UrlSession));
    }

    private sealed class ConstantRenderedLoader : IRenderedDomFallbackLoading
    {
        public void BeginOperation() { }
        public void PromoteRenderedDomHost(Uri url) { }
        public Task<LoadedHtml> LoadAsync(Uri url, CancellationToken cancellationToken = default) =>
            LoadRenderedDomAsync(url, cancellationToken);
        public Task<LoadedHtml> LoadRenderedDomAsync(Uri url, CancellationToken cancellationToken = default) =>
            Task.FromResult(new LoadedHtml(url, url, "<html></html>", HtmlRetrievalKind.WebView2));
    }
}
