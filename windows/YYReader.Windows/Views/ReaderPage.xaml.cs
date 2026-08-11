using Microsoft.UI.Dispatching;
using Microsoft.UI.Input;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Windows.Foundation;
using Windows.System;
using Windows.UI.Core;
using YYReader.Windows.Core.Models;
using YYReader.Windows.Core.Reading;
using YYReader.Windows.Core.Collections;
using YYReader.Windows.Core.Services;
using YYReader.Windows.Services;
using DispatcherQueueTimer = Microsoft.UI.Dispatching.DispatcherQueueTimer;

namespace YYReader.Windows.Views;

public sealed partial class ReaderPage : Page
{
    private readonly Window _window;
    private readonly OfflineDownloadManager _offlineDownloadManager;
    private readonly ReaderPreferencesStore _preferencesStore = new();
    private readonly DispatcherQueueTimer _progressTimer;
    private readonly Dictionary<int, UIElement> _realizedElements = new();
    private readonly ReaderContinuousLoadState _continuousLoadState = new();
    private CancellationTokenSource? _preferenceSaveCancellation;
    private ReaderPreferences _preferences = ReaderPreferences.Defaults;
    private ReaderThemePalette _palette = ReaderThemePalette.FromName("system");
    private bool _initialized;
    private bool _changingChapter;
    private bool _synchronizingCatalog;
    private bool _loadingNext;
    private bool _synchronizingAppearance;

    public ReaderPage(LibraryStore store, OfflineDownloadManager offlineDownloadManager, Book book, Window window)
    {
        Store = store;
        _offlineDownloadManager = offlineDownloadManager;
        Book = book;
        _window = window;
        Items = new RangeObservableCollection<ReaderItem>();
        InitializeComponent();
        _progressTimer = DispatcherQueue.CreateTimer();
        _progressTimer.Interval = TimeSpan.FromMilliseconds(280);
        _progressTimer.IsRepeating = false;
        _progressTimer.Tick += ProgressTimer_Tick;
        Loaded += ReaderPage_Loaded;
        Unloaded += ReaderPage_Unloaded;
        ActualThemeChanged += ReaderPage_ActualThemeChanged;
        _offlineDownloadManager.StateChanged += OfflineDownloadManager_StateChanged;
    }

    public LibraryStore Store { get; }
    public Book Book { get; }
    public RangeObservableCollection<ReaderItem> Items { get; }

    private async void ReaderPage_Loaded(object sender, RoutedEventArgs e)
    {
        if (ReaderToolbar.Parent is Panel parent) parent.Children.Remove(ReaderToolbar);
        if (_window is MainWindow titleWindow) titleWindow.SetPageTitleBar(ReaderToolbar, showBrand: false);
        _preferences = await _preferencesStore.LoadAsync();
        ApplyPreferences();
        Store.ConfigureNextChapterPrefetch(_preferences.PrefetchNextChapter);
        Store.SelectBook(Book);
        if (!await Store.EnsureSelectedChapterLoadedAsync())
        {
            if (_window is MainWindow mainWindow) mainWindow.ShowLibrary();
            return;
        }
        RefreshCatalogList();
        RebuildItems(ReaderRebuildPosition.RestoreProgress);
        _initialized = true;
        ReaderScrollViewer.Focus(FocusState.Programmatic);
    }

    private async void ReaderPage_Unloaded(object sender, RoutedEventArgs e)
    {
        if (_window is MainWindow mainWindow) mainWindow.ClearPageTitleBar(ReaderToolbar);
        _progressTimer.Stop();
        _offlineDownloadManager.StateChanged -= OfflineDownloadManager_StateChanged;
        CommitVisiblePosition();
        await FlushPreferencesAsync();
        await Store.FlushPendingProgressAsync();
    }

    private void RebuildItems(ReaderRebuildPosition position = ReaderRebuildPosition.PreserveAnchor)
    {
        var anchor = position == ReaderRebuildPosition.PreserveAnchor ? CaptureReaderAnchor() : null;
        Items.ReplaceAll(ReaderItemBuilder.Build(Store.ReaderSession.Entries));
        DispatcherQueue.TryEnqueue(Microsoft.UI.Dispatching.DispatcherQueuePriority.Low, () =>
        {
            ReaderRepeater.UpdateLayout();
            ReaderScrollViewer.UpdateLayout();
            switch (position)
            {
                case ReaderRebuildPosition.ChapterTop:
                    ReaderScrollViewer.ChangeView(null, 0, null, true);
                    break;
                case ReaderRebuildPosition.RestoreProgress:
                    RestorePosition();
                    break;
                case ReaderRebuildPosition.PreserveAnchor:
                    if (anchor is not null) RestoreReaderAnchor(anchor);
                    break;
            }
        });
    }

