namespace YYReader.Windows.Core.Services;

public static class HtmlChallengeDetector
{
    public static bool IsChallenge(string html)
    {
        var sample = html.ToLowerInvariant();
        return sample.Contains("cf-chl-", StringComparison.Ordinal)
            || sample.Contains("cloudflare challenge", StringComparison.Ordinal)
            || sample.Contains("<title>just a moment", StringComparison.Ordinal)
            || sample.Contains("enable javascript and cookies to continue", StringComparison.Ordinal);
    }
}
