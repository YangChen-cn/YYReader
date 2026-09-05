using Microsoft.UI.Input;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.System;
using Windows.UI.Core;

namespace YYReader.Windows.Views;

public sealed partial class ReaderPage
{
    private bool _presentationRestoring;
    private readonly Dictionary<(string Chapter, int Start), int> _academicColumns = new();
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
            header.Margin = new Thickness(0, 24, 0, 24);
            foreach (var text in new[] { plan.Title, "Abstract", plan.Abstract, "Keywords: " + plan.Keywords, plan.SectionTitle })
                header.Children.Add(new TextBlock { Text = text, TextWrapping = TextWrapping.Wrap, Foreground = _palette.Foreground,
                    FontFamily = new FontFamily("Times New Roman"), FontSize = text == plan.Title ? 26 : 16, Margin = new Thickness(0, 0, 0, 12) });
            return true;
        }
        if (element is not Grid grid) return false;
        if (item.Supplement is { } supplement)
        {
            grid.Children.Clear();
            grid.Children.Add(AcademicPaperVisuals.Create(supplement, _palette.Foreground));
            return true;
        }
        if (item.Kind != ReaderItemKind.AcademicBlock || item.PaperPlan is null) return false;
        grid.Children.Clear();
        grid.ColumnDefinitions.Clear();
        var two = _preferences.AcademicTwoColumns && ReaderRoot.ActualWidth >= 760;
        grid.ColumnSpacing = two ? 28 : 0;
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
                Text = p.Text + (p.Citations.Count == 0 ? "" : " [" + string.Join(", ", p.Citations) + "]"),
                Tag = new ReaderItem(ReaderItemKind.Paragraph, item.Chapter, index, original),
                IsTextSelectionEnabled = true, TextWrapping = TextWrapping.Wrap,
                FontFamily = new FontFamily("Times New Roman"), FontSize = _preferences.FontSize,
                LineHeight = _preferences.FontSize * (1 + _preferences.LineSpacing), Foreground = _palette.Foreground,
                Margin = new Thickness(0, 0, 0, _preferences.FontSize * _preferences.ParagraphSpacing)
            };
            (item.ColumnForParagraph(index, _preferences.AcademicTwoColumns, ReaderRoot.ActualWidth) == 1 ? right : left).Children.Add(paragraph);
        }
        return true;
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
