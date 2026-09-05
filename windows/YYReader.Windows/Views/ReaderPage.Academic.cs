using Microsoft.UI.Input;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Documents;
using Windows.UI.Text;
using YYReader.Windows.Core.Models;
using Microsoft.UI.Xaml.Media;
using Windows.System;
using Windows.UI.Core;

namespace YYReader.Windows.Views;

public sealed partial class ReaderPage
{
    private bool _presentationRestoring;
    private readonly Dictionary<(string Chapter, int Start), int> _academicColumns = new();
    private double AcademicBodySize => Math.Clamp(_preferences.FontSize * .78, 12, 28);
    private string? AcademicBookIdentity => _preferences.AcademicMode ? Store.SelectedBook?.SourceBookUrl : null;

    private void AcademicMode_Click(object sender, RoutedEventArgs e) => ToggleAcademicMode();
    private void ToggleAcademicMode()
    {
        CommitVisiblePosition();
        _preferences = _preferences with { AcademicMode = !_preferences.AcademicMode };
        RebuildItems();
        SchedulePreferencesSave();
    }

    private void AcademicColumns_Click(object sender, RoutedEventArgs e)
    {
        _preferences = _preferences with { AcademicTwoColumns = AcademicColumnsCheckBox.IsChecked == true };
        if (_preferences.AcademicMode) RebuildItems();
        SchedulePreferencesSave();
    }

    private void AcademicShortcut_LostFocus(object sender, RoutedEventArgs e)
    {
        var letter = AcademicShortcutBox.Text.Trim().ToUpperInvariant();
        if (letter.Length == 1 && letter[0] is >= 'A' and <= 'Z')
        {
            _preferences = _preferences with { AcademicShortcut = letter };
            SchedulePreferencesSave();
        }
        AcademicShortcutBox.Text = _preferences.AcademicShortcut;
    }

    private bool IsAcademicShortcut(VirtualKey key) =>
        (int)key == _preferences.AcademicShortcut.FirstOrDefault()
        && InputKeyboardSource.GetKeyStateForCurrentThread(VirtualKey.Control).HasFlag(CoreVirtualKeyStates.Down)
        && InputKeyboardSource.GetKeyStateForCurrentThread(VirtualKey.Menu).HasFlag(CoreVirtualKeyStates.Down);

