using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Windows.ApplicationModel.DataTransfer;
using Windows.Storage;
using WinRT.Interop;
using YYReader.Windows.Core.Models;
using YYReader.Windows.Core.Services;
using YYReader.Windows.Core.Transfer;
using YYReader.Windows.Services;

namespace YYReader.Windows.Views;

public sealed partial class LibraryPage : Page
{
    private readonly Window _window;
    private readonly OfflineDownloadManager _offlineDownloadManager;
    private CancellationTokenSource? _downloadNoticeCancellation;
    private bool _isSubscribed;

    public LibraryPage(LibraryStore store, OfflineDownloadManager offlineDownloadManager, Window window)
    {
        Store = store;
        _offlineDownloadManager = offlineDownloadManager;
        _window = window;
        InitializeComponent();
        Loaded += LibraryPage_Loaded;
        Unloaded += LibraryPage_Unloaded;
    }

    public LibraryStore Store { get; }

    public event EventHandler<BookRequestedEventArgs>? OpenBookRequested;

    public void RefreshView()
    {
        if (BookListView is null) return;
        EmptyState.Visibility = Store.Books.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        var featured = Store.Books.OrderByDescending(book => book.LastReadAt ?? book.UpdatedAt).FirstOrDefault();
        FeaturedBookPanel.Visibility = featured is null ? Visibility.Collapsed : Visibility.Visible;
        FeaturedTitle.Text = featured?.Title ?? "";
        FeaturedMonogram.Text = featured?.Monogram ?? "阅";
        FeaturedChapter.Text = featured?.CurrentChapterTitle ?? "";
        FeaturedProgress.Text = featured is null ? "" : $"{featured.ProgressDisplay} · {featured.LastReadDisplay}";
        FeaturedOpenButton.Tag = featured;
        StatusInfoBar.IsOpen = Store.IsBusy || !string.IsNullOrWhiteSpace(Store.ErrorMessage) || !string.IsNullOrWhiteSpace(Store.StatusMessage);
        StatusInfoBar.Message = Store.ErrorMessage ?? Store.StatusMessage ?? "";
        StatusInfoBar.Severity = Store.ErrorMessage is null ? InfoBarSeverity.Informational : InfoBarSeverity.Error;
    }

    private void LibraryPage_Loaded(object sender, RoutedEventArgs e)
    {
        if (LibraryToolbar.Parent is Panel parent) parent.Children.Remove(LibraryToolbar);
        if (_window is MainWindow mainWindow) mainWindow.SetPageTitleBar(LibraryToolbar, showBrand: true);
        if (!_isSubscribed)
        {
            Store.PropertyChanged += Store_PropertyChanged;
            Store.Books.CollectionChanged += Books_CollectionChanged;
            _offlineDownloadManager.StateChanged += OfflineDownloadManager_StateChanged;
            _isSubscribed = true;
        }
        RefreshBookRows();
        RefreshView();
        ApplyOfflineDownloadState(_offlineDownloadManager.State);
    }

    private void LibraryPage_Unloaded(object sender, RoutedEventArgs e)
    {
        if (_window is MainWindow mainWindow) mainWindow.ClearPageTitleBar(LibraryToolbar);
        if (!_isSubscribed) return;
        Store.PropertyChanged -= Store_PropertyChanged;
        Store.Books.CollectionChanged -= Books_CollectionChanged;
        _offlineDownloadManager.StateChanged -= OfflineDownloadManager_StateChanged;
        _isSubscribed = false;
        _downloadNoticeCancellation?.Cancel();
        _downloadNoticeCancellation?.Dispose();
        _downloadNoticeCancellation = null;
    }

    private void Books_CollectionChanged(object? sender, System.Collections.Specialized.NotifyCollectionChangedEventArgs e)
    {
        RefreshBookRows();
        RefreshView();
    }

    private void RefreshBookRows()
    {
        BookListView.ItemsSource = null;
        BookListView.ItemsSource = Store.Books;
    }

