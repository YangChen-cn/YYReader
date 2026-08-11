using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media;

namespace YYReader.Windows.Views;

public sealed record ReaderThemePalette(
    ElementTheme ElementTheme,
    SolidColorBrush Background,
    SolidColorBrush Foreground,
    SolidColorBrush SecondaryForeground,
    SolidColorBrush Accent,
    SolidColorBrush Separator)
{
    public static ReaderThemePalette FromName(string name) => name switch
    {
        "light" => Create(ElementTheme.Light, 0xF9, 0xFA, 0xF8, 0x20, 0x22, 0x25, 0x4E, 0x78, 0xA8),
        "sepia" => Create(ElementTheme.Light, 0xF2, 0xEA, 0xD9, 0x3B, 0x2D, 0x20, 0xA5, 0x65, 0x3C),
        "rose" => Create(ElementTheme.Light, 0xF5, 0xE9, 0xED, 0x52, 0x2E, 0x3E, 0xA1, 0x4E, 0x6E),
        "dark" => Create(ElementTheme.Dark, 0x25, 0x25, 0x23, 0xE6, 0xE3, 0xD9, 0xD4, 0xAE, 0x6E),
        "midnight" => Create(ElementTheme.Dark, 0x1D, 0x22, 0x29, 0xDE, 0xE5, 0xEB, 0x58, 0xB4, 0xC8),
        _ => Create(ElementTheme.Default, 0xF9, 0xFA, 0xFB, 0x25, 0x25, 0x27, 0x0, 0x99, 0xFF)
    };

    private static ReaderThemePalette Create(
        ElementTheme theme,
        byte backgroundR,
        byte backgroundG,
        byte backgroundB,
        byte foregroundR,
        byte foregroundG,
        byte foregroundB,
        byte accentR,
        byte accentG,
        byte accentB)
    {
        var background = Brush(backgroundR, backgroundG, backgroundB);
        var foreground = Brush(foregroundR, foregroundG, foregroundB);
        var secondary = Brush(
            (byte)((foregroundR + 128) / 2),
            (byte)((foregroundG + 128) / 2),
            (byte)((foregroundB + 128) / 2));
        var accent = Brush(accentR, accentG, accentB);
        var separator = Brush(
            (byte)((backgroundR + foregroundR) / 2),
            (byte)((backgroundG + foregroundG) / 2),
            (byte)((backgroundB + foregroundB) / 2));
        return new ReaderThemePalette(theme, background, foreground, secondary, accent, separator);
    }

    private static SolidColorBrush Brush(byte red, byte green, byte blue) =>
        new(ColorHelper.FromArgb(255, red, green, blue));
}