    private bool ApplyAcademicStyle(UIElement element, ReaderItem item)
    {
        if (item.PaperPlan is { } plan && item.Kind == ReaderItemKind.Header && element is StackPanel header)
        {
            header.Children.Clear();
            header.Margin = new Thickness(0, 28, 0, 16);
            header.Spacing = 0;
            TextBlock Text(string value, double size, bool bold = false) => new()
            {
                Text = value, FontFamily = AcademicTypography.Latin, FontSize = size,
                Foreground = _palette.Foreground, TextWrapping = TextWrapping.Wrap,
                FontWeight = bold ? Microsoft.UI.Text.FontWeights.Bold : Microsoft.UI.Text.FontWeights.Normal,
                Margin = new Thickness(0, 0, 0, 10)
            };
            var running = new Grid { ColumnDefinitions = { new ColumnDefinition(), new ColumnDefinition { Width = GridLength.Auto } },
                BorderBrush = _palette.Foreground, BorderThickness = new Thickness(0, 0, 0, 1), Margin = new Thickness(0, 0, 0, 22) };
            var category = Text("TEXTUAL ANALYSIS", 10, true); category.CharacterSpacing = 100;
            running.Children.Add(category);
            var articleType = Text("RESEARCH ARTICLE", 10); Grid.SetColumn(articleType, 1); running.Children.Add(articleType);
            header.Children.Add(running);
            var title = Text(plan.Title, 25, true); title.TextAlignment = TextAlignment.Center;
            title.Margin = new Thickness(20, 0, 20, 20); header.Children.Add(title);
            var abstractLabel = Text("Abstract", 13, true); abstractLabel.TextAlignment = TextAlignment.Center;
            header.Children.Add(abstractLabel);
            var abstractText = Text(plan.Abstract, 13); abstractText.TextAlignment = TextAlignment.Justify;
            abstractText.LineHeight = 18; abstractText.Margin = new Thickness(24, 0, 24, 10); header.Children.Add(abstractText);
            var keywords = Text("Keywords: " + plan.Keywords, 12); keywords.FontStyle = FontStyle.Italic;
            keywords.Margin = new Thickness(24, 0, 24, 20); header.Children.Add(keywords);
            header.Children.Add(new Border { Height = 1, Background = _palette.Separator, Margin = new Thickness(0, 0, 0, 18) });
            header.Children.Add(Text(plan.SectionTitle, 17, true));
            return true;
        }
        if (element is not Grid grid) return false;
        if (item.Supplement is { } supplement)
        {
            grid.Children.Clear();
            grid.Children.Add(AcademicPaperVisuals.Create(supplement, _palette.Foreground, AcademicBodySize / 15.6));
            return true;
        }
        if (item.Kind != ReaderItemKind.AcademicBlock || item.PaperPlan is null) return false;
        grid.Children.Clear();
        grid.ColumnDefinitions.Clear();
        var two = _preferences.AcademicTwoColumns && ReaderRoot.ActualWidth >= 760;
        grid.ColumnSpacing = two ? 30 : 0;
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        if (two) grid.ColumnDefinitions.Add(new ColumnDefinition());
        var left = new StackPanel();
        var right = new StackPanel();
        grid.Children.Add(left);
        if (two) { Grid.SetColumn(right, 1); grid.Children.Add(right); }
        var original = item.PaperPlan.Paragraphs.Select(p => p.Text).ToArray();
        for (var index = item.ParagraphIndex; index < item.EndParagraphIndex; index++)
        {
            var p = item.PaperPlan.Paragraphs[index];
            var paragraph = new TextBlock
            {
                Tag = new ReaderItem(ReaderItemKind.Paragraph, item.Chapter, index, original),
                IsTextSelectionEnabled = true, TextWrapping = TextWrapping.Wrap,
                FontFamily = AcademicTypography.Chinese, FontSize = AcademicBodySize,
                FontWeight = Microsoft.UI.Text.FontWeights.Normal, TextAlignment = TextAlignment.Justify,
                LineHeight = AcademicBodySize * 1.42, LineStackingStrategy = LineStackingStrategy.BlockLineHeight,
                Foreground = _palette.Foreground, Margin = new Thickness(0, 0, 0, AcademicBodySize * .24)
            };
            AcademicTypography.SetBody(paragraph, p.Text);
            if (p.Citations.Count > 0)
                paragraph.Inlines.Add(new Run { Text = " [" + string.Join(", ", p.Citations) + "]", FontFamily = AcademicTypography.Latin, FontSize = AcademicBodySize * .85 });
            (item.ColumnForParagraph(index, _preferences.AcademicTwoColumns, ReaderRoot.ActualWidth) == 1 ? right : left).Children.Add(paragraph);
        }
        return true;
    }

    private void UpdateReaderContentWidth(double availableWidth)
    {
        ReaderContent.Width = _preferences.AcademicMode
            ? Math.Max(1, Math.Min(_preferences.AcademicTwoColumns && availableWidth >= 760 ? 960 : 760, availableWidth - 32))
            : ReaderLayout.EffectiveContentWidth(_preferences.ContentWidthEm, _preferences.FontSize, availableWidth);
    }

    private void ApplyAcademicPageAppearance()
    {
        UpdateReaderContentWidth(ReaderRoot.ActualWidth > 0 ? ReaderRoot.ActualWidth : ActualWidth);
        var paper = _preferences.AcademicMode;
        ReaderContent.Padding = paper ? new Thickness(40, 0, 40, 28) : new Thickness(0);
        ReaderContent.BorderThickness = paper ? new Thickness(1, 0, 1, 0) : new Thickness(0);
        ReaderContent.BorderBrush = _palette.Separator;
        ReaderContent.Background = null;
        ReaderScrollViewer.Background = _palette.Background;
        if (paper)
        {
            bool dark = _palette.ElementTheme == ElementTheme.Dark || _palette.ElementTheme == ElementTheme.Default && ActualTheme == ElementTheme.Dark;
            ReaderContent.Background = new SolidColorBrush(dark ? Microsoft.UI.ColorHelper.FromArgb(255, 37, 37, 39) : Microsoft.UI.Colors.White);
            ReaderScrollViewer.Background = new SolidColorBrush(dark ? Microsoft.UI.ColorHelper.FromArgb(255, 27, 27, 29) : Microsoft.UI.ColorHelper.FromArgb(255, 232, 233, 235));
            if (new global::Windows.UI.ViewManagement.AccessibilitySettings().HighContrast)
            {
                var settings = new global::Windows.UI.ViewManagement.UISettings();
                ReaderContent.Background = ReaderScrollViewer.Background = new SolidColorBrush(settings.GetColorValue(global::Windows.UI.ViewManagement.UIColorType.Background));
            }
        }
        UpdateReaderChrome();
    }

