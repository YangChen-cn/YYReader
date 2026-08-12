using Microsoft.UI.Input;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Media;
using Windows.Foundation;
using Windows.Graphics;
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
    private RectInt32[] _titleBarPassthroughRects = [];

    public MainWindow()
    {
        InitializeComponent();
        AppWindow.SetIcon(Path.Combine(AppContext.BaseDirectory, "Assets", "AppIcon.ico"));
        ExtendsContentIntoTitleBar = true;
        // Keep page toolbar controls inside the custom title bar's interactive subtree.
        // A separate full-width drag overlay can classify rapid button clicks as caption
        // double-clicks and unexpectedly maximize the window.
        SetTitleBar(AppTitleBar);
        AppTitleBar.SizeChanged += (_, _) => UpdateTitleBarPassthroughRegions();
        PageTitleBarContent.SizeChanged += (_, _) => UpdateTitleBarPassthroughRegions();
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
        _libraryPage.RefreshView();
        // Cloud-backed folders can block inside ordinary file-system calls while their
        // provider is reconnecting. The library must become usable without waiting for sync.
        _ = InitializeFolderSyncAsync();
    }

    private async Task InitializeFolderSyncAsync()
    {
        try
        {
            await _folderSyncService.InitializeAsync();
        }
        catch
        {
            // FolderSyncService reports recoverable errors through its state. Startup and
            // local reading remain available even if the selected folder is offline.
        }
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

    private async Task RemoteSyncAppliedAsync()
    {
        if (ReferenceEquals(ContentFrame.Content, _libraryPage))
        {
            await _store.ReloadAsync();
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
        _libraryPage.RefreshView();
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
        DispatcherQueue.TryEnqueue(UpdateTitleBarPassthroughRegions);
    }

    public void ClearPageTitleBar(UIElement content)
    {
        if (!ReferenceEquals(PageTitleBarContent.Content, content)) return;
        PageTitleBarContent.Content = null;
        TitleBarBrand.Visibility = Visibility.Visible;
        DispatcherQueue.TryEnqueue(UpdateTitleBarPassthroughRegions);
    }

    public void RefreshTitleBarHitTestRegions() =>
        DispatcherQueue.TryEnqueue(UpdateTitleBarPassthroughRegions);

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

    private void UpdateTitleBarPassthroughRegions()
    {
        if (AppTitleBar.XamlRoot is null || PageTitleBarContent.Content is not DependencyObject content) return;
        var scale = AppTitleBar.XamlRoot.RasterizationScale;
        var titleBarHeight = Math.Max(1, (int)Math.Ceiling(AppTitleBar.ActualHeight * scale));
        var regions = Descendants(content)
            .OfType<ButtonBase>()
            .Where(button => button.Visibility == Visibility.Visible && button.ActualWidth > 0)
            .Select(button =>
            {
                var origin = button.TransformToVisual(RootGrid).TransformPoint(new Point());
                const double guard = 8;
                var x = Math.Max(0, (int)Math.Floor((origin.X - guard) * scale));
                var right = (int)Math.Ceiling((origin.X + button.ActualWidth + guard) * scale);
                return new RectInt32(x, 0, Math.Max(1, right - x), titleBarHeight);
            })
            .OrderBy(rect => rect.X)
            .ToArray();
        if (SameRegions(_titleBarPassthroughRects, regions)) return;
        InputNonClientPointerSource.GetForWindowId(AppWindow.Id)
            .SetRegionRects(NonClientRegionKind.Passthrough, regions);
        _titleBarPassthroughRects = regions;
    }

    private static IEnumerable<DependencyObject> Descendants(DependencyObject root)
    {
        yield return root;
        for (var index = 0; index < VisualTreeHelper.GetChildrenCount(root); index++)
        {
            foreach (var descendant in Descendants(VisualTreeHelper.GetChild(root, index)))
            {
                yield return descendant;
            }
        }
    }

    private static bool SameRegions(IReadOnlyList<RectInt32> first, IReadOnlyList<RectInt32> second)
    {
        if (first.Count != second.Count) return false;
        for (var index = 0; index < first.Count; index++)
        {
            if (first[index].X != second[index].X
                || first[index].Y != second[index].Y
                || first[index].Width != second[index].Width
                || first[index].Height != second[index].Height) return false;
        }
        return true;
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
