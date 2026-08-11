namespace YYReader.Windows.Core.Parsing;

public interface INovelSourceAdapter
{
    bool CanHandle(LoadedHtml document);
    ParsedChapterPage ParseChapterPage(LoadedHtml document);
    ParsedBookCatalog ParseCatalogPage(LoadedHtml document);
}