    private void UpdateReaderChrome()
    {
        var plan = Items.FirstOrDefault(item => item.ChapterUrl == Store.SelectedChapter?.SourceUrl && item.PaperPlan is not null)?.PaperPlan;
        ToolbarBookTitle.Text = _preferences.AcademicMode ? plan?.Title ?? "Textual Analysis · Research Article" : Store.SelectedBook?.Title ?? "";
        ToolbarBookTitle.FontFamily = _preferences.AcademicMode ? AcademicTypography.Latin : new FontFamily("Segoe UI Variable Text");
        ToolbarChapterTitle.Text = _preferences.AcademicMode ? plan?.SectionTitle ?? "Research Article" : Store.SelectedChapter?.Title ?? "";
        ProgressText.Text = _preferences.AcademicMode
            ? $"{plan?.SectionTitle ?? "Research Article"}   ·   {Store.SelectedChapter?.Progress:P0}"
            : $"{Store.SelectedChapter?.Progress:P0}　{Store.SelectedChapter?.Title}";
    }

    private static IEnumerable<FrameworkElement> Descendants(FrameworkElement root)
    {
        yield return root;
        for (var i = 0; i < VisualTreeHelper.GetChildrenCount(root); i++)
            if (VisualTreeHelper.GetChild(root, i) is FrameworkElement child)
                foreach (var descendant in Descendants(child)) yield return descendant;
    }

    private IEnumerable<(ReaderItem Item, FrameworkElement Element)> RealizedParagraphs()
    {
        foreach (var (index, element) in _realizedElements.OrderBy(pair => pair.Key).ToArray())
        {
            if (index < 0 || index >= Items.Count || element is not FrameworkElement root) continue;
            var item = Items[index];
            if (item.IsParagraph) yield return (item, root);
            else if (item.Kind == ReaderItemKind.AcademicBlock)
                foreach (var child in Descendants(root).Where(child => child.Tag is ReaderItem { IsParagraph: true })
                    .OrderBy(child => item.ColumnForParagraph(((ReaderItem)child.Tag).ParagraphIndex, _preferences.AcademicTwoColumns, ReaderRoot.ActualWidth)
                        == _academicColumns.GetValueOrDefault((item.ChapterUrl, item.ParagraphIndex)) ? 0 : 1))
                    if (child.Tag is ReaderItem paragraph) yield return (paragraph, child);
        }
    }

    private void RememberAcademicColumn(string chapterUrl, int paragraphIndex)
    {
        if (!_preferences.AcademicMode || !_preferences.AcademicTwoColumns || ReaderRoot.ActualWidth < 760) return;
        var block = Items.FirstOrDefault(item => item.Kind == ReaderItemKind.AcademicBlock && item.ChapterUrl == chapterUrl && item.ContainsParagraph(paragraphIndex));
        if (block is not null) _academicColumns[(chapterUrl, block.ParagraphIndex)] = block.ColumnForParagraph(paragraphIndex, true, ReaderRoot.ActualWidth);
    }

    private UIElement ParagraphElement(int itemIndex, int paragraphIndex)
    {
        var root = ReaderRepeater.GetOrCreateElement(itemIndex);
        if (Items[itemIndex].Kind == ReaderItemKind.AcademicBlock && root is FrameworkElement framework)
        {
            ApplyRealizedItemStyle(root, Items[itemIndex]);
            root.UpdateLayout();
            return Descendants(framework).FirstOrDefault(child => child.Tag is ReaderItem p && p.ParagraphIndex == paragraphIndex) ?? root;
        }
        return root;
    }
}
