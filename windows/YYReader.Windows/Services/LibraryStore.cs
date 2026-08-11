using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using YYReader.Windows.Core.Models;
using YYReader.Windows.Core.Persistence;
using YYReader.Windows.Core.Parsing;
using YYReader.Windows.Core.Reading;
using YYReader.Windows.Core.Services;
using YYReader.Windows.Core.Transfer;

namespace YYReader.Windows.Services;

public sealed class LibraryStore : INotifyPropertyChanged, IAsyncDisposable
{
    private readonly SqliteLibraryRepository _repository;
    private readonly NovelImportCoordinator _coordinator;
    private CancellationTokenSource? _progressSaveCancellation;
    private PendingProgress? _pendingProgress;
    private bool _disposed;
    private Book? _selectedBook;
    private Chapter? _selectedChapter;
    private bool _isBusy;
    private string _statusMessage = "";
    private string? _errorMessage;

    public LibraryStore(SqliteLibraryRepository repository, NovelImportCoordinator coordinator)
    {
        _repository = repository;
        _coordinator = coordinator;
    }

    public ObservableCollection<Book> Books { get; } = new();
    public ContinuousReaderSession ReaderSession { get; } = new();
    public Book? SelectedBook
    {
        get => _selectedBook;
        private set => SetField(ref _selectedBook, value);
    }

    public Chapter? SelectedChapter
    {
        get => _selectedChapter;
        private set => SetField(ref _selectedChapter, value);
    }

    public bool IsBusy
    {
        get => _isBusy;
        private set => SetField(ref _isBusy, value);
    }

    public string StatusMessage
    {
        get => _statusMessage;
        private set => SetField(ref _statusMessage, value);
    }

    public string? ErrorMessage
    {
        get => _errorMessage;
        private set => SetField(ref _errorMessage, value);
    }

    public event PropertyChangedEventHandler? PropertyChanged;
    public event EventHandler? BooksChanged;

    public async Task InitializeAsync(CancellationToken cancellationToken = default)
    {
        await _repository.InitializeAsync(cancellationToken).ConfigureAwait(true);
        await ReloadAsync(cancellationToken).ConfigureAwait(true);
    }

    public async Task ReloadAsync(CancellationToken cancellationToken = default)
    {
        var selectedBookId = SelectedBook?.Id;
        var selectedChapterUrl = SelectedChapter?.SourceUrl;
        var books = await _repository.GetBooksAsync(cancellationToken).ConfigureAwait(true);
        Books.Clear();
        foreach (var book in books)
        {
            Books.Add(book);
        }

        SelectedBook = selectedBookId is null
            ? null
            : Books.FirstOrDefault(book => book.Id == selectedBookId);
        SelectedChapter = SelectedBook is null
            ? null
            : SelectedBook.Chapters.FirstOrDefault(chapter => chapter.SourceUrl == selectedChapterUrl)
                ?? SelectedBook.CurrentChapter;
        ReaderSession.Reset(SelectedChapter);
        BooksChanged?.Invoke(this, EventArgs.Empty);
    }

    public void SelectBook(Book? book)
    {
        if (SelectedBook?.Id == book?.Id)
        {
            return;
        }

        _ = FlushPendingProgressAsync();
        SelectedBook = book;
        SelectedChapter = book?.CurrentChapter;
        ReaderSession.Reset(SelectedChapter);
        OnPropertyChanged(nameof(SelectedBook));
        OnPropertyChanged(nameof(SelectedChapter));
    }

    public async Task SelectChapterAsync(Chapter chapter, CancellationToken cancellationToken = default)
    {
        if (SelectedBook is null)
        {
            return;
        }

        await FlushPendingProgressAsync(cancellationToken).ConfigureAwait(true);
        SelectedChapter = chapter;
        SelectedBook.CurrentChapterUrl = chapter.SourceUrl;
        ReaderSession.Reset(chapter);
        OnPropertyChanged(nameof(SelectedChapter));
        if (!chapter.IsCached)
        {
            await LoadChapterIntoMemoryAsync(chapter, cancellationToken).ConfigureAwait(true);
        }
    }

