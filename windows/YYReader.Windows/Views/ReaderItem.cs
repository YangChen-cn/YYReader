using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using YYReader.Windows.Core.Models;

namespace YYReader.Windows.Views;

public enum ReaderItemKind
{
    Header,
    Paragraph,
    Footer
}

public sealed class ReaderItem
{
    public ReaderItemKind Kind { get; set; }
    public string Text { get; set; } = "";
    public string ChapterUrl { get; set; } = "";
    public int ParagraphIndex { get; set; }
    public int ParagraphCount { get; set; }
    public double FontSize { get; set; }
    public double LineHeight { get; set; }
    public FontFamily FontFamily { get; set; } = new("Microsoft YaHei UI");
    public Thickness Margin { get; set; }
    public Brush Foreground { get; set; } = new SolidColorBrush(Microsoft.UI.Colors.Black);
    public bool IsParagraph => Kind == ReaderItemKind.Paragraph;
}

public sealed class ReaderItemTemplateSelector : DataTemplateSelector
{
    public DataTemplate? HeaderTemplate { get; set; }
    public DataTemplate? ParagraphTemplate { get; set; }
    public DataTemplate? FooterTemplate { get; set; }

    protected override DataTemplate? SelectTemplateCore(object item, DependencyObject container)
    {
        return item is ReaderItem readerItem
            ? readerItem.Kind switch
            {
                ReaderItemKind.Header => HeaderTemplate,
                ReaderItemKind.Footer => FooterTemplate,
                _ => ParagraphTemplate
            }
            : base.SelectTemplateCore(item, container);
    }
}