    private void ReaderRoot_SizeChanged(object sender, SizeChangedEventArgs e)
    {
        ReaderContent.Width = ReaderLayout.EffectiveContentWidth(
            _preferences.ContentWidthEm,
            _preferences.FontSize,
            e.NewSize.Width);
    }

    private void ReaderRepeater_ElementPrepared(ItemsRepeater sender, ItemsRepeaterElementPreparedEventArgs args)
    {
        var index = sender.GetElementIndex(args.Element);
        _realizedElements[index] = args.Element;
        if (index >= 0 && index < Items.Count) ApplyRealizedItemStyle(args.Element, Items[index]);
    }

    private void ReaderRepeater_ElementClearing(ItemsRepeater sender, ItemsRepeaterElementClearingEventArgs args)
    {
        var index = sender.GetElementIndex(args.Element);
        if (index >= 0) _realizedElements.Remove(index);
    }

    private void ApplyRealizedItemStyle(UIElement element, ReaderItem item)
    {
        var fontFamily = ReaderFontFamily();
        if (item.Kind == ReaderItemKind.Paragraph && element is TextBlock paragraph)
        {
            paragraph.Text = _preferences.ParagraphIndent && !string.IsNullOrWhiteSpace(item.Text)
                ? $"\u3000\u3000{item.Text}"
                : item.Text;
            paragraph.FontSize = _preferences.FontSize;
            paragraph.LineHeight = _preferences.FontSize * (1 + _preferences.LineSpacing);
            paragraph.FontFamily = fontFamily;
            paragraph.Foreground = _palette.Foreground;
            paragraph.Margin = new Thickness(0, 0, 0, _preferences.FontSize * _preferences.ParagraphSpacing);
            return;
        }

        if (item.Kind == ReaderItemKind.Header && element is StackPanel header)
        {
            var isFirst = Store.ReaderSession.Entries.FirstOrDefault()?.Chapter.SourceUrl == item.ChapterUrl;
            var headingSize = _preferences.FontSize * (isFirst ? 1.35 : 1.12);
            header.Margin = new Thickness(0, isFirst ? 32 : 24, 0, isFirst ? 20 : 10);
            if (header.Children.OfType<TextBlock>().LastOrDefault() is { } title)
            {
                title.FontSize = headingSize;
                title.FontFamily = fontFamily;
                title.Foreground = _palette.Accent;
            }
            return;
        }

        if (item.Kind == ReaderItemKind.Footer && element is StackPanel footer
            && footer.Children.OfType<Border>().FirstOrDefault() is { } separator)
        {
            separator.Background = _palette.Separator;
            separator.Width = _preferences.ContinuousReading ? 72 : double.NaN;
            separator.HorizontalAlignment = _preferences.ContinuousReading ? HorizontalAlignment.Center : HorizontalAlignment.Stretch;
            footer.Margin = _preferences.ContinuousReading
                ? new Thickness(0, 24, 0, 12)
                : new Thickness(0, 24, 0, 34);
            if (footer.Children.OfType<Grid>().FirstOrDefault() is { } navigation)
            {
                navigation.Visibility = _preferences.ContinuousReading ? Visibility.Collapsed : Visibility.Visible;
            }
        }
    }

    private void ReapplyRealizedItemStyles()
    {
        foreach (var (index, element) in _realizedElements.ToArray())
        {
            if (index >= 0 && index < Items.Count)
            {
                ApplyRealizedItemStyle(element, Items[index]);
            }
        }
    }

    private void ReaderScrollViewer_ViewChanged(object sender, ScrollViewerViewChangedEventArgs e)
    {
        _progressTimer.Stop();
        _progressTimer.Start();
    }

    private async void ProgressTimer_Tick(DispatcherQueueTimer sender, object args)
    {
        CommitVisiblePosition();
        if (_preferences.ContinuousReading
            && !_loadingNext
            && IsNearEndOfLoadedEntries())
        {
            await LoadNextContinuousChapterAsync(false);
        }
    }

    private void CommitVisiblePosition()
    {
        var visible = FindVisibleParagraph();
        if (visible is null) return;
        Store.UpdateVisibleReaderPosition(visible.ChapterUrl, visible.ParagraphIndex, visible.ParagraphCount);
        ProgressText.Text = $"{Store.SelectedChapter?.Progress:P0}　{Store.SelectedChapter?.Title}";
        ToolbarChapterTitle.Text = Store.SelectedChapter?.Title ?? "";
    }

