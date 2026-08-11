using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Windows.ApplicationModel.DataTransfer;
using Windows.Storage;
using WinRT.Interop;
using YYReader.Windows.Core.Models;
using YYReader.Windows.Core.Transfer;
using YYReader.Windows.Services;

namespace YYReader.Windows.Views;

public sealed partial class LibraryPage : Page
{
    private readonly Window _window;

    public LibraryPage(LibraryStore store, Window window)
    {
        Store = store;
        _window = window;
        InitializeComponent();
        Store.PropertyChanged += Store_PropertyChanged;
        Store.Books.CollectionChanged += (_, _) => RefreshView();
        RefreshView();
    }

    public LibraryStore Store { get; }

    public event EventHandler<BookRequestedEventArgs>? OpenBookRequested;

    public void RefreshView()
    {
        if (BookListView is null) return;
        EmptyState.Visibility = Store.Books.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        BusyRing.IsActive = Store.IsBusy;
        StatusText.Text = Store.ErrorMessage ?? Store.StatusMessage ?? "";
        ClearErrorButton.Visibility = Store.ErrorMessage is null ? Visibility.Collapsed : Visibility.Visible;
    }

    private async void AddUrl_Click(object sender, RoutedEventArgs e)
    {
        if (await Store.AddUrlAsync(UrlTextBox.Text))
        {
            UrlTextBox.Text = "";
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

    private async void DeleteBook_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as Button)?.Tag is not Book book) return;
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

    private void ClearError_Click(object sender, RoutedEventArgs e)
    {
        Store.ClearError();
        RefreshView();
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
