using YYReader.Windows.Core.Reading;

namespace YYReader.Windows.Views;

public static class ReaderItemBuilder
{
    public static IReadOnlyList<ReaderItem> Build(IReadOnlyList<ContinuousReaderSession.Entry> entries, string? academicBookIdentity = null)
    {
        var result = new List<ReaderItem>();
        foreach (var entry in entries) result.AddRange(BuildEntry(entry, academicBookIdentity));
        return result;
    }

    public static IReadOnlyList<ReaderItem> BuildEntry(ContinuousReaderSession.Entry entry, string? academicBookIdentity = null)
    {
        var paragraphs = entry.Paragraphs;
        if (academicBookIdentity is not null)
        {
            var plan = AcademicPaperPlanner.MakePlan(academicBookIdentity, entry.Chapter.SourceUrl, Math.Max(0, entry.Chapter.SortIndex - 1), paragraphs);
            var paperItems = new List<ReaderItem> { new(ReaderItemKind.Header, entry.Chapter) { PaperPlan = plan } };
            var start = 0;
            foreach (var supplement in plan.Supplements)
            {
                paperItems.Add(new(ReaderItemKind.AcademicBlock, entry.Chapter, start, paragraphs) { PaperPlan = plan, EndParagraphIndex = supplement.Index });
                paperItems.Add(new(ReaderItemKind.AcademicSupplement, entry.Chapter) { Supplement = supplement });
                start = supplement.Index;
            }
            paperItems.Add(new(ReaderItemKind.AcademicBlock, entry.Chapter, start, paragraphs) { PaperPlan = plan, EndParagraphIndex = paragraphs.Count });
            paperItems.Add(new(ReaderItemKind.Footer, entry.Chapter));
            return paperItems;
        }
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
