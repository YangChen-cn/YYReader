using YYReader.Windows.Core.Models;
using YYReader.Windows.Core.Parsing;
using YYReader.Windows.Core.Persistence;

namespace YYReader.Windows.Core.Services;

public enum OfflineDownloadScope
{
    CurrentChapter,
    Next20Chapters,
    AllChapters
}

public sealed record OfflineDownloadState(
    bool IsActive = false,
    int Completed = 0,
    int Total = 0,
    int Failed = 0,
    string? CurrentChapter = null,
    bool WasCancelled = false);

public sealed class OfflineDownloadManager
{
    private readonly SqliteLibraryRepository _repository;
    private readonly Func<Uri, CancellationToken, Task<ChapterLoadResult>> _loadChapter;
    private readonly SemaphoreSlim _operationGate = new(1, 1);
    private CancellationTokenSource? _activeCancellation;

    public OfflineDownloadManager(SqliteLibraryRepository repository, NovelImportCoordinator coordinator)
        : this(repository, coordinator.LoadChapterContentAsync)
    {
    }

    public OfflineDownloadManager(
        SqliteLibraryRepository repository,
        Func<Uri, CancellationToken, Task<ChapterLoadResult>> loadChapter)
    {
        _repository = repository;
        _loadChapter = loadChapter;
    }

    public OfflineDownloadState State { get; private set; } = new();
    public event EventHandler<OfflineDownloadState>? StateChanged;

    public async Task<OfflineDownloadState> DownloadAsync(
        Book book,
        Chapter currentChapter,
        OfflineDownloadScope scope,
        CancellationToken cancellationToken = default)
    {
        Cancel();
        await _operationGate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            var linkedCancellation = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            _activeCancellation = linkedCancellation;
            var chapters = SelectChapters(book, currentChapter, scope)
                .Select(chapter => new DownloadChapter(
                    chapter.SourceUrl,
                    chapter.Title,
                    chapter.SortIndex,
                    chapter.IsAvailableOffline))
                .ToArray();
            UpdateState(new OfflineDownloadState(true, Total: chapters.Length));
            var completed = 0;
            var failed = 0;
            var cancelled = false;
            try
            {
                foreach (var chapter in chapters)
                {
                    linkedCancellation.Token.ThrowIfCancellationRequested();
                    UpdateState(State with { Completed = completed, Failed = failed, CurrentChapter = chapter.Title });
                    var succeeded = chapter.IsAvailableOffline;
                    if (!chapter.IsAvailableOffline)
                    {
                        try
                        {
                            var result = await _loadChapter(new Uri(chapter.SourceUrl), linkedCancellation.Token).ConfigureAwait(false);
                            await _repository.SaveChapterAsync(book.Id, result, chapter.SortIndex, linkedCancellation.Token).ConfigureAwait(false);
                            succeeded = true;
                        }
                        catch (OperationCanceledException)
                        {
                            throw;
                        }
                        catch
                        {
                            failed++;
                        }
                    }
                    if (succeeded) completed++;
                }
            }
            catch (OperationCanceledException)
            {
                cancelled = true;
            }
            finally
            {
                if (ReferenceEquals(_activeCancellation, linkedCancellation)) _activeCancellation = null;
                linkedCancellation.Dispose();
            }

            UpdateState(new OfflineDownloadState(false, completed, chapters.Length, failed, null, cancelled));
            return State;
        }
        finally
        {
            _operationGate.Release();
        }
    }

    public void Cancel() => _activeCancellation?.Cancel();

    public async Task ClearOfflineCacheAsync(Book book, CancellationToken cancellationToken = default)
    {
        Cancel();
        await _operationGate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            await _repository.ClearChapterBodiesAsync(book.Id, cancellationToken).ConfigureAwait(false);
        }
        finally
        {
            _operationGate.Release();
        }
    }

    private static IReadOnlyList<Chapter> SelectChapters(Book book, Chapter current, OfflineDownloadScope scope)
    {
        var ordered = book.Chapters.OrderBy(chapter => chapter.SortIndex).ToArray();
        var currentIndex = Array.FindIndex(ordered, chapter => chapter.SourceUrl == current.SourceUrl);
        if (currentIndex < 0) return [];
        return scope switch
        {
            OfflineDownloadScope.CurrentChapter => [current],
            OfflineDownloadScope.Next20Chapters => ordered.Skip(currentIndex).Take(21).ToArray(),
            _ => ordered
        };
    }

    private void UpdateState(OfflineDownloadState state)
    {
        State = state;
        StateChanged?.Invoke(this, state);
    }

    private sealed record DownloadChapter(string SourceUrl, string Title, int SortIndex, bool IsAvailableOffline);
}