    public async Task AddUrlAsync(string input, CancellationToken cancellationToken = default)
    {
        var url = UrlCanonicalizer.NormalizeInput(input);
        if (url is null)
        {
            ErrorMessage = "请输入有效的 HTTP 或 HTTPS 小说 URL。";
            return;
        }

        await RunBusyAsync("正在下载并识别小说…", async () =>
        {
            var result = await _coordinator.ImportNovelAsync(url, cancellationToken).ConfigureAwait(true);
            var book = await _repository.UpsertImportAsync(result, cancellationToken).ConfigureAwait(true);
            await ReloadAsync(cancellationToken).ConfigureAwait(true);
            SelectedBook = Books.FirstOrDefault(candidate => candidate.Id == book.Id);
            SelectedChapter = SelectedBook?.Chapters.FirstOrDefault(chapter => chapter.SourceUrl == UrlCanonicalizer.CanonicalizeChapter(result.ChapterUrl).AbsoluteUri);
            ReaderSession.Reset(SelectedChapter);
            OnPropertyChanged(nameof(SelectedBook));
            OnPropertyChanged(nameof(SelectedChapter));
        }, cancellationToken).ConfigureAwait(true);
    }

    public async Task EnsureSelectedChapterLoadedAsync(CancellationToken cancellationToken = default)
    {
        if (SelectedChapter is not null && !SelectedChapter.IsCached)
        {
            await LoadChapterIntoMemoryAsync(SelectedChapter, cancellationToken).ConfigureAwait(true);
        }
        ReaderSession.Reset(SelectedChapter);
    }

    public async Task<Chapter?> PrepareNextChapterAsync(CancellationToken cancellationToken = default)
    {
        if (SelectedBook is null || SelectedChapter is null)
        {
            return null;
        }

        var ordered = SelectedBook.Chapters.OrderBy(chapter => chapter.SortIndex).ToArray();
        var index = Array.FindIndex(ordered, chapter => chapter.SourceUrl == SelectedChapter.SourceUrl);
        var next = index >= 0 && index + 1 < ordered.Length
            ? ordered[index + 1]
            : null;
        if (next is null)
        {
            var linkedNextUrl = SelectedChapter.NextUrl;
            if (!string.IsNullOrWhiteSpace(linkedNextUrl))
            {
                next = SelectedBook.Chapters.FirstOrDefault(chapter =>
                UrlCanonicalizer.CanonicalizeChapter(chapter.SourceUrl).AbsoluteUri
                == UrlCanonicalizer.CanonicalizeChapter(linkedNextUrl).AbsoluteUri);
            if (next is null)
            {
                next = new Chapter(linkedNextUrl, "下一章", SelectedChapter.SortIndex + 1);
                SelectedBook.Chapters.Add(next);
            }
            }
        }

        if (next is null)
        {
            return null;
        }
        if (!next.IsCached)
        {
            await LoadChapterIntoMemoryAsync(next, cancellationToken).ConfigureAwait(true);
        }
        ReaderSession.AttachNext(next);
        return next;
    }

    public void UpdateVisibleReaderPosition(string chapterUrl, int paragraphIndex, int paragraphCount)
    {
        var chapter = SelectedBook?.Chapters.FirstOrDefault(candidate => candidate.SourceUrl == chapterUrl);
        if (chapter is null)
        {
            return;
        }

        var now = DateTimeOffset.UtcNow;
        chapter.ApplyProgress(paragraphIndex, paragraphCount, now);
        SelectedBook!.CurrentChapterUrl = chapter.SourceUrl;
        if (SelectedChapter?.SourceUrl != chapter.SourceUrl)
        {
            SelectedChapter = chapter;
            ReaderSession.UpdateVisibleChapter(chapter.SourceUrl);
            OnPropertyChanged(nameof(SelectedChapter));
        }
        _pendingProgress = new PendingProgress(SelectedBook.Id, chapter.SourceUrl, chapter.ParagraphIndex, chapter.Progress, now);
        ScheduleProgressSave();
        OnPropertyChanged(nameof(SelectedBook));
        OnPropertyChanged(nameof(SelectedChapter));
    }

    public async Task FlushPendingProgressAsync(CancellationToken cancellationToken = default)
    {
        _progressSaveCancellation?.Cancel();
        _progressSaveCancellation = null;
        if (_pendingProgress is not { } pending)
        {
            return;
        }

        _pendingProgress = null;
        await _repository.SaveProgressAsync(
            pending.BookId,
            pending.ChapterUrl,
            pending.ParagraphIndex,
            pending.Progress,
            pending.LastReadAt,
            cancellationToken).ConfigureAwait(true);
    }

