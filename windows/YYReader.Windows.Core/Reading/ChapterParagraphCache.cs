using YYReader.Windows.Core.Models;

namespace YYReader.Windows.Core.Reading;

public sealed class ChapterParagraphCache
{
    private readonly int _capacity;
    private readonly Dictionary<CacheKey, CacheValue> _values = new();
    private long _accessOrder;

    public ChapterParagraphCache(int capacity = 8)
    {
        _capacity = Math.Max(capacity, 1);
    }

    public int Count => _values.Count;

    public IReadOnlyList<string> Get(Chapter chapter)
    {
        var key = new CacheKey(chapter.SourceUrl, chapter.CachedAt, chapter.ContentRevision);
        _accessOrder++;
        if (_values.TryGetValue(key, out var existing))
        {
            existing.AccessOrder = _accessOrder;
            return existing.Paragraphs;
        }

        foreach (var oldKey in _values.Keys.Where(oldKey => oldKey.SourceUrl == chapter.SourceUrl).ToArray())
        {
            _values.Remove(oldKey);
        }

        var paragraphs = chapter.Paragraphs;
        _values[key] = new CacheValue(paragraphs, _accessOrder);
        if (_values.Count > _capacity)
        {
            var oldest = _values.MinBy(pair => pair.Value.AccessOrder).Key;
            _values.Remove(oldest);
        }

        return paragraphs;
    }

    public void Clear() => _values.Clear();

    private readonly record struct CacheKey(string SourceUrl, DateTimeOffset? CachedAt, int Revision);

    private sealed class CacheValue(IReadOnlyList<string> paragraphs, long accessOrder)
    {
        public IReadOnlyList<string> Paragraphs { get; } = paragraphs;
        public long AccessOrder { get; set; } = accessOrder;
    }
}