    private ReaderItem? FindVisibleParagraph()
    {
        ReaderItem? best = null;
        var bestTop = double.MaxValue;
        foreach (var (index, element) in _realizedElements.ToArray())
        {
            if (index < 0 || index >= Items.Count || Items[index] is not { IsParagraph: true } item || element is not FrameworkElement frameworkElement)
            {
                continue;
            }

            var top = frameworkElement.TransformToVisual(ReaderScrollViewer).TransformPoint(new Point(0, 0)).Y;
            var bottom = top + frameworkElement.ActualHeight;
            if (bottom < 0 || top > ReaderScrollViewer.ActualHeight) continue;
            var candidateTop = top >= 0 ? top : 0;
            if (candidateTop < bestTop)
            {
                best = item;
                bestTop = candidateTop;
            }
        }
        return best;
    }

    private bool IsNearEndOfLoadedEntries()
    {
        if (Store.ReaderSession.Entries.Count == 0)
        {
            return false;
        }

        return ReaderPageScroll.ShouldLoadNext(
            ReaderScrollViewer.VerticalOffset,
            ReaderScrollViewer.ScrollableHeight,
            ReaderScrollViewer.ActualHeight);
    }

    private void RestorePosition()
    {
        var chapter = Store.SelectedChapter;
        if (chapter is null) return;
        var restoredIndex = ReaderPosition.RestoreParagraphIndex(
            chapter.ParagraphIndex,
            chapter.Progress,
            chapter.Paragraphs.Count);
        var itemIndex = -1;
        for (var index = 0; index < Items.Count; index++)
        {
            if (Items[index] is { IsParagraph: true } item
                && item.ChapterUrl == chapter.SourceUrl
                && item.ParagraphIndex == restoredIndex)
            {
                itemIndex = index;
                break;
            }
        }

        if (itemIndex >= 0)
        {
            var element = ReaderRepeater.GetOrCreateElement(itemIndex);
            element.StartBringIntoView(new BringIntoViewOptions
            {
                AnimationDesired = false,
                VerticalAlignmentRatio = 0
            });
            return;
        }

        var progress = ReaderPosition.ProgressForParagraph(restoredIndex, chapter.Paragraphs.Count);
        ReaderScrollViewer.ChangeView(null, ReaderScrollViewer.ScrollableHeight * progress, null, true);
    }

    private ReaderAnchor? CaptureReaderAnchor()
    {
        var visible = FindVisibleParagraph();
        if (visible is null) return null;
        var itemIndex = Items.IndexOf(visible);
        if (!_realizedElements.TryGetValue(itemIndex, out var element) || element is not FrameworkElement frameworkElement)
        {
            return new ReaderAnchor(visible.ChapterUrl, visible.ParagraphIndex);
        }

        var top = frameworkElement.TransformToVisual(ReaderScrollViewer).TransformPoint(new Point(0, 0)).Y;
        var relativeOffset = ReaderScrollViewer.ActualHeight <= 0 ? 0 : Math.Clamp(top / ReaderScrollViewer.ActualHeight, 0, 1);
        return new ReaderAnchor(visible.ChapterUrl, visible.ParagraphIndex, relativeOffset);
    }

    private void RestoreReaderAnchor(ReaderAnchor anchor)
    {
        var paragraphCount = Items.Count(item => item.IsParagraph && item.ChapterUrl == anchor.ChapterUrl);
        var normalized = anchor.Normalized(paragraphCount);
        for (var index = 0; index < Items.Count; index++)
        {
            if (Items[index] is not { IsParagraph: true } item
                || item.ChapterUrl != normalized.ChapterUrl
                || item.ParagraphIndex != normalized.ParagraphIndex)
            {
                continue;
            }

            ReaderRepeater.GetOrCreateElement(index).StartBringIntoView(new BringIntoViewOptions
            {
                AnimationDesired = false,
                VerticalAlignmentRatio = normalized.ViewportRelativeOffset
            });
            return;
        }
    }

