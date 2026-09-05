using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using YYReader.Windows.Core.Models;

namespace YYReader.Windows.Core.Services;

public sealed record LocalTextImportDraft(string SourceBookUrl, string Title, string Encoding, IReadOnlyList<Chapter> Chapters);

public static class LocalTextImportService
{
    public static async Task<LocalTextImportDraft> PrepareAsync(string path, CancellationToken cancellationToken = default)
    {
        if (!Path.GetExtension(path).Equals(".txt", StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("只支持 TXT 文件。");
        var bytes = await File.ReadAllBytesAsync(path, cancellationToken).ConfigureAwait(false);
        return await Task.Run(() => Prepare(bytes, Path.GetFileNameWithoutExtension(path), cancellationToken), cancellationToken).ConfigureAwait(false);
    }

    public static LocalTextImportDraft Prepare(byte[] bytes, string title, CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        if (bytes.Length == 0) throw new InvalidDataException("TXT 文件为空。");
        string text;
        string encoding;
        try
        {
            bool bom = bytes.AsSpan().StartsWith(new byte[] { 0xef, 0xbb, 0xbf });
            text = new UTF8Encoding(false, true).GetString(bytes, bom ? 3 : 0, bytes.Length - (bom ? 3 : 0));
            encoding = bom ? "UTF-8 BOM" : "UTF-8";
        }
        catch (DecoderFallbackException)
        {
            Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);
            try { text = Encoding.GetEncoding(54936, EncoderFallback.ExceptionFallback, DecoderFallback.ExceptionFallback).GetString(bytes); }
            catch (DecoderFallbackException ex) { throw new InvalidDataException("不支持的 TXT 编码。", ex); }
            encoding = "GB18030 / GBK";
        }
        text = Regex.Replace(text.Replace("\r\n", "\n").Replace('\r', '\n').Trim().Trim('\ufeff').Trim(), @"\n[ \t\u3000]*\n(?:[ \t\u3000]*\n)+", "\n\n");
        if (string.IsNullOrWhiteSpace(text)) throw new InvalidDataException("TXT 没有可阅读正文。");
        using var hash = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        hash.AppendData(Encoding.UTF8.GetBytes("yyreader-txt-v1\0" + bytes.Length.ToString(CultureInfo.InvariantCulture) + "\0"));
        hash.AppendData(bytes);
        var identity = "yyreader-local://txt/" + Convert.ToHexString(hash.GetHashAndReset()).ToLowerInvariant();
        var lines = text.Split('\n');
        var candidates = lines.Select((line, index) => (Title: line.Trim(), Index: index)).Where(x => IsTitle(x.Title)).ToArray();
        var reliable = candidates.Length >= 2 || candidates.Length == 1
            && lines.Take(candidates[0].Index).Count(x => !string.IsNullOrWhiteSpace(x)) < 20
            && IsSubstantive(lines.Skip(candidates[0].Index + 1));
        var pieces = new List<(string Title, string Body)>();
        if (reliable)
        {
            var prefix = lines.Take(candidates[0].Index).ToArray();
            if (IsSubstantive(prefix)) { pieces.Add(("前言", string.Join('\n', prefix))); prefix = []; }
            for (var i = 0; i < candidates.Length; i++)
            {
                cancellationToken.ThrowIfCancellationRequested();
                var end = i + 1 < candidates.Length ? candidates[i + 1].Index : lines.Length;
                var body = string.Join('\n', (i == 0 ? prefix : []).Concat(lines.Skip(candidates[i].Index + 1).Take(end - candidates[i].Index - 1)));
                if (!string.IsNullOrWhiteSpace(body)) pieces.Add((candidates[i].Title, body));
            }
        }
        if (pieces.Count == 0) pieces.Add(("正文", text));
        string Url(int index) => identity + "/chapter/" + index.ToString("D6", CultureInfo.InvariantCulture);
        var now = DateTimeOffset.UtcNow;
        var chapters = pieces.Select((piece, i) => new Chapter(Url(i + 1), piece.Title, i + 1, piece.Body,
            i > 0 ? Url(i) : null, i + 1 < pieces.Count ? Url(i + 2) : null, now)).ToArray();
        return new(identity, string.IsNullOrWhiteSpace(title) ? "本地小说" : title.Trim(), encoding, chapters);
    }

    private static bool IsSubstantive(IEnumerable<string> lines)
    {
        var content = lines.Where(x => !string.IsNullOrWhiteSpace(x)).ToArray();
        return content.Length >= 2 || content.Sum(x => x.Count(c => !char.IsWhiteSpace(c))) >= 200;
    }

    public static bool IsTitle(string value)
    {
        if (value.Length is 0 or > 60 || "。！？!?；;".Contains(value[^1])) return false;
        const string n = "[0-9０-９〇零一二三四五六七八九十百千万两]+";
        const string suffix = @"(?:[ \t\u3000:：·、\-—]+.{1,42})?";
        return Regex.IsMatch(value, @"\A(?:第[ \t\u3000]*" + n + @"[ \t\u3000]*(?:章|回|节|卷)|序章|序言|楔子|引子|尾声|后记|番外(?:[ \t\u3000]*" + n + @")?|卷[ \t\u3000]*" + n + ")" + suffix + @"\z");
    }
}