    private async void AddUrl_Click(object sender, RoutedEventArgs e)
    {
        if (await Store.AddUrlAsync(UrlTextBox.Text))
        {
            UrlTextBox.Text = "";
            AddBookFlyout.Hide();
        }
        RefreshView();
    }

    private async void UrlTextBox_KeyDown(object sender, KeyRoutedEventArgs e)
    {
        if (e.Key == global::Windows.System.VirtualKey.Enter)
        {
            e.Handled = true;
            if (await Store.AddUrlAsync(UrlTextBox.Text))
            {
                UrlTextBox.Text = "";
            }
            RefreshView();
        }
    }

    private async void ImportBookshelf_Click(object sender, RoutedEventArgs e)
    {
        var json = await ReadTransferTextAsync();
        if (!string.IsNullOrWhiteSpace(json))
        {
            await ShowTransferPreviewAsync(json);
        }
    }

    private async Task<string?> ReadTransferTextAsync()
    {
        var clipboard = Clipboard.GetContent();
        if (clipboard.Contains(StandardDataFormats.Text))
        {
            var text = await clipboard.GetTextAsync();
            if (text.Contains("yyreader-bookshelf", StringComparison.OrdinalIgnoreCase))
            {
                return text;
            }
        }

        var picker = new global::Windows.Storage.Pickers.FileOpenPicker
        {
            SuggestedStartLocation = global::Windows.Storage.Pickers.PickerLocationId.DocumentsLibrary
        };
        picker.FileTypeFilter.Add(".yyreader");
        picker.FileTypeFilter.Add(".json");
        InitializeWithWindow.Initialize(picker, WindowNative.GetWindowHandle(_window));
        var file = await picker.PickSingleFileAsync();
        return file is null ? null : await FileIO.ReadTextAsync(file);
    }

    private async Task ShowTransferPreviewAsync(string json)
    {
        BookshelfTransferDocument document;
        BookshelfTransferPreview preview;
        try
        {
            document = BookshelfTransferCodec.Decode(json);
            preview = BookshelfTransferPlanner.Preview(document, Store.Books);
        }
        catch (BookshelfTransferException ex)
        {
            await ShowMessageAsync("无法导入书架", ex.Message);
            return;
        }

        var detail = $"检测到 {preview.TotalCount} 本小说\n新书 {preview.NewCount} 本，已存在 {preview.ExistingCount} 本。"
            + (preview.InvalidCount > 0 ? $"\n数据错误 {preview.InvalidCount} 本。" : "")
            + (preview.DuplicateCount > 0 ? $"\n文件内重复 {preview.DuplicateCount} 本。" : "");
        var dialog = new ContentDialog
        {
            Title = "导入书架预览",
            Content = new TextBlock { Text = detail, TextWrapping = TextWrapping.Wrap },
            PrimaryButtonText = "导入",
            CloseButtonText = "取消",
            XamlRoot = XamlRoot
        };
        if (await dialog.ShowAsync() != ContentDialogResult.Primary)
        {
            return;
        }

        var summary = await Store.ImportTransferAsync(document);
        var result = $"成功 {summary.Succeeded} 本，跳过 {summary.Skipped} 本，失败 {summary.Failed} 本。";
        if (summary.Failures.Count > 0)
        {
            result += "\n" + string.Join("\n", summary.Failures.Select(failure => $"{failure.SourceUrl}：{failure.Message}"));
        }
        await ShowMessageAsync("书架导入完成", result);
        RefreshView();
    }

