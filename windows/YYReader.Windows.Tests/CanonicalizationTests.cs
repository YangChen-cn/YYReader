using Microsoft.VisualStudio.TestTools.UnitTesting;
using YYReader.Windows.Core.Models;

namespace YYReader.Windows.Tests;

[TestClass]
public sealed class CanonicalizationTests
{
    [TestMethod]
    public void QidiyChapterPaginationSuffixIsRemovedWithoutMergingOtherChapters()
    {
        var paged = UrlCanonicalizer.CanonicalizeChapter("https://WWW.QIDIY.com:443/book/100/1/2.html#top");
        var other = UrlCanonicalizer.CanonicalizeChapter("https://www.qidiy.com/book/100/2.html");

        Assert.AreEqual("https://www.qidiy.com/book/100/1.html", paged.AbsoluteUri);
        Assert.AreEqual("https://www.qidiy.com/book/100/2.html", other.AbsoluteUri);
        Assert.AreNotEqual(paged, other);
    }

    [TestMethod]
    public void SourceBookIdentityUsesBookPathWhenAvailable()
    {
        var identity = UrlCanonicalizer.SourceBookIdentityForChapter(
            new Uri("https://example.com/serial/quiet-river/12.html"),
            "示例小说",
            "示例作者");

        Assert.AreEqual("https://example.com/serial/quiet-river/", identity.AbsoluteUri);
    }

    [TestMethod]
    public void InputWithoutSchemeDefaultsToHttpsAndRejectsNonHttp()
    {
        Assert.AreEqual("https://example.com/book/", UrlCanonicalizer.NormalizeInput("example.com/book/")!.AbsoluteUri);
        Assert.IsNull(UrlCanonicalizer.NormalizeInput("file:///tmp/book.html"));
    }
}
