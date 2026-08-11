using YYReader.Windows.Core.Models;

namespace YYReader.Windows.Core.Transfer;

public static class BookshelfTransferExporter
{
    public static IReadOnlyList<BookshelfTransferBook> FromBooks(IEnumerable<Book> books) =>
        books.Select(book =>
        {
            var chapter = book.CurrentChapter;
            return new BookshelfTransferBook
            {
                SourceUrl = book.SourceBookUrl,
                Title = book.Title,
                Author = book.Author,
                CurrentChapterUrl = chapter?.SourceUrl,
                ParagraphIndex = chapter?.ParagraphIndex,
                Progress = chapter?.Progress
            };
        }).ToArray();
}