    private void BookListView_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        Store.SelectBook(BookListView.SelectedItem as Book);
    }

    private async void OpenBook_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as Button)?.Tag is not Book book) return;
        await OpenBookAsync(book);
    }

    private async void OpenBookMenu_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as MenuFlyoutItem)?.Tag is Book book) await OpenBookAsync(book);
    }

    private async Task OpenBookAsync(Book book)
    {
        Store.SelectBook(book);
        if (await Store.EnsureSelectedChapterLoadedAsync())
        {
            OpenBookRequested?.Invoke(this, new BookRequestedEventArgs(book));
        }
        else
        {
            RefreshView();
        }
    }

    private async void BookListView_DoubleTapped(object sender, DoubleTappedRoutedEventArgs e)
    {
        if (BookListView.SelectedItem is Book book) await OpenBookAsync(book);
    }

    private async void BookListView_KeyDown(object sender, KeyRoutedEventArgs e)
    {
        if (e.Key == global::Windows.System.VirtualKey.Enter && BookListView.SelectedItem is Book book)
        {
            e.Handled = true;
            await OpenBookAsync(book);
        }
    }

    private async void DeleteBook_Click(object sender, RoutedEventArgs e)
    {
        var book = sender switch
        {
            Button button => button.Tag as Book,
            MenuFlyoutItem item => item.Tag as Book,
            _ => null
        };
        if (book is null) return;
        var dialog = new ContentDialog
        {
            Title = "删除小说？",
            Content = $"将删除“{book.Title}”及其本地正文和阅读进度。",
            PrimaryButtonText = "删除",
            CloseButtonText = "取消",
            DefaultButton = ContentDialogButton.Close,
            XamlRoot = XamlRoot
        };
        if (await dialog.ShowAsync() == ContentDialogResult.Primary)
        {
            await Store.DeleteBookAsync(book);
            RefreshView();
        }
    }

    private async void RefreshBookCatalog_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as MenuFlyoutItem)?.Tag is not Book book) return;
        Store.SelectBook(book);
        await Store.RefreshSelectedCatalogAsync();
        RefreshView();
    }

    private async void DownloadAllBook_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as MenuFlyoutItem)?.Tag is not Book book || book.CurrentChapter is not { } chapter) return;
        await _offlineDownloadManager.DownloadAsync(book, chapter, OfflineDownloadScope.AllChapters);
        await Store.RefreshOfflineMetadataAsync(book.Id);
    }

    private async void ClearBookCache_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as MenuFlyoutItem)?.Tag is not Book book) return;
        await _offlineDownloadManager.ClearOfflineCacheAsync(book);
        await Store.RefreshOfflineMetadataAsync(book.Id);
        StatusInfoBar.Message = "离线正文已删除，书籍和阅读进度已保留。";
        StatusInfoBar.Severity = InfoBarSeverity.Success;
        StatusInfoBar.IsOpen = true;
    }

    private void OfflineDownloadManager_StateChanged(object? sender, OfflineDownloadState state)
    {
        DispatcherQueue.TryEnqueue(() => ApplyOfflineDownloadState(state));
    }

    private void ApplyOfflineDownloadState(OfflineDownloadState state)
    {
        _downloadNoticeCancellation?.Cancel();
        _downloadNoticeCancellation?.Dispose();
        _downloadNoticeCancellation = null;
        if (state.IsActive)
        {
            StatusInfoBar.Message = $"正在下载 {state.CurrentChapter} · {state.Completed}/{state.Total}";
            StatusInfoBar.Severity = InfoBarSeverity.Informational;
            StatusInfoBar.IsOpen = true;
            return;
        }
        if (state.Total <= 0) return;

        StatusInfoBar.Message = state.WasCancelled
            ? $"下载已取消，已保留 {state.Completed} 章。"
            : $"离线下载完成：{state.Completed} 章" + (state.Failed > 0 ? $"，失败 {state.Failed} 章" : "");
        StatusInfoBar.Severity = state.Failed > 0 ? InfoBarSeverity.Warning : InfoBarSeverity.Success;
        StatusInfoBar.IsOpen = true;
        if (state.Failed == 0)
        {
            _downloadNoticeCancellation = new CancellationTokenSource();
            _ = HideSuccessfulDownloadNoticeAsync(_downloadNoticeCancellation);
        }
    }

    private async Task HideSuccessfulDownloadNoticeAsync(CancellationTokenSource cancellation)
    {
        try
        {
            await Task.Delay(TimeSpan.FromSeconds(5), cancellation.Token);
            if (ReferenceEquals(_downloadNoticeCancellation, cancellation)
                && string.IsNullOrWhiteSpace(Store.ErrorMessage))
            {
                _downloadNoticeCancellation = null;
                StatusInfoBar.IsOpen = false;
            }
        }
        catch (OperationCanceledException)
        {
        }
        finally
        {
            cancellation.Dispose();
        }
    }

    private void LibraryPage_KeyDown(object sender, KeyRoutedEventArgs e)
    {
        if ((e.Key == global::Windows.System.VirtualKey.O || e.Key == global::Windows.System.VirtualKey.L)
            && (Microsoft.UI.Input.InputKeyboardSource.GetKeyStateForCurrentThread(global::Windows.System.VirtualKey.Control)
                & global::Windows.UI.Core.CoreVirtualKeyStates.Down) != 0)
        {
            AddBookFlyout.ShowAt(AddBookButton);
            DispatcherQueue.TryEnqueue(() => UrlTextBox.Focus(FocusState.Programmatic));
            e.Handled = true;
        }
    }

    private void StatusInfoBar_Closed(InfoBar sender, InfoBarClosedEventArgs args) => Store.ClearError();

    private string CreateBookshelfExport() =>
        BookshelfTransferCodec.Encode(BookshelfTransferExporter.FromBooks(Store.Books));

    private void CopyBookshelfExport_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            var package = new DataPackage();
            package.SetText(CreateBookshelfExport());
            Clipboard.SetContent(package);
            Clipboard.Flush();
            StatusInfoBar.Message = $"已复制 {Store.Books.Count} 本小说的书架数据。";
            StatusInfoBar.Severity = InfoBarSeverity.Success;
            StatusInfoBar.IsOpen = true;
        }
        catch (Exception exception)
        {
            StatusInfoBar.Message = $"复制书架失败：{exception.Message}";
            StatusInfoBar.Severity = InfoBarSeverity.Error;
            StatusInfoBar.IsOpen = true;
        }
    }

    private async void SaveBookshelfExport_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            var picker = new global::Windows.Storage.Pickers.FileSavePicker
            {
                SuggestedStartLocation = global::Windows.Storage.Pickers.PickerLocationId.DocumentsLibrary,
                SuggestedFileName = $"YYReader-Bookshelf-{DateTime.Now:yyyyMMdd}"
            };
            picker.FileTypeChoices.Add("YYReader 书架", [".yyreader"]);
            InitializeWithWindow.Initialize(picker, WindowNative.GetWindowHandle(_window));
            var file = await picker.PickSaveFileAsync();
            if (file is null) return;
            await FileIO.WriteTextAsync(file, CreateBookshelfExport());
            StatusInfoBar.Message = $"书架已导出到 {file.Name}";
            StatusInfoBar.Severity = InfoBarSeverity.Success;
            StatusInfoBar.IsOpen = true;
        }
        catch (Exception exception)
        {
            StatusInfoBar.Message = $"导出书架失败：{exception.Message}";
            StatusInfoBar.Severity = InfoBarSeverity.Error;
            StatusInfoBar.IsOpen = true;
        }
    }

    private async Task ShowMessageAsync(string title, string message)
    {
        var dialog = new ContentDialog
        {
            Title = title,
            Content = new ScrollViewer { Content = new TextBlock { Text = message, TextWrapping = TextWrapping.Wrap } },
            CloseButtonText = "知道了",
            XamlRoot = XamlRoot
        };
        await dialog.ShowAsync();
    }

    private void Store_PropertyChanged(object? sender, System.ComponentModel.PropertyChangedEventArgs e) => RefreshView();
}

public sealed class BookRequestedEventArgs(Book book) : EventArgs
{
    public Book Book { get; } = book;
}
