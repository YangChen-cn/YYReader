using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;
using Windows.Foundation;
using YYReader.Windows.Core.Reading;

namespace YYReader.Windows.Views;

// Native WinUI primitives only; decorations never receive a ReaderItem paragraph tag.
internal static class AcademicPaperVisuals
{
    public static FrameworkElement Create(AcademicSupplement supplement, Brush foreground)
    {
        var panel = new StackPanel { Spacing = 10, Margin = new Thickness(0, 20, 0, 24) };
        TextBlock Text(string text, double size = 14) => new() { Text = text, FontSize = size, Foreground = foreground, TextWrapping = TextWrapping.Wrap };
        if (supplement.Kind == "equation")
        {
            panel.Children.Add(Text($"S(t) = α · C(t) + β · E(t) + ε(t)                         ({supplement.Number})", 20));
            panel.Children.Add(Text("where C denotes contextual continuity, E represents observable evidence, and ε is the residual term."));
        }
        else if (supplement.Kind == "table")
        {
            panel.Children.Add(Text($"Table {supplement.Number}. Estimates of contextual effects"));
            var table = new Grid { BorderBrush = foreground, BorderThickness = new Thickness(0, 1, 0, 1), Padding = new Thickness(0, 8, 0, 8), RowSpacing = 8, ColumnSpacing = 12 };
            for (var i = 0; i < 4; i++) table.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            string[][] rows = [["Variable", "Estimate", "95% CI", "p value"], ["Continuity", "0.72", "[0.64, 0.80]", "< .001"], ["Transition", "0.38", "[0.25, 0.51]", ".004"], ["Context", "0.61", "[0.49, 0.73]", "< .001"], ["Residual", "0.09", "[0.02, 0.16]", ".021"]];
            for (var r = 0; r < rows.Length; r++)
            {
                table.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
                for (var c = 0; c < 4; c++) { var cell = Text(rows[r][c]); Grid.SetRow(cell, r); Grid.SetColumn(cell, c); table.Children.Add(cell); }
            }
            panel.Children.Add(table);
            panel.Children.Add(Text("Note. Standardized illustrative estimates; CI denotes confidence interval."));
        }
        else
        {
            panel.Children.Add(Text($"Figure {supplement.Number}. Contextual continuity across observations"));
            var chart = new Canvas { Width = 560, Height = 240 };
            var accent = new SolidColorBrush(Colors.SteelBlue);
            var comparison = new SolidColorBrush(Colors.DarkOrange);
            void Line(double x1, double y1, double x2, double y2, Brush brush, bool dashed = false)
            {
                var line = new Line { X1 = x1, Y1 = y1, X2 = x2, Y2 = y2, Stroke = brush, StrokeThickness = 1.5 };
                if (dashed) line.StrokeDashArray = new DoubleCollection { 4, 4 };
                chart.Children.Add(line);
            }
            void Label(string text, double x, double y)
            {
                var label = Text(text, 12); Canvas.SetLeft(label, x); Canvas.SetTop(label, y); chart.Children.Add(label);
            }
            Line(45, 15, 45, 195, foreground); Line(45, 195, 535, 195, foreground);
            for (var i = 0; i <= 4; i++) { var y = 195 - i * 45; Label((i * .25).ToString("0.00", System.Globalization.CultureInfo.InvariantCulture), 4, y - 8); }
            Line(45, 105, 535, 105, foreground, true);
            double[] first = [.30, .45, .42, .59, .66, .62, .79, .84];
            double[] second = [.22, .31, .38, .41, .49, .51, .57, .64];
            for (var i = 0; i < first.Length; i++)
            {
                var x = 55 + i * 66;
                Label((i + 1).ToString(), x - 3, 200);
                if (i > 0) { Line(x - 66, 195 - first[i - 1] * 180, x, 195 - first[i] * 180, accent); Line(x - 66, 195 - second[i - 1] * 180, x, 195 - second[i] * 180, comparison); }
            }
            Label("Observation", 235, 221);
            var viewbox = new Viewbox { Child = chart, Stretch = Stretch.Uniform, MaxHeight = 260, HorizontalAlignment = HorizontalAlignment.Stretch };
            panel.Children.Add(Text("Normalized score", 12));
            panel.Children.Add(viewbox);
            var legend = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 20 };
            var a = Text("━ Context"); a.Foreground = accent; legend.Children.Add(a);
            var b = Text("━ Baseline"); b.Foreground = comparison; legend.Children.Add(b);
            legend.Children.Add(Text("┄ Reference = 0.50")); panel.Children.Add(legend);
        }
        return panel;
    }
}
