using YYReader.Windows.Core.Reading;

namespace YYReader.Windows.Views;

public static class ReaderItemBuilder
{
    public static IReadOnlyList<ReaderItem> Build(IReadOnlyList<ContinuousReaderSession.Entry> entries)
    {
        var result = new List<ReaderItem>();
        foreach (var entry in entries) result.AddRange(BuildEntry(entry));
        return result;
    }

    public static IReadOnlyList<ReaderItem> BuildEntry(ContinuousReaderSession.Entry entry)
    {
        var paragraphs = entry.Paragraphs;
        var result = new List<ReaderItem>(paragraphs.Count + 2)
        {
            new(ReaderItemKind.Header, entry.Chapter)
        };
        for (var index = 0; index < paragraphs.Count; index++)
        {
            result.Add(new ReaderItem(ReaderItemKind.Paragraph, entry.Chapter, index, paragraphs));
        }
        result.Add(new ReaderItem(ReaderItemKind.Footer, entry.Chapter));
        return result;
    }
}
