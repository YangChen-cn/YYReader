using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace YYReader.Windows.Views;

public sealed partial class AboutDialogContent : UserControl
{
    public AboutDialogContent()
    {
        InitializeComponent();
        var version = typeof(App).Assembly.GetName().Version;
        VersionText.Text = version is null
            ? "版本 1.2.1"
            : $"版本 {version.Major}.{version.Minor}.{Math.Max(0, version.Build)}";
    }

    public static async Task ShowAsync(XamlRoot xamlRoot)
    {
        var dialog = new ContentDialog
        {
            Content = new AboutDialogContent(),
            CloseButtonText = "关闭",
            DefaultButton = ContentDialogButton.Close,
            XamlRoot = xamlRoot
        };
        await dialog.ShowAsync();
    }
}
