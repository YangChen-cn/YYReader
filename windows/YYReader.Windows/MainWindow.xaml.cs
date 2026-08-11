using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using YYReader.Windows.Core.Persistence;
using YYReader.Windows.Core.Services;
using YYReader.Windows.Services;
using YYReader.Windows.Views;

namespace YYReader.Windows;

public sealed partial class MainWindow : Window
{
    private readonly HttpHtmlLoader _httpLoader;
    private readonly WebView2HtmlLoader _webViewLoader;
    private readonly SqliteLibraryRepository _repository;
    private readonly LibraryStore _store;
    private readonly OfflineDownloadManager _offlineDownloadManager;
    private readonly FolderSyncService _folderSyncService;
    private readonly LibraryPage _libraryPage;
    private TaskCompletionSource<bool>? _verificationCompletion;
    private bool _closeReady;
    private bool _syncReloadPending;
    private readonly HashSet<string> _pendingCatalogRefreshSources = new(StringComparer.Ordinal);

    public MainWindow()
    {
        InitializeComponent();
        AppWindow.SetIcon(Path.Combine(AppContext.BaseDirectory, "Assets", "AppIcon.ico"));
        ExtendsContentIntoTitleBar = true;
        SetTitleBar(TitleBarDragRegion);
        AppWindow.Changed += AppWindow_Changed;
        UpdateTitleBarInsets();
        try
        {
            SystemBackdrop = new MicaBackdrop();
        }
        catch
        {
            // Older supported Windows builds fall back to the opaque WinUI background.
        }

        var databaseDirectory = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "YYReader");
        Directory.CreateDirectory(databaseDirectory);
        _repository = new SqliteLibraryRepository(Path.Combine(databaseDirectory, "library.db"));
        _httpLoader = new HttpHtmlLoader();
        _webViewLoader = new WebView2HtmlLoader(VerificationWebView, _httpLoader)
        {
            VerificationRequested = ShowVerificationAsync
        };
        var loader = new HybridHtmlLoader(_httpLoader, _webViewLoader);
        var coordinator = new NovelImportCoordinator(loader);
        _store = new LibraryStore(_repository, coordinator);
        _offlineDownloadManager = new OfflineDownloadManager(_repository, coordinator);
        _folderSyncService = new FolderSyncService(_repository, _store, DispatcherQueue, RemoteSyncAppliedAsync);
        _libraryPage = new LibraryPage(_store, _offlineDownloadManager, _folderSyncService, this);
        _libraryPage.OpenBookRequested += OpenBookRequested;
        ContentFrame.Content = _libraryPage;
        AppWindow.Closing += MainWindow_Closing;
        Activated += MainWindow_Activated;
        _ = InitializeStoreAsync();
    }

    private async Task InitializeStoreAsync()
    {
        await _store.InitializeAsync();
        await _folderSyncService.InitializeAsync();
        _libraryPage.RefreshView();
    }

    private void OpenBookRequested(object? sender, BookRequestedEventArgs args)
    {
        ContentFrame.Content = new ReaderPage(_store, _offlineDownloadManager, args.Book, this);
    }

    public void ShowLibrary()
    {
        ContentFrame.Content = _libraryPage;
        if (_syncReloadPending) _ = RefreshLibraryAfterSyncAsync();
    }

    private async Task RemoteSyncAppliedAsync(IReadOnlyList<string> catalogRefreshSources)
    {
        foreach (var source in catalogRefreshSources) _pendingCatalogRefreshSources.Add(source);
        if (ReferenceEquals(ContentFrame.Content, _libraryPage))
        {
            await _store.ReloadAsync();
            await RefreshPendingSyncedCatalogsAsync();
            _libraryPage.RefreshView();
        }
        else
        {
            // Keep the live Reader geometry and visible chapter untouched. The database result
            // becomes the restoration position only after the user leaves the Reader.
            _syncReloadPending = true;
        }
    }

    private async Task RefreshLibraryAfterSyncAsync()
    {
        _syncReloadPending = false;
        await _store.FlushPendingProgressAsync();
        await _store.ReloadAsync();
        await RefreshPendingSyncedCatalogsAsync();
        _libraryPage.RefreshView();
    }

    private async Task RefreshPendingSyncedCatalogsAsync()
    {
        foreach (var source in _pendingCatalogRefreshSources.ToArray())
        {
            if (await _store.RefreshCatalogForSourceAsync(source))
            {
                _pendingCatalogRefreshSources.Remove(source);
            }
        }
    }

    private void MainWindow_Activated(object sender, WindowActivatedEventArgs args)
    {
        if (args.WindowActivationState != WindowActivationState.Deactivated)
        {
            _folderSyncService.OnAppActivated();
        }
    }

    public void SetPageTitleBar(UIElement content, bool showBrand)
    {
        PageTitleBarContent.Content = content;
        TitleBarBrand.Visibility = showBrand ? Visibility.Visible : Visibility.Collapsed;
    }

    public void ClearPageTitleBar(UIElement content)
    {
        if (!ReferenceEquals(PageTitleBarContent.Content, content)) return;
        PageTitleBarContent.Content = null;
        TitleBarBrand.Visibility = Visibility.Visible;
    }

    private void AppWindow_Changed(Microsoft.UI.Windowing.AppWindow sender, Microsoft.UI.Windowing.AppWindowChangedEventArgs args) =>
        UpdateTitleBarInsets();

    private void UpdateTitleBarInsets()
    {
        AppTitleBar.Padding = new Thickness(
            12 + AppWindow.TitleBar.LeftInset,
            0,
            8 + AppWindow.TitleBar.RightInset,
            0);
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
            await _folderSyncService.DisposeAsync();
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
