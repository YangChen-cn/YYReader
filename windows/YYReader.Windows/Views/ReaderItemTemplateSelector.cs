using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace YYReader.Windows.Views;

public sealed class ReaderItemTemplateSelector : DataTemplateSelector
{
    public DataTemplate? HeaderTemplate { get; set; }
    public DataTemplate? ParagraphTemplate { get; set; }
    public DataTemplate? FooterTemplate { get; set; }
    public DataTemplate? AcademicTemplate { get; set; }

    protected override DataTemplate? SelectTemplateCore(object item, DependencyObject container) =>
        item is ReaderItem readerItem
            ? readerItem.Kind switch
            {
                ReaderItemKind.Header => HeaderTemplate,
                ReaderItemKind.Footer => FooterTemplate,
                ReaderItemKind.AcademicBlock or ReaderItemKind.AcademicSupplement => AcademicTemplate,
                _ => ParagraphTemplate
            }
            : base.SelectTemplateCore(item, container);
}
