using YYReader.Windows.Core.Models;
using YYReader.Windows.Core.Reading;

namespace YYReader.Windows.Views;

public enum ReaderItemKind
{
    Header,
    Paragraph,
    Footer,
    AcademicBlock,
    AcademicSupplement
}

public sealed class ReaderItem(
    ReaderItemKind kind,
    Chapter chapter,
    int paragraphIndex = 0,
    IReadOnlyList<string>? paragraphs = null)
{
    public AcademicPaperPlan? PaperPlan { get; set; }
    public AcademicSupplement? Supplement { get; set; }
    public int EndParagraphIndex { get; set; }
    public int ColumnForParagraph(int index, bool preferTwoColumns, double width) =>
        preferTwoColumns && width >= 760 && index >= ParagraphIndex + (EndParagraphIndex - ParagraphIndex + 1) / 2 ? 1 : 0;
    public bool ContainsParagraph(int index) => IsParagraph ? index == ParagraphIndex : Kind == ReaderItemKind.AcademicBlock && index >= ParagraphIndex && index < EndParagraphIndex;
    public ReaderItemKind Kind { get; } = kind;
    public Chapter Chapter { get; } = chapter;
    public int ParagraphIndex { get; } = paragraphIndex;
    public string ChapterUrl => Chapter.SourceUrl;
    public int ParagraphCount => paragraphs?.Count ?? 0;
    public string Text => Kind is ReaderItemKind.Header or ReaderItemKind.Footer
        ? Chapter.Title
        : paragraphs is not null && ParagraphIndex >= 0 && ParagraphIndex < paragraphs.Count
            ? paragraphs[ParagraphIndex]
            : "";
    public bool IsParagraph => Kind == ReaderItemKind.Paragraph;
}
