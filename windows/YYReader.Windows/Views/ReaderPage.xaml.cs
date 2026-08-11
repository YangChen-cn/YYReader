using System.Collections.ObjectModel;
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
using YYReader.Windows.Services;
using DispatcherQueueTimer = Microsoft.UI.Dispatching.DispatcherQueueTimer;

namespace YYReader.Windows.Views;

public sealed partial class ReaderPage : Page
{
    private readonly Window _window;
    private readonly ReaderPreferencesStore _preferencesStore = new();
    private readonly DispatcherQueueTimer _progressTimer;
    private readonly Dictionary<int, UIElement> _realizedElements = new();
    private readonly ReaderContinuousLoadState _continuousLoadState = new();
    private ReaderPreferences _preferences = ReaderPreferences.Defaults;
    private ReaderThemePalette _palette = ReaderThemePalette.FromName("system");
    private bool _initialized;
    private bool _changingChapter;
    private bool _synchronizingChapterPicker;
    private bool _loadingNext;

    public ReaderPage(LibraryStore store, Book book, Window window)
    {
        Store = store;
        Book = book;
        _window = window;
        Items = new ObservableCollection<ReaderItem>();
        InitializeComponent();
        _progressTimer = DispatcherQueue.CreateTimer();
        _progressTimer.Interval = TimeSpan.FromMilliseconds(280);
        _progressTimer.IsRepeating = false;
        _progressTimer.Tick += ProgressTimer_Tick;
        Loaded += ReaderPage_Loaded;
        Unloaded += ReaderPage_Unloaded;
        ActualThemeChanged += ReaderPage_ActualThemeChanged;
    }

    public LibraryStore Store { get; }
    public Book Book { get; }
    public ObservableCollection<ReaderItem> Items { get; }

    private async void ReaderPage_Loaded(object sender, RoutedEventArgs e)
    {
        _preferences = await _preferencesStore.LoadAsync();
        ApplyPreferences();
        Store.ConfigureNextChapterPrefetch(_preferences.PrefetchNextChapter);
        Store.SelectBook(Book);
        if (!await Store.EnsureSelectedChapterLoadedAsync())
        {
            if (_window is MainWindow mainWindow) mainWindow.ShowLibrary();
            return;
        }
        RefreshChapterPicker();
        RebuildItems(ReaderRebuildPosition.RestoreProgress);
        _initialized = true;
        ReaderScrollViewer.Focus(FocusState.Programmatic);
    }

    private async void ReaderPage_Unloaded(object sender, RoutedEventArgs e)
    {
        _progressTimer.Stop();
        CommitVisiblePosition();
        await Store.FlushPendingProgressAsync();
    }

