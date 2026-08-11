using System.Text.Json;
using System.Text.Json.Serialization;
using YYReader.Windows.Core.Models;
using YYReader.Windows.Core.Persistence;

namespace YYReader.Windows.Core.Transfer;

public sealed class BookshelfTransferDocument
{
    [JsonPropertyName("format")]
    public string Format { get; init; } = "";

    [JsonPropertyName("version")]
    public int Version { get; init; }

    [JsonPropertyName("exportedAt")]
    public string ExportedAt { get; init; } = "";

    [JsonPropertyName("books")]
    public List<BookshelfTransferBook> Books { get; init; } = new();

    [JsonExtensionData]
    public Dictionary<string, JsonElement>? ExtraFields { get; init; }
}

public sealed class BookshelfTransferBook
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
    public int? ParagraphIndex { get; init; }

    [JsonPropertyName("progress")]
    public double? Progress { get; init; }

    [JsonExtensionData]
    public Dictionary<string, JsonElement>? ExtraFields { get; init; }
}

public static class BookshelfTransferCodec
{
    public const string Format = "yyreader-bookshelf";
    public const int Version = 1;

    private static readonly JsonSerializerOptions SerializerOptions = new()
    {
        PropertyNameCaseInsensitive = false,
        ReadCommentHandling = JsonCommentHandling.Skip,
        AllowTrailingCommas = true,
        WriteIndented = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
    };

    public static BookshelfTransferDocument Decode(string json)
    {
        BookshelfTransferDocument? document;
        try
        {
            document = JsonSerializer.Deserialize<BookshelfTransferDocument>(json, SerializerOptions);
        }
        catch (JsonException ex)
        {
            throw new BookshelfTransferException(BookshelfTransferErrorKind.MalformedJson, ex.Message);
        }

        if (document is null)
        {
            throw new BookshelfTransferException(BookshelfTransferErrorKind.InvalidDocument, "JSON 顶层对象不能为空。");
        }
        if (!string.Equals(document.Format, Format, StringComparison.Ordinal))
        {
            throw new BookshelfTransferException(BookshelfTransferErrorKind.InvalidDocument, "不是 YYReader bookshelf-transfer 文件。");
        }
        if (document.Version != Version)
        {
            throw new BookshelfTransferException(
                BookshelfTransferErrorKind.UnsupportedVersion,
                $"暂不支持 BookshelfTransfer v{document.Version}，当前支持 v{Version}。\n未知的可选字段会被忽略。");
        }
        if (!DateTimeOffset.TryParse(document.ExportedAt, out _))
        {
            throw new BookshelfTransferException(BookshelfTransferErrorKind.InvalidDocument, "exportedAt 不是有效的日期时间。");
        }

        return document;
    }

    public static string Encode(IEnumerable<BookshelfTransferBook> books, DateTimeOffset? exportedAt = null) =>
        JsonSerializer.Serialize(new BookshelfTransferDocument
        {
            Format = Format,
            Version = Version,
            ExportedAt = (exportedAt ?? DateTimeOffset.UtcNow).ToUniversalTime().ToString("O"),
            Books = books.ToList()
        }, SerializerOptions);

    public static string? ValidateBook(BookshelfTransferBook book)
    {
        if (string.IsNullOrWhiteSpace(book.SourceUrl)) return "缺少 sourceURL。";
        if (!Uri.TryCreate(book.SourceUrl.Trim(), UriKind.Absolute, out var sourceUri)
            || (!UrlCanonicalizer.IsHttp(sourceUri) && !sourceUri.Scheme.Equals("yyreader-book", StringComparison.OrdinalIgnoreCase)))
        {
            return "sourceURL 必须是 HTTP、HTTPS 或 YYReader 无目录书籍身份 URL。";
        }
        if (book.ParagraphIndex is < 0) return "paragraphIndex 不能为负数。";
        if (book.Progress is < 0 or > 1 || double.IsNaN(book.Progress ?? 0) || double.IsInfinity(book.Progress ?? 0))
        {
            return "progress 必须位于 0 到 1 之间。";
        }
        if (book.CurrentChapterUrl is not null
            && (!Uri.TryCreate(book.CurrentChapterUrl, UriKind.Absolute, out var chapterUri) || !UrlCanonicalizer.IsHttp(chapterUri)))
        {
            return "currentChapterURL 必须是 HTTP 或 HTTPS URL。";
        }
        return null;
    }
}

