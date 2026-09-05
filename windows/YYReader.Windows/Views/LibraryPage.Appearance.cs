using System.Security.Cryptography;
using System.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.UI;
using Windows.UI.ViewManagement;
using YYReader.Windows.Services;

namespace YYReader.Windows.Views;

public sealed partial class LibraryPage
{
    public static Brush BookCoverBrush(string identity)
    {
        if (new AccessibilitySettings().HighContrast)
            return new SolidColorBrush(new UISettings().GetColorValue(UIColorType.Background));
        Color[] colors =
        [
            Color.FromArgb(255, 54, 94, 81),
            Color.FromArgb(255, 66, 83, 112),
            Color.FromArgb(255, 128, 78, 66),
            Color.FromArgb(255, 107, 88, 118),
            Color.FromArgb(255, 117, 103, 65),
            Color.FromArgb(255, 53, 100, 109)
        ];
        var index = SHA256.HashData(Encoding.UTF8.GetBytes(identity))[0] % colors.Length;
        return new SolidColorBrush(colors[index]);
    }

    public static string BookSubtitle(string author, bool isLocalText) =>
        $"{(string.IsNullOrWhiteSpace(author) ? "未知作者" : author)}  ·  {(isLocalText ? "本地 TXT" : "网页小说")}";
    public static string ChapterProgress(double progress) => $"本章进度 {progress:P0}";
    public static string OpenBookLabel(string title) => $"阅读《{title}》";

    private void UpdateLibrarySummary()
    {
        TotalBooksText.Text = Store.Books.Count.ToString("D2");
        OfflineBooksText.Text = Store.Books.Count(book => book.Chapters.Any(chapter => chapter.IsAvailableOffline)).ToString("D2");
        LocalBooksText.Text = Store.Books.Count(book => book.IsLocalText).ToString("D2");
        UpdateSyncSummary(_folderSyncService.State);
    }

    private void UpdateSyncSummary(FolderSyncState state)
    {
        SyncSummaryText.Text = state.IsSyncing ? "正在同步…"
            : !string.IsNullOrWhiteSpace(state.ErrorMessage) ? "同步需要处理"
            : !_folderSyncService.Preferences.IsEnabled ? "设置文件夹同步"
            : state.LastSyncAt is { } at ? $"已同步 · {at.ToLocalTime():HH:mm}"
            : "文件夹同步已开启";
    }

    private void BookSearchBox_TextChanged(object sender, TextChangedEventArgs e) => RefreshBookRows();
    private void BookFilter_SelectionChanged(object sender, SelectionChangedEventArgs e) => RefreshBookRows();

    private void LibraryShell_SizeChanged(object sender, SizeChangedEventArgs e)
    {
        var compact = e.NewSize.Width < 900;
        LibraryShell.Padding = compact ? new Thickness(22, 18, 22, 14) : new Thickness(40, 24, 40, 18);
        LibraryStats.Visibility = compact ? Visibility.Collapsed : Visibility.Visible;
        FeaturedCover.Width = compact ? 76 : 104;
        FeaturedCover.Height = compact ? 112 : 142;
        FeaturedAction.Width = compact ? 118 : 150;
        FeaturedTitle.FontSize = compact ? 20 : 24;
        BookSearchBox.Width = compact ? 180 : 220;
    }
}
