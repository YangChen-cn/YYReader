using Microsoft.VisualStudio.TestTools.UnitTesting;
using YYReader.Windows.Core.Models;
using YYReader.Windows.Core.Reading;
using YYReader.Windows.Core.Collections;

namespace YYReader.Windows.Tests;

[TestClass]
public sealed class ReaderBehaviorTests
{
    [TestMethod]
    public void ParagraphCacheHasBoundedLruCapacityAndRefreshesChangedContent()
    {
        var cache = new ChapterParagraphCache(2);
        var first = NewChapter("https://example.com/1.html", "第一段");
        var second = NewChapter("https://example.com/2.html", "第二段");
        var third = NewChapter("https://example.com/3.html", "第三段");

        cache.Get(first);
        cache.Get(second);
        cache.Get(first);
        cache.Get(third);

        Assert.AreEqual(2, cache.Count);
        first.ReplaceBodyText("更新后的第一段");
        CollectionAssert.AreEqual(new[] { "更新后的第一段" }, cache.Get(first).ToArray());
    }

    [TestMethod]
    public void ContinuousSessionNeverRemovesAlreadyAttachedChapters()
    {
        var session = new ContinuousReaderSession();
        var first = NewChapter("https://example.com/1.html", "第一段");
        var second = NewChapter("https://example.com/2.html", "第二段");
        var third = NewChapter("https://example.com/3.html", "第三段");

        session.Reset(first);
        Assert.AreSame(first, session.LastChapter);
        Assert.IsFalse(first.IsCached, "连续会话解析段落后应释放聚合正文字符串");
        CollectionAssert.AreEqual(new[] { "第一段" }, session.Entries[0].Paragraphs.ToArray());
        Assert.IsTrue(session.AttachNext(second));
        Assert.IsTrue(session.AttachNext(third));
        Assert.AreSame(third, session.LastChapter,
            "查找连续阅读后继必须从 session 尾部开始，不能依赖可能滞后的可见章节");
        Assert.AreEqual(3, session.Entries.Count);
        Assert.IsFalse(session.AttachNext(second));
    }

    [TestMethod]
    public void RestorePositionUsesSessionParagraphCountAfterBodyTextIsReleased()
    {
        var chapter = NewChapter(
            "https://example.com/1.html",
            string.Join("\n\n", Enumerable.Range(0, 12).Select(index => $"第{index}段")));
        chapter.ApplyProgress(7, 12, DateTimeOffset.UtcNow);
        var session = new ContinuousReaderSession();

        session.Reset(chapter);

        Assert.IsFalse(chapter.IsCached, "session 创建后应继续释放 BodyText");
        Assert.AreEqual(0, chapter.Paragraphs.Count);
        var paragraphCount = session.ParagraphCount(chapter.SourceUrl);
        Assert.AreEqual(12, paragraphCount);
        Assert.AreEqual(7, ReaderPosition.RestoreParagraphIndex(
            chapter.ParagraphIndex,
            chapter.Progress,
            paragraphCount));
    }

    [TestMethod]
    public void RelativeContentWidthAndKeyboardPageDistanceRemainStable()
    {
        Assert.AreEqual(960, ReaderLayout.EffectiveContentWidth(48, 20, 1_200));
        Assert.AreEqual(704, ReaderPageScroll.PageDistance(800));
        Assert.AreEqual(1_620, ReaderPageScroll.DestinationY(1_508, 800, 3_000, ReaderPageScroll.SmallStep));
        Assert.AreEqual(0, ReaderPageScroll.DestinationY(0, 800, 3_000, -112));
    }

    [TestMethod]
    public void ContinuousReadingLoadsBeforeTheScrollableEndRegardlessOfParagraphLength()
    {
        Assert.IsFalse(ReaderPageScroll.ShouldLoadNext(6_000, 8_000, 800));
        Assert.IsTrue(ReaderPageScroll.ShouldLoadNext(7_100, 8_000, 800));
        Assert.IsTrue(ReaderPageScroll.ShouldLoadNext(8_000, 8_000, 800));
        Assert.IsFalse(ReaderPageScroll.ShouldRearmNextLoad(7_000, 8_100, 800),
            "加载边界自身的微小高度变化不能重新武装自动加载");
        Assert.IsTrue(ReaderPageScroll.ShouldRearmNextLoad(5_000, 8_100, 800));
    }

    [TestMethod]
    public void ContinuousFailedLoadRetriesOnlyAfterLeavingNearEndOrImmediatelyByUser()
    {
        var state = new ReaderContinuousLoadState(TimeSpan.FromSeconds(4));
        var now = DateTimeOffset.Parse("2026-08-12T00:00:00Z");

        state.ObserveNearEnd("https://example.com/1.html", isNearEnd: true);
        Assert.IsTrue(state.TryBegin("https://example.com/1.html", now));
        state.MarkFailed(now);
        Assert.IsFalse(state.TryBegin("https://example.com/1.html", now.AddSeconds(2)));
        Assert.IsTrue(state.TryBegin("https://example.com/1.html", now.AddSeconds(2), explicitRetry: true));
        state.MarkFailed(now.AddSeconds(2));

        Assert.IsFalse(state.TryBegin("https://example.com/1.html", now.AddSeconds(7)),
            "停留在章末时不能因布局/ViewChanged 反复自动重试");
        state.ObserveNearEnd("https://example.com/1.html", isNearEnd: false);
        state.ObserveNearEnd("https://example.com/1.html", isNearEnd: true);
        Assert.IsTrue(state.TryBegin("https://example.com/1.html", now.AddSeconds(7)));
    }

