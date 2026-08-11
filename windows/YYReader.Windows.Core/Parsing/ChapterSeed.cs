using YYReader.Windows.Core.Models;

namespace YYReader.Windows.Core.Parsing;

public sealed record ChapterSeed(string Title, Uri Url, int SortIndex)
{
    public ChapterSeed Canonicalized() =>
        this with { Url = UrlCanonicalizer.CanonicalizeChapter(Url) };
}
