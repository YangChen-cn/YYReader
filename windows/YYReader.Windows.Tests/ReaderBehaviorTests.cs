using Microsoft.VisualStudio.TestTools.UnitTesting;
using YYReader.Windows.Core.Models;
using YYReader.Windows.Core.Reading;

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
    public void BodyTextNormalizationProducesParagraphsWithoutEmptyRows()
    {
        var chapter = NewChapter("https://example.com/1.html", " 第一段 \r\n\r\n 第二段 ");

        CollectionAssert.AreEqual(new[] { "第一段", "第二段" }, chapter.Paragraphs.ToArray());
    }

    private static Chapter NewChapter(string url, string body) =>
        new(url, "测试章节", 1, body, cachedAt: DateTimeOffset.UtcNow);
}
