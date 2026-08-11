using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using YYReader.Windows.Core.Persistence;
using YYReader.Windows.Core.Services;
using YYReader.Windows.Services;
using YYReader.Windows.Views;

namespace YYReader.Windows;

public sealed partial class MainWindow : Window
{
    private readonly HttpHtmlLoader _httpLoader;
    private readonly WebView2HtmlLoader _webViewLoader;
    private readonly LibraryStore _store;
    private readonly LibraryPage _libraryPage;
    private TaskCompletionSource<bool>? _verificationCompletion;
    private bool _closeReady;

    public MainWindow()
    {
        InitializeComponent();
        AppWindow.SetIcon(Path.Combine(AppContext.BaseDirectory, "Assets", "AppIcon.ico"));

        var databaseDirectory = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "YYReader");
        Directory.CreateDirectory(databaseDirectory);
        var repository = new SqliteLibraryRepository(Path.Combine(databaseDirectory, "library.db"));
        _httpLoader = new HttpHtmlLoader();
        _webViewLoader = new WebView2HtmlLoader(VerificationWebView, _httpLoader)
        {
            VerificationRequested = ShowVerificationAsync
        };
        var loader = new HybridHtmlLoader(_httpLoader, _webViewLoader);
        _store = new LibraryStore(repository, new NovelImportCoordinator(loader));
        _libraryPage = new LibraryPage(_store, this);
        _libraryPage.OpenBookRequested += OpenBookRequested;
        ContentFrame.Content = _libraryPage;
        AppWindow.Closing += MainWindow_Closing;
        _ = InitializeStoreAsync();
    }

    private async Task InitializeStoreAsync()
    {
        await _store.InitializeAsync();
        _libraryPage.RefreshView();
    }

    private void OpenBookRequested(object? sender, BookRequestedEventArgs args)
    {
        ContentFrame.Content = new ReaderPage(_store, args.Book, this);
    }

    public void ShowLibrary()
    {
        ContentFrame.Content = _libraryPage;
    }

    private async Task<bool> ShowVerificationAsync(Uri url)
    {
        _verificationCompletion = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
        VerificationOverlay.Visibility = Visibility.Visible;
        VerificationWebView.Visibility = Visibility.Visible;
        return await _verificationCompletion.Task;
    }

    private void CompleteVerification_Click(object sender, RoutedEventArgs e)
    {
        VerificationOverlay.Visibility = Visibility.Collapsed;
        _verificationCompletion?.TrySetResult(true);
        _verificationCompletion = null;
    }

    private void CancelVerification_Click(object sender, RoutedEventArgs e)
    {
        VerificationOverlay.Visibility = Visibility.Collapsed;
        _verificationCompletion?.TrySetResult(false);
        _verificationCompletion = null;
    }

    private async void MainWindow_Closing(Microsoft.UI.Windowing.AppWindow sender, Microsoft.UI.Windowing.AppWindowClosingEventArgs args)
    {
        if (_closeReady)
        {
            return;
        }

        args.Cancel = true;
        try
        {
            await _store.DisposeAsync();
        }
        catch (Exception exception)
        {
            System.Diagnostics.Debug.WriteLine($"Final reader progress save failed: {exception.Message}");
        }
        finally
        {
            _closeReady = true;
            Close();
        }
    }
}