    public async Task DeleteBookAsync(Book book, CancellationToken cancellationToken = default)
    {
        await FlushPendingProgressAsync(cancellationToken).ConfigureAwait(true);
        await _repository.DeleteBookAsync(book.Id, cancellationToken).ConfigureAwait(true);
        if (SelectedBook?.Id == book.Id)
        {
            SelectedBook = null;
            SelectedChapter = null;
            ReaderSession.Reset(null);
        }
        await ReloadAsync(cancellationToken).ConfigureAwait(true);
    }

    public void ClearError() => ErrorMessage = null;

    public async Task<BookshelfTransferImportSummary> ImportTransferAsync(
        BookshelfTransferDocument document,
        CancellationToken cancellationToken = default)
    {
        await FlushPendingProgressAsync(cancellationToken).ConfigureAwait(true);
        var summary = await BookshelfTransferImporter.ImportAsync(document, Books, _repository, cancellationToken).ConfigureAwait(true);
        await ReloadAsync(cancellationToken).ConfigureAwait(true);
        return summary;
    }

    private async Task LoadChapterIntoMemoryAsync(Chapter chapter, CancellationToken cancellationToken)
    {
        await RunBusyAsync("正在加载章节…", async () =>
        {
            var result = await _coordinator.LoadChapterContentAsync(new Uri(chapter.SourceUrl), cancellationToken).ConfigureAwait(true);
            chapter.Title = result.Title;
            chapter.ReplaceBodyText(result.BodyText);
            chapter.PreviousUrl = result.PreviousChapterUrl?.AbsoluteUri;
            chapter.NextUrl = result.NextChapterUrl?.AbsoluteUri;
            await _repository.SaveChapterAsync(SelectedBook!.Id, result, cancellationToken).ConfigureAwait(true);
            if (SelectedChapter?.SourceUrl == chapter.SourceUrl)
            {
                ReaderSession.Reset(SelectedChapter);
            }
        }, cancellationToken).ConfigureAwait(true);
    }

    private void ScheduleProgressSave()
    {
        _progressSaveCancellation?.Cancel();
        var cancellation = new CancellationTokenSource();
        _progressSaveCancellation = cancellation;
        _ = SaveProgressAfterIdleAsync(cancellation.Token);
    }

    private async Task SaveProgressAfterIdleAsync(CancellationToken cancellationToken)
    {
        try
        {
            await Task.Delay(TimeSpan.FromMilliseconds(600), cancellationToken).ConfigureAwait(true);
            await FlushPendingProgressAsync(cancellationToken).ConfigureAwait(true);
        }
        catch (OperationCanceledException)
        {
            // A new scroll sample or explicit flush superseded this write.
        }
    }

    private async Task RunBusyAsync(string message, Func<Task> operation, CancellationToken cancellationToken)
    {
        if (IsBusy)
        {
            return;
        }

        IsBusy = true;
        ErrorMessage = null;
        StatusMessage = message;
        try
        {
            await operation().ConfigureAwait(true);
        }
        catch (OperationCanceledException)
        {
        }
        catch (HtmlLoadException ex) when (ex.Kind == HtmlLoadErrorKind.VerificationRequired)
        {
            ErrorMessage = "网站要求完成浏览器验证，请在验证面板中完成后重试。";
        }
        catch (Exception ex)
        {
            ErrorMessage = ex.Message;
        }
        finally
        {
            IsBusy = false;
            StatusMessage = "";
        }
    }

    public async ValueTask DisposeAsync()
    {
        if (_disposed) return;
        _disposed = true;
        await FlushPendingProgressAsync().ConfigureAwait(true);
        _progressSaveCancellation?.Dispose();
    }

    private void OnPropertyChanged([CallerMemberName] string? propertyName = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));

    private bool SetField<T>(ref T field, T value, [CallerMemberName] string? propertyName = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value)) return false;
        field = value;
        OnPropertyChanged(propertyName);
        return true;
    }

    private sealed record PendingProgress(
        string BookId,
        string ChapterUrl,
        int ParagraphIndex,
        double Progress,
        DateTimeOffset LastReadAt);
}
