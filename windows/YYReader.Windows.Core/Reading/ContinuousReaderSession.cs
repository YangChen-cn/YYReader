using YYReader.Windows.Core.Models;

namespace YYReader.Windows.Core.Reading;

public sealed class ContinuousReaderSession
{
    private readonly ChapterParagraphCache _paragraphCache;
    private readonly List<Entry> _entries = new();

    public ContinuousReaderSession(int paragraphCacheCapacity = 8)
    {
        _paragraphCache = new ChapterParagraphCache(paragraphCacheCapacity);
    }

    public IReadOnlyList<Entry> Entries => _entries;
    public Chapter? LastChapter => _entries.LastOrDefault()?.Chapter;
    public string? VisibleChapterUrl { get; private set; }
    public int CachedParagraphChapterCount => _paragraphCache.Count;

    public void Reset(Chapter? chapter)
    {
        _entries.Clear();
        VisibleChapterUrl = null;
        if (chapter is not { IsCached: true })
        {
            return;
        }

        _entries.Add(new Entry(chapter, _paragraphCache));
        VisibleChapterUrl = chapter.SourceUrl;
    }

    public void UpdateVisibleChapter(string chapterUrl) => VisibleChapterUrl = chapterUrl;

    public bool AttachNext(Chapter chapter)
    {
        if (!chapter.IsCached || _entries.Any(entry => entry.Chapter.SourceUrl == chapter.SourceUrl))
        {
            return false;
        }

        _entries.Add(new Entry(chapter, _paragraphCache));
        return true;
    }

    public IReadOnlyList<string> GetParagraphs(Chapter chapter) => _paragraphCache.Get(chapter);

    public sealed class Entry
    {
        internal Entry(Chapter chapter, ChapterParagraphCache paragraphCache)
        {
            Chapter = chapter;
            Paragraphs = paragraphCache.Get(chapter);
            chapter.ReleaseLoadedBody();
        }

        public Chapter Chapter { get; }
        public IReadOnlyList<string> Paragraphs { get; }
    }
}