    private async Task LoadNextContinuousChapterAsync(bool explicitRetry)
    {
        var lastLoadedUrl = Store.ReaderSession.Entries.LastOrDefault()?.Chapter.SourceUrl;
        if (!_continuousLoadState.TryBegin(lastLoadedUrl, DateTimeOffset.UtcNow, explicitRetry)) return;
        _loadingNext = true;
        SetNavigationEnabled(false);
        ShowContinuationLoading();
        try
        {
            var before = Store.ReaderSession.Entries.Count;
            var next = await Store.PrepareNextChapterAsync();
            if (next is not null && Store.ReaderSession.Entries.Count > before)
            {
                var stableOffset = ReaderScrollViewer.VerticalOffset;
                Items.AddRange(ReaderItemBuilder.BuildEntry(Store.ReaderSession.Entries[^1]));
                RefreshCatalogList();
                HideContinuationBoundary();
                DispatcherQueue.TryEnqueue(Microsoft.UI.Dispatching.DispatcherQueuePriority.Low, () =>
                {
                    ReaderRepeater.UpdateLayout();
                    ReaderScrollViewer.ChangeView(null, stableOffset, null, true);
                });
                return;
            }

            if (string.IsNullOrWhiteSpace(Store.ErrorMessage))
            {
                ShowContinuationMessage("已到最新章节", false);
                return;
            }

            _continuousLoadState.MarkFailed(DateTimeOffset.UtcNow);
            ShowContinuationMessage("下一章加载失败", true);
        }
        finally
        {
            _loadingNext = false;
            SetNavigationEnabled(true);
        }
    }

    private async void ContinuationRetry_Click(object sender, RoutedEventArgs e)
    {
        await LoadNextContinuousChapterAsync(true);
    }

    private void ShowContinuationLoading()
    {
        ContinuationBoundary.Visibility = Visibility.Visible;
        ContinuationProgress.IsActive = true;
        ContinuationProgress.Visibility = Visibility.Visible;
        ContinuationMessage.Text = "正在准备下一章…";
        ContinuationRetryButton.Visibility = Visibility.Collapsed;
    }

    private void ShowContinuationMessage(string message, bool canRetry)
    {
        ContinuationBoundary.Visibility = Visibility.Visible;
        ContinuationProgress.IsActive = false;
        ContinuationProgress.Visibility = Visibility.Collapsed;
        ContinuationMessage.Text = message;
        ContinuationRetryButton.Visibility = canRetry ? Visibility.Visible : Visibility.Collapsed;
    }

    private void HideContinuationBoundary()
    {
        ContinuationProgress.IsActive = false;
        ContinuationBoundary.Visibility = Visibility.Collapsed;
    }

