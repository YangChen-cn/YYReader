using Microsoft.VisualStudio.TestTools.UnitTesting;
using YYReader.Windows.Core.Models;
using YYReader.Windows.Core.Transfer;

namespace YYReader.Windows.Tests;

[TestClass]
public sealed class TransferTests
{
    [TestMethod]
    public void DecodeAcceptsV1AndIgnoresUnknownOptionalFields()
    {
        var document = BookshelfTransferCodec.Decode("""
            {
              "format": "yyreader-bookshelf",
              "version": 1,
              "exportedAt": "2026-08-11T12:00:00Z",
              "futureOptionalField": { "keep": true },
              "books": [{
                "sourceURL": "https://example.com/book/",
                "title": "测试书",
                "author": "测试作者",
                "progress": 0.63,
                "futureBookField": "ignored"
              }]
            }
            """);

        Assert.AreEqual(BookshelfTransferCodec.Format, document.Format);
        Assert.AreEqual(1, document.Version);
        Assert.AreEqual(1, document.Books.Count);
        Assert.AreEqual(0.63, document.Books[0].Progress);
    }

    [TestMethod]
    public void MalformedJsonAndUnsupportedVersionAreReportedSeparately()
    {
        var malformed = Assert.ThrowsException<BookshelfTransferException>(() => BookshelfTransferCodec.Decode("{"));
        Assert.AreEqual(BookshelfTransferErrorKind.MalformedJson, malformed.Kind);

        var version = Assert.ThrowsException<BookshelfTransferException>(() => BookshelfTransferCodec.Decode("""
            {"format":"yyreader-bookshelf","version":2,"exportedAt":"2026-08-11T12:00:00Z","books":[]}
            """));
        Assert.AreEqual(BookshelfTransferErrorKind.UnsupportedVersion, version.Kind);
    }

    [TestMethod]
    public void PreviewSeparatesNewExistingDuplicateAndInvalidBooks()
    {
        var existing = new Book(
            "book-id",
            "https://example.com/book/",
            "https://example.com/book/",
            "旧书",
            "作者",
            "example.com",
            true,
            DateTimeOffset.UtcNow,
            DateTimeOffset.UtcNow);
        var document = new BookshelfTransferDocument
        {
            Format = BookshelfTransferCodec.Format,
            Version = 1,
            ExportedAt = "2026-08-11T12:00:00Z",
            Books =
            [
                new() { SourceUrl = "https://example.com/book/", Title = "旧书", Author = "作者" },
                new() { SourceUrl = "https://example.com/book/", Title = "重复", Author = "作者" },
                new() { SourceUrl = "https://example.com/new/", Title = "新书", Author = "作者" },
                new() { SourceUrl = "not a url", Title = "坏数据", Author = "作者" }
            ]
        };

        var preview = BookshelfTransferPlanner.Preview(document, [existing]);

        Assert.AreEqual(1, preview.NewCount);
        Assert.AreEqual(1, preview.ExistingCount);
        Assert.AreEqual(1, preview.DuplicateCount);
        Assert.AreEqual(1, preview.InvalidCount);
    }

    [TestMethod]
    public void ReadingPositionUsesIndexFirstAndProgressAsOutOfRangeFallback()
    {
        Assert.AreEqual(12, ReaderPosition.RestoreParagraphIndex(12, 0.9, 40));
        Assert.AreEqual(20, ReaderPosition.RestoreParagraphIndex(99, 0.5, 40));
        Assert.AreEqual(1, ReaderPosition.RestoreParagraphIndex(null, 1, 2));
        Assert.AreEqual(0.5, ReaderPosition.ProgressForParagraph(1, 3), 0.0001);
    }
}
