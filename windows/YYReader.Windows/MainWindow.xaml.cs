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

    public MainWindow()
    {
        InitializeComponent();

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
        RootNavigation.SelectionChanged += RootNavigation_SelectionChanged;
        Closed += MainWindow_Closed;
        _ = InitializeStoreAsync();
    }

    private async Task InitializeStoreAsync()
    {
        await _store.InitializeAsync();
        _libraryPage.RefreshView();
    }

    private void RootNavigation_SelectionChanged(NavigationView sender, NavigationViewSelectionChangedEventArgs args)
    {
        if (args.SelectedItem is NavigationViewItem { Tag: "library" })
        {
            ContentFrame.Content = _libraryPage;
        }
    }

    private void OpenBookRequested(object? sender, BookRequestedEventArgs args)
    {
        ContentFrame.Content = new ReaderPage(_store, args.Book, this);
    }

    public void ShowLibrary()
    {
        ContentFrame.Content = _libraryPage;
        RootNavigation.SelectedItem = RootNavigation.MenuItems[0];
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

    private async void MainWindow_Closed(object sender, WindowEventArgs args)
    {
        await _store.DisposeAsync();
    }
}