    private async void CatalogList_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (!_initialized || _changingChapter || _synchronizingCatalog || CatalogList.SelectedItem is not Chapter chapter) return;
        _changingChapter = true;
        SetNavigationEnabled(false);
        try
        {
            _continuousLoadState.Reset();
            var selected = await Store.SelectChapterAsync(chapter);
            if (!selected)
            {
                RefreshCatalogList();
                await ShowChapterLoadFailureAsync();
                return;
            }
            RebuildItems(ReaderRebuildPosition.ChapterTop);
            CatalogSplitView.IsPaneOpen = false;
        }
        finally
        {
            _changingChapter = false;
            SetNavigationEnabled(true);
        }
    }

    private async Task NavigateChapterAsync(int offset)
    {
        if (_changingChapter || _loadingNext)
        {
            return;
        }

        _changingChapter = true;
        SetNavigationEnabled(false);
        try
        {
            _continuousLoadState.Reset();
            var chapter = await Store.NavigateChapterAsync(offset);
            if (chapter is null)
            {
                RefreshCatalogList();
                await ShowChapterLoadFailureAsync();
                return;
            }
            RefreshCatalogList();
            RebuildItems(ReaderRebuildPosition.ChapterTop);
        }
        finally
        {
            _changingChapter = false;
            SetNavigationEnabled(true);
        }
    }

    private async void PreviousChapter_Click(object sender, RoutedEventArgs e) => await NavigateChapterAsync(-1);

    private async void NextChapter_Click(object sender, RoutedEventArgs e) => await NavigateChapterAsync(1);

    private async void ReaderFooterPrevious_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as Button)?.Tag is Chapter chapter) await NavigateFromChapterAsync(chapter, -1);
    }

    private async void ReaderFooterNext_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as Button)?.Tag is Chapter chapter) await NavigateFromChapterAsync(chapter, 1);
    }

    private async Task NavigateFromChapterAsync(Chapter chapter, int offset)
    {
        if (_changingChapter || _loadingNext) return;
        _changingChapter = true;
        SetNavigationEnabled(false);
        try
        {
            var target = await Store.NavigateFromChapterAsync(chapter, offset);
            if (target is null)
            {
                await ShowChapterLoadFailureAsync();
                return;
            }
            RefreshCatalogList();
            RebuildItems(ReaderRebuildPosition.ChapterTop);
        }
        finally
        {
            _changingChapter = false;
            SetNavigationEnabled(true);
        }
    }

    private void RefreshCatalogList()
    {
        _synchronizingCatalog = true;
        CatalogList.SelectionChanged -= CatalogList_SelectionChanged;
        try
        {
            IEnumerable<Chapter> chapters = Store.SelectedBook is { } book
                ? book.Chapters.OrderBy(chapter => chapter.SortIndex)
                : Enumerable.Empty<Chapter>();
            if (!string.IsNullOrWhiteSpace(CatalogSearchBox.Text))
            {
                chapters = chapters.Where(chapter => chapter.Title.Contains(CatalogSearchBox.Text, StringComparison.CurrentCultureIgnoreCase));
            }
            var visibleChapters = chapters.ToArray();
            CatalogList.ItemsSource = visibleChapters;
            CatalogList.SelectedItem = visibleChapters.FirstOrDefault(chapter => chapter.SourceUrl == Store.SelectedChapter?.SourceUrl);
        }
        finally
        {
            CatalogList.SelectionChanged += CatalogList_SelectionChanged;
            _synchronizingCatalog = false;
        }
        ToolbarChapterTitle.Text = Store.SelectedChapter?.Title ?? "";
        if (CatalogSplitView.IsPaneOpen && CatalogList.SelectedItem is not null)
        {
            var selected = CatalogList.SelectedItem;
            CatalogList.ScrollIntoView(selected, ScrollIntoViewAlignment.Default);
            DispatcherQueue.TryEnqueue(Microsoft.UI.Dispatching.DispatcherQueuePriority.Low, () =>
            {
                if (CatalogList.ContainerFromItem(selected) is ListViewItem container)
                {
                    container.StartBringIntoView(new BringIntoViewOptions
                    {
                        AnimationDesired = false,
                        VerticalAlignmentRatio = 0.5
                    });
                }
            });
        }
    }

    private void ReaderScrollViewer_KeyDown(object sender, KeyRoutedEventArgs e)
    {
        var distance = e.Key switch
        {
            VirtualKey.Up => -ReaderPageScroll.SmallStep,
            VirtualKey.Down => ReaderPageScroll.SmallStep,
            VirtualKey.Left or VirtualKey.PageUp => -ReaderPageScroll.PageDistance(ReaderScrollViewer.ActualHeight),
            VirtualKey.Right or VirtualKey.PageDown => ReaderPageScroll.PageDistance(ReaderScrollViewer.ActualHeight),
            VirtualKey.Space => IsShiftDown() ? -ReaderPageScroll.PageDistance(ReaderScrollViewer.ActualHeight) : ReaderPageScroll.PageDistance(ReaderScrollViewer.ActualHeight),
            _ => double.NaN
        };

        if (e.Key == VirtualKey.Home)
        {
            ReaderScrollViewer.ChangeView(null, 0, null, true);
            e.Handled = true;
            return;
        }
        if (e.Key == VirtualKey.End)
        {
            ReaderScrollViewer.ChangeView(null, ReaderScrollViewer.ScrollableHeight, null, true);
            e.Handled = true;
            return;
        }
        if (double.IsNaN(distance)) return;

        var destination = ReaderPageScroll.DestinationY(
            ReaderScrollViewer.VerticalOffset,
            ReaderScrollViewer.ActualHeight,
            ReaderScrollViewer.ExtentHeight,
            distance);
        ReaderScrollViewer.ChangeView(null, destination, null, true);
        e.Handled = true;
    }

    private static bool IsShiftDown() =>
        (InputKeyboardSource.GetKeyStateForCurrentThread(VirtualKey.Shift) & CoreVirtualKeyStates.Down) != 0;

    private static bool IsControlDown() =>
        (InputKeyboardSource.GetKeyStateForCurrentThread(VirtualKey.Control) & CoreVirtualKeyStates.Down) != 0;

    private void ReaderPage_KeyDown(object sender, KeyRoutedEventArgs e)
    {
        if (e.Key == VirtualKey.Escape && CatalogSplitView.IsPaneOpen)
        {
            CatalogSplitView.IsPaneOpen = false;
            e.Handled = true;
        }
        else if (e.Key == VirtualKey.F && IsControlDown())
        {
            OpenCatalog(focusSearch: true);
            e.Handled = true;
        }
        else if (e.Key == VirtualKey.R && IsControlDown())
        {
            _ = RefreshCatalogAsync();
            e.Handled = true;
        }
    }

    private void Catalog_Click(object sender, RoutedEventArgs e) => OpenCatalog(focusSearch: false);

    private void OpenCatalog(bool focusSearch)
    {
        CatalogSplitView.IsPaneOpen = true;
        RefreshCatalogList();
        if (focusSearch) DispatcherQueue.TryEnqueue(() => CatalogSearchBox.Focus(FocusState.Programmatic));
    }

    private void CloseCatalog_Click(object sender, RoutedEventArgs e) => CatalogSplitView.IsPaneOpen = false;

    private void CatalogSearchBox_TextChanged(object sender, TextChangedEventArgs e) => RefreshCatalogList();

    private async void RefreshCatalog_Click(object sender, RoutedEventArgs e) => await RefreshCatalogAsync();

    private async Task RefreshCatalogAsync()
    {
        CatalogList.IsEnabled = false;
        CatalogProgress.IsActive = true;
        CatalogCancelButton.Visibility = Visibility.Visible;
        CatalogStatusText.Text = "正在刷新完整目录…";
        try
        {
            if (await Store.RefreshSelectedCatalogAsync())
            {
                RefreshCatalogList();
                _continuousLoadState.Reset();
                Store.RearmSelectedChapterPrefetch();
                HideContinuationBoundary();
                CatalogStatusText.Text = $"已更新，共 {Store.SelectedBook?.Chapters.Count ?? 0} 章";
            }
            else
            {
                CatalogStatusText.Text = Store.ErrorMessage ?? "目录刷新已取消";
            }
        }
        finally
        {
            CatalogList.IsEnabled = true;
            CatalogProgress.IsActive = false;
            CatalogCancelButton.Visibility = Visibility.Collapsed;
        }
    }

    private void CancelCatalogRefresh_Click(object sender, RoutedEventArgs e) => Store.CancelCatalogRefresh();

    private async void DownloadCurrentChapter_Click(object sender, RoutedEventArgs e) =>
        await StartOfflineDownloadAsync(OfflineDownloadScope.CurrentChapter);

    private async void DownloadNext20_Click(object sender, RoutedEventArgs e) =>
        await StartOfflineDownloadAsync(OfflineDownloadScope.Next20Chapters);

    private async void DownloadAll_Click(object sender, RoutedEventArgs e) =>
        await StartOfflineDownloadAsync(OfflineDownloadScope.AllChapters);

    private async Task StartOfflineDownloadAsync(OfflineDownloadScope scope)
    {
        if (Store.SelectedBook is not { } book || Store.SelectedChapter is not { } chapter) return;
        await _offlineDownloadManager.DownloadAsync(book, chapter, scope);
        await Store.RefreshOfflineMetadataAsync(book.Id);
    }

    private void CancelDownload_Click(object sender, RoutedEventArgs e) => _offlineDownloadManager.Cancel();

    private async void ClearOfflineCache_Click(object sender, RoutedEventArgs e)
    {
        if (Store.SelectedBook is not { } book) return;
        var dialog = new ContentDialog
        {
            Title = "删除离线缓存？",
            Content = "书籍、目录和阅读进度会保留；已下载正文将被删除。",
            PrimaryButtonText = "删除缓存",
            CloseButtonText = "取消",
            DefaultButton = ContentDialogButton.Close,
            XamlRoot = XamlRoot
        };
        if (await dialog.ShowAsync() == ContentDialogResult.Primary)
        {
            await _offlineDownloadManager.ClearOfflineCacheAsync(book);
            await Store.RefreshOfflineMetadataAsync(book.Id);
        }
    }

    private void OfflineDownloadManager_StateChanged(object? sender, OfflineDownloadState state)
    {
        DispatcherQueue.TryEnqueue(() =>
        {
            var shouldRemainVisible = state.IsActive || state.Failed > 0 || state.WasCancelled;
            DownloadStatusButton.Visibility = shouldRemainVisible ? Visibility.Visible : Visibility.Collapsed;
            DownloadStatusIcon.Glyph = state.Failed > 0 ? "\uE7BA" : state.WasCancelled ? "\uE711" : "\uE896";
            DownloadStatusText.Text = state.IsActive
                ? $"{state.CurrentChapter}\n已完成 {state.Completed} / {state.Total}" + (state.Failed > 0 ? $"，失败 {state.Failed}" : "")
                : state.WasCancelled
                    ? $"下载已取消；已完成并保留 {state.Completed} 章。"
                    : state.Failed > 0
                        ? $"下载完成 {state.Completed} 章，失败 {state.Failed} 章。"
                        : "";
            DownloadProgressBar.Value = state.Total <= 0 ? 0 : (double)(state.Completed + state.Failed) / state.Total;
        });
    }

    private void AppearanceFlyout_Opened(object sender, object e)
    {
        _synchronizingAppearance = true;
        try
        {
            AppearanceFontOptions.SelectedIndex = _preferences.FontFamily switch { "system" => 1, "kaiti" => 2, _ => 0 };
            AppearanceLineOptions.SelectedIndex = OptionIndex(SpacingName(_preferences.LineSpacing, 0.34, 0.49));
            AppearanceParagraphOptions.SelectedIndex = OptionIndex(SpacingName(_preferences.ParagraphSpacing, 0.50, 0.70));
            AppearanceWidthOptions.SelectedIndex = OptionIndex(WidthName(_preferences.ContentWidthEm));
            AppearanceIndentToggle.IsOn = _preferences.ParagraphIndent;
            AppearanceContinuousToggle.IsOn = _preferences.ContinuousReading;
            AppearancePrefetchToggle.IsOn = _preferences.PrefetchNextChapter;
            AppearanceFontSizeText.Text = $"{_preferences.FontSize:0} pt";
            UpdateThemeSelection();
        }
        finally
        {
            _synchronizingAppearance = false;
        }
    }

    private void DecreaseFont_Click(object sender, RoutedEventArgs e) => ChangeFontSize(-1);

    private void IncreaseFont_Click(object sender, RoutedEventArgs e) => ChangeFontSize(1);

    private void ChangeFontSize(double amount)
    {
        _preferences = (_preferences with { FontSize = _preferences.FontSize + amount }).Normalized();
        AppearanceFontSizeText.Text = $"{_preferences.FontSize:0} pt";
        ApplyAppearanceChange();
    }

    private void AppearanceControl_Changed(object sender, RoutedEventArgs e)
    {
        if (_synchronizingAppearance) return;
        _preferences = (_preferences with
        {
            FontFamily = AppearanceFontOptions.SelectedIndex switch { 1 => "system", 2 => "kaiti", _ => "serif" },
            LineSpacing = SpacingValue(OptionName(AppearanceLineOptions.SelectedIndex), 0.28, 0.40, 0.58),
            ParagraphSpacing = SpacingValue(OptionName(AppearanceParagraphOptions.SelectedIndex), 0.40, 0.60, 0.82),
            ContentWidthEm = WidthValue(WidthOptionName(AppearanceWidthOptions.SelectedIndex)),
            ParagraphIndent = AppearanceIndentToggle.IsOn,
            ContinuousReading = AppearanceContinuousToggle.IsOn,
            PrefetchNextChapter = AppearancePrefetchToggle.IsOn
        }).Normalized();
        ApplyAppearanceChange();
    }

    private void AppearanceTheme_Click(object sender, RoutedEventArgs e)
    {
        if (_synchronizingAppearance || sender is not Button { Tag: string theme }) return;
        _preferences = (_preferences with { Theme = theme }).Normalized();
        ApplyAppearanceChange();
        UpdateThemeSelection();
    }

    private void UpdateThemeSelection()
    {
        foreach (var button in AppearanceThemePanel.Children.OfType<Button>())
        {
            var selected = string.Equals(button.Tag as string, _preferences.Theme, StringComparison.Ordinal);
            button.BorderThickness = new Thickness(selected ? 2 : 1);
            button.BorderBrush = selected ? _palette.Accent : _palette.Separator;
            button.Opacity = selected ? 1 : 0.78;
        }
    }

    private void ApplyAppearanceChange()
    {
        var anchor = CaptureReaderAnchor();
        _continuousLoadState.Reset();
        Store.ConfigureNextChapterPrefetch(_preferences.PrefetchNextChapter);
        ApplyPreferences();
        ReapplyRealizedItemStyles();
        if (anchor is not null)
        {
            DispatcherQueue.TryEnqueue(Microsoft.UI.Dispatching.DispatcherQueuePriority.Low, () =>
            {
                ReaderRepeater.UpdateLayout();
                ReaderScrollViewer.UpdateLayout();
                RestoreReaderAnchor(anchor);
            });
        }
        SchedulePreferencesSave();
    }

    private void SchedulePreferencesSave()
    {
        _preferenceSaveCancellation?.Cancel();
        _preferenceSaveCancellation?.Dispose();
        var cancellation = new CancellationTokenSource();
        _preferenceSaveCancellation = cancellation;
        _ = SavePreferencesAfterIdleAsync(cancellation);
    }

    private async Task SavePreferencesAfterIdleAsync(CancellationTokenSource scheduledSave)
    {
        try
        {
            await Task.Delay(500, scheduledSave.Token);
            if (ReferenceEquals(_preferenceSaveCancellation, scheduledSave))
            {
                _preferenceSaveCancellation = null;
                await _preferencesStore.SaveAsync(_preferences, scheduledSave.Token);
            }
        }
        catch (OperationCanceledException)
        {
        }
        finally
        {
            scheduledSave.Dispose();
        }
    }

    private async Task FlushPreferencesAsync()
    {
        var scheduledSave = _preferenceSaveCancellation;
        _preferenceSaveCancellation = null;
        scheduledSave?.Cancel();
        scheduledSave?.Dispose();
        await _preferencesStore.SaveAsync(_preferences);
    }

    private async void More_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new ContentDialog
        {
            Title = "阅读",
            Content = new TextBlock { Text = "正文始终由 WinUI 原生文本控件渲染。网页验证只在需要时使用 WebView2。", TextWrapping = TextWrapping.Wrap },
            CloseButtonText = "知道了",
            XamlRoot = XamlRoot
        };
        await dialog.ShowAsync();
    }

    private Task ShowChapterLoadFailureAsync()
    {
        if (string.IsNullOrWhiteSpace(Store.ErrorMessage))
        {
            return Task.CompletedTask;
        }
        ReaderInfoBar.Title = "章节加载失败";
        ReaderInfoBar.Message = Store.ErrorMessage;
        ReaderInfoBar.Severity = InfoBarSeverity.Error;
        ReaderInfoBar.IsOpen = true;
        return Task.CompletedTask;
    }

    private void SetNavigationEnabled(bool isEnabled)
    {
        CatalogList.IsEnabled = isEnabled;
    }

    private void Back_Click(object sender, RoutedEventArgs e)
    {
        if (_window is MainWindow mainWindow)
        {
            mainWindow.ShowLibrary();
        }
    }

    private void ApplyPreferences()
    {
        _preferences = _preferences.Normalized();
        var systemTheme = ActualTheme == ElementTheme.Dark ? ElementTheme.Dark : ElementTheme.Light;
        _palette = ReaderThemePalette.FromName(_preferences.Theme, systemTheme);
        ReaderRoot.RequestedTheme = _palette.ElementTheme;
        ReaderToolbar.RequestedTheme = _palette.ElementTheme;
        ReaderRoot.Background = _palette.Background;
        ReaderScrollViewer.Background = _palette.Background;
        ReaderContent.Width = ReaderLayout.EffectiveContentWidth(_preferences.ContentWidthEm, _preferences.FontSize, ActualWidth);
        ProgressText.Foreground = _palette.SecondaryForeground;
        ContinuationBoundary.Background = _palette.Background;
        ContinuationBoundary.BorderBrush = _palette.Separator;
        ContinuationBoundary.BorderThickness = new Thickness(1);
        ContinuationMessage.Foreground = _palette.SecondaryForeground;
        CatalogPane.Background = _palette.Background;
        CatalogPane.BorderBrush = _palette.Separator;
    }

    private void ReaderPage_ActualThemeChanged(FrameworkElement sender, object args)
    {
        if (_preferences.Theme != "system") return;
        ApplyPreferences();
        ReapplyRealizedItemStyles();
    }

    private FontFamily ReaderFontFamily() => _preferences.FontFamily switch
    {
        "system" => new FontFamily("Microsoft YaHei UI, Noto Sans SC, Segoe UI Variable Text"),
        "rounded" => new FontFamily("Microsoft YaHei UI, Noto Sans SC, Segoe UI Variable Text"),
        "kaiti" => new FontFamily("KaiTi, Microsoft YaHei UI, Noto Sans SC"),
        _ => new FontFamily("Noto Serif SC, Microsoft YaHei UI, DengXian")
    };

    private static string WidthName(double value) => value < 43 ? "narrow" : value > 53 ? "wide" : "comfortable";
    private static double WidthValue(string? value) => value switch
    {
        "narrow" => 38,
        "wide" => 58,
        _ => 48
    };

    private static string SpacingName(double value, double compactThreshold, double looseThreshold) =>
        value < compactThreshold ? "compact" : value > looseThreshold ? "loose" : "comfortable";

    private static double SpacingValue(string value, double compact, double comfortable, double loose) => value switch
    {
        "compact" => compact,
        "loose" => loose,
        _ => comfortable
    };

    private static int OptionIndex(string name) => name switch
    {
        "compact" or "narrow" => 0,
        "loose" or "wide" => 2,
        _ => 1
    };

    private static string OptionName(int index) => index switch
    {
        0 => "compact",
        2 => "loose",
        _ => "comfortable"
    };

    private static string WidthOptionName(int index) => index switch
    {
        0 => "narrow",
        2 => "wide",
        _ => "comfortable"
    };

    private enum ReaderRebuildPosition
    {
        PreserveAnchor,
        ChapterTop,
        RestoreProgress
    }
}
