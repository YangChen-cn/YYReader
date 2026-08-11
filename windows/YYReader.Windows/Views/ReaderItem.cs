using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using YYReader.Windows.Core.Models;

namespace YYReader.Windows.Views;

public enum ReaderItemKind
{
    Header,
    Paragraph,
    Footer
}

public sealed class ReaderItem(
    ReaderItemKind kind,
    Chapter chapter,
    int paragraphIndex = 0,
    IReadOnlyList<string>? paragraphs = null)
{
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

public sealed class ReaderItemTemplateSelector : DataTemplateSelector
{
    public DataTemplate? HeaderTemplate { get; set; }
    public DataTemplate? ParagraphTemplate { get; set; }
    public DataTemplate? FooterTemplate { get; set; }

    protected override DataTemplate? SelectTemplateCore(object item, DependencyObject container) =>
        item is ReaderItem readerItem
            ? readerItem.Kind switch
            {
                ReaderItemKind.Header => HeaderTemplate,
                ReaderItemKind.Footer => FooterTemplate,
                _ => ParagraphTemplate
            }
            : base.SelectTemplateCore(item, container);
}