    [TestMethod]
    public void CatalogRefreshResetAllowsContinuousLoadingAfterPreviouslyReachingLatestChapter()
    {
        var state = new ReaderContinuousLoadState();
        var now = DateTimeOffset.Parse("2026-08-12T00:00:00Z");

        Assert.IsTrue(state.TryBegin("https://example.com/100.html", now));
        Assert.IsFalse(state.TryBegin("https://example.com/100.html", now));

        state.Reset();

        Assert.IsTrue(state.TryBegin("https://example.com/100.html", now));
    }

    [TestMethod]
    public void BodyTextNormalizationProducesParagraphsWithoutEmptyRows()
    {
        var chapter = NewChapter("https://example.com/1.html", " 第一段 \r\n\r\n 第二段 ");

        CollectionAssert.AreEqual(new[] { "第一段", "第二段" }, chapter.Paragraphs.ToArray());
    }

    [TestMethod]
    public void ReaderDefaultsMatchTheQuietMacReadingFlow()
    {
        Assert.IsFalse(ReaderPreferences.Defaults.ContinuousReading);
        Assert.IsTrue(ReaderPreferences.Defaults.PrefetchNextChapter);
        Assert.AreEqual(48, ReaderPreferences.Defaults.ContentWidthEm);
        Assert.IsTrue(ReaderPreferences.Defaults.ParagraphIndent);
    }

    [TestMethod]
    public void ReaderAnchorKeepsChapterAndClampsParagraphAfterLayoutChanges()
    {
        var anchor = new ReaderAnchor("https://example.com/2.html", 42, 0.25);

        var restored = anchor.Normalized(20);

        Assert.AreEqual("https://example.com/2.html", restored.ChapterUrl);
        Assert.AreEqual(19, restored.ParagraphIndex);
        Assert.AreEqual(0.25, restored.ViewportRelativeOffset, 0.0001);
    }

    [TestMethod]
    public void ReaderAnchorPreservesNegativeParagraphViewportOffset()
    {
        var anchor = new ReaderAnchor("https://example.com/2.html", 8, -0.37);

        var restored = anchor.Normalized(20);

        Assert.AreEqual("https://example.com/2.html", restored.ChapterUrl);
        Assert.AreEqual(8, restored.ParagraphIndex);
        Assert.AreEqual(-0.37, restored.ViewportRelativeOffset, 0.0001);
    }

    [TestMethod]
    public void OpeningCatalogCentersTheVisibleReadingChapter()
    {
        var source = File.ReadAllText(Path.Combine(
            AppContext.BaseDirectory,
            "..", "..", "..", "..", "..", "windows", "YYReader.Windows", "Views", "ReaderPage.xaml.cs"));
        var centerStart = source.IndexOf("private void CenterCatalogOnCurrentChapter", StringComparison.Ordinal);
        var centerEnd = source.IndexOf("private void CenterCatalogItemAfterLayout", centerStart, StringComparison.Ordinal);
        var centerMethod = source[centerStart..centerEnd];
        var openStart = source.IndexOf("private void OpenCatalog", StringComparison.Ordinal);
        var openEnd = source.IndexOf("private void CloseCatalog_Click", openStart, StringComparison.Ordinal);
        var openMethod = source[openStart..openEnd];

        StringAssert.Contains(centerMethod, "FindVisibleParagraph()?.ChapterUrl");
        StringAssert.Contains(source, "VerticalAlignmentRatio = 0.5");
        StringAssert.Contains(openMethod, "CenterCatalogOnCurrentChapter()");
    }

    [TestMethod]
    public void RangeCollectionRaisesOneNotificationForAnAppendedChapter()
    {
        var collection = new RangeObservableCollection<int>();
        var notifications = 0;
        collection.CollectionChanged += (_, _) => notifications++;

        collection.AddRange(Enumerable.Range(1, 500));

        Assert.AreEqual(500, collection.Count);
        Assert.AreEqual(1, notifications);
    }

    [TestMethod]
    public void LibraryBookProgressDisplayReflectsUpdatedCurrentChapterWhenRebound()
    {
        var chapter = NewChapter("https://example.com/1.html", "第一段\n\n第二段\n\n第三段\n\n第四段");
        var book = new Book(
            "book", "https://example.com/book/", "https://example.com/book/", "测试", "作者", "example.com",
            true, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow, currentChapterUrl: chapter.SourceUrl);
        book.Chapters.Add(chapter);

        chapter.ApplyProgress(2, 4, DateTimeOffset.UtcNow);

        Assert.AreEqual("67%", book.ProgressDisplay);
        Assert.AreEqual("测试章节", book.CurrentChapterTitle);
    }

    private static Chapter NewChapter(string url, string body) =>
        new(url, "测试章节", 1, body, cachedAt: DateTimeOffset.UtcNow);
}
