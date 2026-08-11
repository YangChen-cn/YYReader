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
        Assert.IsFalse(first.IsCached, "连续会话解析段落后应释放聚合正文字符串");
        CollectionAssert.AreEqual(new[] { "第一段" }, session.Entries[0].Paragraphs.ToArray());
        Assert.IsTrue(session.AttachNext(second));
        Assert.IsTrue(session.AttachNext(third));
        Assert.AreEqual(3, session.Entries.Count);
        Assert.IsFalse(session.AttachNext(second));
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
    }

    [TestMethod]
    public void ContinuousFailedLoadCanRetryAfterCooldownOrImmediatelyByUser()
    {
        var state = new ReaderContinuousLoadState(TimeSpan.FromSeconds(4));
        var now = DateTimeOffset.Parse("2026-08-12T00:00:00Z");

        Assert.IsTrue(state.TryBegin("https://example.com/1.html", now));
        state.MarkFailed(now);
        Assert.IsFalse(state.TryBegin("https://example.com/1.html", now.AddSeconds(2)));
        Assert.IsTrue(state.TryBegin("https://example.com/1.html", now.AddSeconds(2), explicitRetry: true));
        state.MarkFailed(now.AddSeconds(2));
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
    public void RangeCollectionRaisesOneNotificationForAnAppendedChapter()
    {
        var collection = new RangeObservableCollection<int>();
        var notifications = 0;
        collection.CollectionChanged += (_, _) => notifications++;

        collection.AddRange(Enumerable.Range(1, 500));

        Assert.AreEqual(500, collection.Count);
        Assert.AreEqual(1, notifications);
    }

    private static Chapter NewChapter(string url, string body) =>
        new(url, "测试章节", 1, body, cachedAt: DateTimeOffset.UtcNow);
}