public enum BookshelfTransferErrorKind
{
    MalformedJson,
    InvalidDocument,
    UnsupportedVersion
}

public sealed class BookshelfTransferException(BookshelfTransferErrorKind kind, string message) : Exception(message)
{
    public BookshelfTransferErrorKind Kind { get; } = kind;
}

public enum BookshelfTransferEntryStatus
{
    New,
    Existing,
    DuplicateInFile,
    Invalid
}

public sealed record BookshelfTransferPreviewEntry(
    BookshelfTransferBook Book,
    BookshelfTransferEntryStatus Status,
    string? Error = null);

public sealed record BookshelfTransferPreview(
    IReadOnlyList<BookshelfTransferPreviewEntry> Entries,
    int NewCount,
    int ExistingCount,
    int InvalidCount,
    int DuplicateCount)
{
    public int TotalCount => Entries.Count;
}

public static class BookshelfTransferPlanner
{
    public static BookshelfTransferPreview Preview(
        BookshelfTransferDocument document,
        IEnumerable<Book> existingBooks)
    {
        var existing = existingBooks
            .Select(book => book.SourceBookUrl)
            .ToHashSet(StringComparer.Ordinal);
        var seen = new HashSet<string>(StringComparer.Ordinal);
        var entries = new List<BookshelfTransferPreviewEntry>();

        foreach (var book in document.Books)
        {
            var error = BookshelfTransferCodec.ValidateBook(book);
            if (error is not null)
            {
                entries.Add(new(book, BookshelfTransferEntryStatus.Invalid, error));
                continue;
            }

            var key = UrlCanonicalizer.Canonicalize(book.SourceUrl).AbsoluteUri;
            if (!seen.Add(key))
            {
                entries.Add(new(book, BookshelfTransferEntryStatus.DuplicateInFile, "同一个文件中已经出现过相同 sourceURL。"));
            }
            else if (existing.Contains(key))
            {
                entries.Add(new(book, BookshelfTransferEntryStatus.Existing));
            }
            else
            {
                entries.Add(new(book, BookshelfTransferEntryStatus.New));
            }
        }

        return new BookshelfTransferPreview(
            entries,
            entries.Count(entry => entry.Status == BookshelfTransferEntryStatus.New),
            entries.Count(entry => entry.Status == BookshelfTransferEntryStatus.Existing),
            entries.Count(entry => entry.Status == BookshelfTransferEntryStatus.Invalid),
            entries.Count(entry => entry.Status == BookshelfTransferEntryStatus.DuplicateInFile));
    }
}

public sealed record BookshelfTransferFailure(string SourceUrl, string Message);

public sealed record BookshelfTransferImportSummary(
    int Succeeded,
    int Skipped,
    int Failed,
    IReadOnlyList<BookshelfTransferFailure> Failures);

public static class BookshelfTransferImporter
{
    public static async Task<BookshelfTransferImportSummary> ImportAsync(
        BookshelfTransferDocument document,
        IEnumerable<Book> existingBooks,
        SqliteLibraryRepository repository,
        CancellationToken cancellationToken = default)
    {
        var preview = BookshelfTransferPlanner.Preview(document, existingBooks);
        var succeeded = 0;
        var skipped = 0;
        var failed = 0;
        var failures = new List<BookshelfTransferFailure>();

        foreach (var entry in preview.Entries)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (entry.Status == BookshelfTransferEntryStatus.DuplicateInFile)
            {
                skipped++;
                continue;
            }
            if (entry.Status == BookshelfTransferEntryStatus.Invalid)
            {
                failed++;
                failures.Add(new(entry.Book.SourceUrl, entry.Error ?? "数据无效。"));
                continue;
            }

            try
            {
                await repository.UpsertTransferBookAsync(entry.Book, cancellationToken).ConfigureAwait(false);
                succeeded++;
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                failed++;
                failures.Add(new(entry.Book.SourceUrl, ex.Message));
            }
        }

        return new BookshelfTransferImportSummary(succeeded, skipped, failed, failures);
    }
}