    private void RebuildItems(ReaderRebuildPosition position = ReaderRebuildPosition.PreserveAnchor)
    {
        var anchor = position == ReaderRebuildPosition.PreserveAnchor ? CaptureReaderAnchor() : null;
        Items.Clear();
        var entries = Store.ReaderSession.Entries;
        for (var entryIndex = 0; entryIndex < entries.Count; entryIndex++)
        {
            AddEntryItems(entries[entryIndex], entryIndex == 0);
        }
        ReaderRepeater.ItemsSource = Items;
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

    private void AddEntryItems(ContinuousReaderSession.Entry entry, bool firstEntry)
    {
        var chapter = entry.Chapter;
        var headingSize = firstEntry ? _preferences.FontSize * 1.35 : _preferences.FontSize * 1.12;
        Items.Add(new ReaderItem
        {
            Kind = ReaderItemKind.Header,
            Text = chapter.Title,
            ChapterUrl = chapter.SourceUrl,
            FontSize = headingSize,
            LineHeight = headingSize * 1.3,
            FontFamily = ReaderFontFamily(),
            Foreground = _palette.Accent,
            Margin = new Thickness(0, firstEntry ? 32 : 24, 0, firstEntry ? 20 : 10)
        });

        var paragraphs = entry.Paragraphs;
        for (var index = 0; index < paragraphs.Count; index++)
        {
            var paragraph = _preferences.ParagraphIndent && !string.IsNullOrWhiteSpace(paragraphs[index])
                ? $"\u3000\u3000{paragraphs[index]}"
                : paragraphs[index];
            Items.Add(new ReaderItem
            {
                Kind = ReaderItemKind.Paragraph,
                Text = paragraph,
                ChapterUrl = chapter.SourceUrl,
                ParagraphIndex = index,
                ParagraphCount = paragraphs.Count,
                FontSize = _preferences.FontSize,
                LineHeight = _preferences.FontSize * (1 + _preferences.LineSpacing),
                FontFamily = ReaderFontFamily(),
                Foreground = _palette.Foreground,
                Margin = new Thickness(0, 0, 0, _preferences.FontSize * _preferences.ParagraphSpacing)
            });
        }
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
        _realizedElements[sender.GetElementIndex(args.Element)] = args.Element;
    }

    private void ReaderRepeater_ElementClearing(ItemsRepeater sender, ItemsRepeaterElementClearingEventArgs args)
    {
        var index = sender.GetElementIndex(args.Element);
        if (index >= 0) _realizedElements.Remove(index);
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
                AddEntryItems(Store.ReaderSession.Entries[^1], false);
                RefreshChapterPicker();
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

    private async void ChapterPicker_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (!_initialized || _changingChapter || _synchronizingChapterPicker || ChapterPicker.SelectedItem is not Chapter chapter) return;
        _changingChapter = true;
        SetNavigationEnabled(false);
        try
        {
            _continuousLoadState.Reset();
            var selected = await Store.SelectChapterAsync(chapter);
            if (!selected)
            {
                RefreshChapterPicker();
                await ShowChapterLoadFailureAsync();
                return;
            }
            RebuildItems(ReaderRebuildPosition.ChapterTop);
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
                RefreshChapterPicker();
                await ShowChapterLoadFailureAsync();
                return;
            }
            RefreshChapterPicker();
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

    private void RefreshChapterPicker()
    {
        _synchronizingChapterPicker = true;
        ChapterPicker.SelectionChanged -= ChapterPicker_SelectionChanged;
        try
        {
            ChapterPicker.ItemsSource = Store.SelectedBook?.Chapters.OrderBy(chapter => chapter.SortIndex).ToArray();
            ChapterPicker.SelectedItem = Store.SelectedChapter;
        }
        finally
        {
            ChapterPicker.SelectionChanged += ChapterPicker_SelectionChanged;
            _synchronizingChapterPicker = false;
        }
        ToolbarChapterTitle.Text = Store.SelectedChapter?.Title ?? "";
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

    private async void Appearance_Click(object sender, RoutedEventArgs e)
    {
        var content = new StackPanel { Spacing = 12, Width = 360 };
        var fontSlider = new Slider { Minimum = 14, Maximum = 36, StepFrequency = 1, Value = _preferences.FontSize, Header = "字号" };
        var widthBox = new ComboBox { Header = "正文宽度", ItemsSource = new[] { "narrow", "comfortable", "wide" }, SelectedItem = WidthName(_preferences.ContentWidthEm) };
        var themeBox = new ComboBox { Header = "主题", ItemsSource = new[] { "system", "light", "rose", "sepia", "mist", "sage", "dark", "midnight" }, SelectedItem = _preferences.Theme };
        var indent = new ToggleSwitch { Header = "段首缩进", IsOn = _preferences.ParagraphIndent };
        var continuous = new ToggleSwitch { Header = "连续阅读", IsOn = _preferences.ContinuousReading };
        var prefetch = new ToggleSwitch { Header = "空闲时预取下一章", IsOn = _preferences.PrefetchNextChapter };
        content.Children.Add(fontSlider);
        content.Children.Add(widthBox);
        content.Children.Add(themeBox);
        content.Children.Add(indent);
        content.Children.Add(continuous);
        content.Children.Add(prefetch);
        var dialog = new ContentDialog
        {
            Title = "阅读设置",
            Content = content,
            PrimaryButtonText = "应用",
            CloseButtonText = "取消",
            XamlRoot = XamlRoot
        };
        if (await dialog.ShowAsync() != ContentDialogResult.Primary) return;
        _preferences = _preferences with
        {
            FontSize = fontSlider.Value,
            ContentWidthEm = WidthValue(widthBox.SelectedItem as string),
            Theme = themeBox.SelectedItem as string ?? "system",
            ParagraphIndent = indent.IsOn,
            ContinuousReading = continuous.IsOn,
            PrefetchNextChapter = prefetch.IsOn
        };
        _continuousLoadState.Reset();
        await _preferencesStore.SaveAsync(_preferences);
        Store.ConfigureNextChapterPrefetch(_preferences.PrefetchNextChapter);
        ApplyPreferences();
        RebuildItems();
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

    private async Task ShowChapterLoadFailureAsync()
    {
        if (string.IsNullOrWhiteSpace(Store.ErrorMessage))
        {
            return;
        }

        var dialog = new ContentDialog
        {
            Title = "章节加载失败",
            Content = new TextBlock { Text = Store.ErrorMessage, TextWrapping = TextWrapping.Wrap },
            CloseButtonText = "知道了",
            XamlRoot = XamlRoot
        };
        await dialog.ShowAsync();
    }

    private void SetNavigationEnabled(bool isEnabled)
    {
        PreviousChapterButton.IsEnabled = isEnabled;
        NextChapterButton.IsEnabled = isEnabled;
        ChapterPicker.IsEnabled = isEnabled;
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
        ReaderRoot.Background = _palette.Background;
        ReaderScrollViewer.Background = _palette.Background;
        ReaderContent.Width = ReaderLayout.EffectiveContentWidth(_preferences.ContentWidthEm, _preferences.FontSize, ActualWidth);
        ProgressText.Foreground = _palette.SecondaryForeground;
        ContinuationBoundary.Background = _palette.Background;
        ContinuationBoundary.BorderBrush = _palette.Separator;
        ContinuationBoundary.BorderThickness = new Thickness(1);
        ContinuationMessage.Foreground = _palette.SecondaryForeground;
    }

    private void ReaderPage_ActualThemeChanged(FrameworkElement sender, object args)
    {
        if (_preferences.Theme == "system") ApplyPreferences();
    }

    private FontFamily ReaderFontFamily() => _preferences.FontFamily switch
    {
        "system" => new FontFamily("Microsoft YaHei UI, Segoe UI"),
        "rounded" => new FontFamily("Microsoft YaHei UI, Segoe UI"),
        "kaiti" => new FontFamily("KaiTi, STKaiti, Microsoft YaHei UI"),
        _ => new FontFamily("Noto Serif CJK SC, SimSun, Microsoft YaHei UI")
    };

    private static string WidthName(double value) => value < 43 ? "narrow" : value > 53 ? "wide" : "comfortable";
    private static double WidthValue(string? value) => value switch
    {
        "narrow" => 38,
        "wide" => 58,
        _ => 48
    };

    private enum ReaderRebuildPosition
    {
        PreserveAnchor,
        ChapterTop,
        RestoreProgress
    }
}
