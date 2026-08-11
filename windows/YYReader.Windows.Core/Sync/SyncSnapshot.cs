using System.Text.Json;
using System.Text.Json.Serialization;
using YYReader.Windows.Core.Models;

namespace YYReader.Windows.Core.Sync;

public sealed class SyncSnapshot
{
    [JsonPropertyName("format")]
    public string Format { get; init; } = SyncSnapshotCodec.Format;

    [JsonPropertyName("version")]
    public int Version { get; init; } = SyncSnapshotCodec.Version;

    [JsonPropertyName("device")]
    public string Device { get; init; } = "";

    [JsonPropertyName("updatedAt")]
    public DateTimeOffset UpdatedAt { get; init; }

    [JsonPropertyName("books")]
    public List<SyncSnapshotBook> Books { get; init; } = new();

    [JsonExtensionData]
    public Dictionary<string, JsonElement>? ExtraFields { get; init; }
}

public sealed record SyncSnapshotBook
{
    [JsonPropertyName("sourceURL")]
    public string SourceUrl { get; init; } = "";

    [JsonPropertyName("title")]
    public string Title { get; init; } = "";

    [JsonPropertyName("author")]
    public string Author { get; init; } = "";

    [JsonPropertyName("currentChapterURL")]
    public string? CurrentChapterUrl { get; init; }

    [JsonPropertyName("paragraphIndex")]
    public int ParagraphIndex { get; init; }

    [JsonPropertyName("progress")]
    public double Progress { get; init; }

    [JsonPropertyName("lastReadAt")]
    public DateTimeOffset? LastReadAt { get; init; }

    [JsonPropertyName("updatedAt")]
    public DateTimeOffset UpdatedAt { get; init; }

    [JsonPropertyName("deletedAt")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public DateTimeOffset? DeletedAt { get; init; }

    [JsonExtensionData]
    public Dictionary<string, JsonElement>? ExtraFields { get; init; }

    public string CanonicalSourceUrl => UrlCanonicalizer.Canonicalize(SourceUrl).AbsoluteUri;
    public DateTimeOffset ActiveAt => LastReadAt is { } read && read > UpdatedAt ? read : UpdatedAt;
}

public static class SyncSnapshotCodec
{
    public const string Format = "yyreader-sync";
    public const int Version = 1;

    private static readonly JsonSerializerOptions Options = new()
    {
        PropertyNameCaseInsensitive = false,
        ReadCommentHandling = JsonCommentHandling.Skip,
        AllowTrailingCommas = true,
        WriteIndented = true
    };

    public static string Encode(SyncSnapshot snapshot) => JsonSerializer.Serialize(snapshot, Options);

    public static SyncSnapshot Decode(string json)
    {
        SyncSnapshot snapshot;
        try
        {
            snapshot = JsonSerializer.Deserialize<SyncSnapshot>(json, Options)
                ?? throw new SyncSnapshotException("同步文件内容为空。");
        }
        catch (JsonException exception)
        {
            throw new SyncSnapshotException($"同步文件不是有效 JSON：{exception.Message}", exception);
        }

        if (snapshot.Format != Format) throw new SyncSnapshotException("不是 YYReader SyncSnapshot 文件。");
        if (snapshot.Version != Version) throw new SyncSnapshotException($"暂不支持 SyncSnapshot v{snapshot.Version}。");
        foreach (var book in snapshot.Books)
        {
            if (string.IsNullOrWhiteSpace(book.SourceUrl)
                || !Uri.TryCreate(book.SourceUrl, UriKind.Absolute, out var source)
                || (!UrlCanonicalizer.IsHttp(source) && !source.Scheme.Equals("yyreader-book", StringComparison.OrdinalIgnoreCase)))
            {
                throw new SyncSnapshotException("同步书籍包含无效 sourceURL。");
            }
            if (book.ParagraphIndex < 0 || book.Progress is < 0 or > 1 || double.IsNaN(book.Progress))
            {
                throw new SyncSnapshotException("同步书籍包含无效阅读位置。");
            }
        }
        return snapshot;
    }
}

public sealed class SyncSnapshotException(string message, Exception? inner = null) : Exception(message, inner);
