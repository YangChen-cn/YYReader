using System.Globalization;
using Microsoft.Data.Sqlite;
using YYReader.Windows.Core.Models;
using YYReader.Windows.Core.Parsing;
using YYReader.Windows.Core.Transfer;

namespace YYReader.Windows.Core.Persistence;

public sealed class SqliteLibraryRepository
{
    private readonly string _connectionString;

    public SqliteLibraryRepository(string databasePath)
    {
        if (string.IsNullOrWhiteSpace(databasePath))
        {
            throw new ArgumentException("A database path is required.", nameof(databasePath));
        }

        if (!databasePath.Equals(":memory:", StringComparison.OrdinalIgnoreCase))
        {
            var directory = Path.GetDirectoryName(Path.GetFullPath(databasePath));
            if (!string.IsNullOrWhiteSpace(directory))
            {
                Directory.CreateDirectory(directory);
            }
        }

        _connectionString = new SqliteConnectionStringBuilder
        {
            DataSource = databasePath,
            Mode = databasePath.Equals(":memory:", StringComparison.OrdinalIgnoreCase)
                ? SqliteOpenMode.Memory
                : SqliteOpenMode.ReadWriteCreate,
            Cache = SqliteCacheMode.Shared,
            ForeignKeys = true,
            Pooling = false
        }.ToString();
    }

    public async Task InitializeAsync(CancellationToken cancellationToken = default)
    {
        await using var connection = await OpenAsync(cancellationToken).ConfigureAwait(false);
        await using var command = connection.CreateCommand();
        command.CommandText = """
            PRAGMA user_version = 1;
            CREATE TABLE IF NOT EXISTS Books (
                Id TEXT NOT NULL PRIMARY KEY,
                SourceBookUrl TEXT NOT NULL UNIQUE,
                CatalogUrl TEXT NOT NULL,
                Title TEXT NOT NULL,
                Author TEXT NOT NULL,
                SourceHost TEXT NOT NULL,
                HasCatalog INTEGER NOT NULL,
                CreatedAt TEXT NOT NULL,
                UpdatedAt TEXT NOT NULL,
                CatalogFetchedAt TEXT NULL,
                CurrentChapterUrl TEXT NULL
            );
            CREATE TABLE IF NOT EXISTS Chapters (
                BookId TEXT NOT NULL,
                SourceUrl TEXT NOT NULL,
                Title TEXT NOT NULL,
                SortIndex INTEGER NOT NULL,
                BodyText TEXT NULL,
                PreviousUrl TEXT NULL,
                NextUrl TEXT NULL,
                CachedAt TEXT NULL,
                PRIMARY KEY (BookId, SourceUrl),
                FOREIGN KEY (BookId) REFERENCES Books(Id) ON DELETE CASCADE
            );
            CREATE TABLE IF NOT EXISTS ReaderProgress (
                BookId TEXT NOT NULL,
                ChapterUrl TEXT NOT NULL,
                ParagraphIndex INTEGER NOT NULL DEFAULT 0,
                Progress REAL NOT NULL DEFAULT 0,
                LastReadAt TEXT NULL,
                PRIMARY KEY (BookId, ChapterUrl),
                FOREIGN KEY (BookId, ChapterUrl) REFERENCES Chapters(BookId, SourceUrl) ON DELETE CASCADE
            );
            CREATE INDEX IF NOT EXISTS IX_Books_UpdatedAt ON Books(UpdatedAt DESC);
            CREATE INDEX IF NOT EXISTS IX_Chapters_Book_Sort ON Chapters(BookId, SortIndex);
            """;
        await command.ExecuteNonQueryAsync(cancellationToken).ConfigureAwait(false);
    }

    public async Task<IReadOnlyList<Book>> GetBooksAsync(CancellationToken cancellationToken = default)
    {
        await using var connection = await OpenAsync(cancellationToken).ConfigureAwait(false);
        await using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT
                b.Id, b.SourceBookUrl, b.CatalogUrl, b.Title, b.Author, b.SourceHost,
                b.HasCatalog, b.CreatedAt, b.UpdatedAt, b.CatalogFetchedAt, b.CurrentChapterUrl,
                c.SourceUrl, c.Title, c.SortIndex, c.PreviousUrl, c.NextUrl, c.CachedAt,
                p.ParagraphIndex, p.Progress, p.LastReadAt
            FROM Books b
            LEFT JOIN Chapters c ON c.BookId = b.Id
            LEFT JOIN ReaderProgress p ON p.BookId = c.BookId AND p.ChapterUrl = c.SourceUrl
            ORDER BY b.UpdatedAt DESC, c.SortIndex ASC;
            """;

        var books = new Dictionary<string, Book>(StringComparer.Ordinal);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken).ConfigureAwait(false);
        while (await reader.ReadAsync(cancellationToken).ConfigureAwait(false))
        {
            var bookId = reader.GetString(0);
            if (!books.TryGetValue(bookId, out var book))
            {
                book = new Book(
                    bookId,
                    reader.GetString(1),
                    reader.GetString(2),
                    reader.GetString(3),
                    reader.GetString(4),
                    reader.GetString(5),
                    reader.GetInt64(6) != 0,
                    ParseDate(reader.GetString(7)),
                    ParseDate(reader.GetString(8)),
                    ParseNullableDate(reader, 9),
                    reader.IsDBNull(10) ? null : reader.GetString(10));
                books.Add(bookId, book);
            }

            if (reader.IsDBNull(11))
            {
                continue;
            }

            var chapter = new Chapter(
                reader.GetString(11),
                reader.GetString(12),
                reader.GetInt32(13),
                null,
                reader.IsDBNull(14) ? null : reader.GetString(14),
                reader.IsDBNull(15) ? null : reader.GetString(15),
                ParseNullableDate(reader, 16),
                reader.IsDBNull(17) ? 0 : reader.GetInt32(17),
                reader.IsDBNull(18) ? 0 : reader.GetDouble(18),
                ParseNullableDate(reader, 19));
            book.Chapters.Add(chapter);
        }

        return books.Values.ToArray();
    }

    public async Task<string?> LoadChapterBodyAsync(
        string bookId,
        string chapterUrl,
        CancellationToken cancellationToken = default)
    {
        var canonicalUrl = UrlCanonicalizer.CanonicalizeChapter(chapterUrl).AbsoluteUri;
        await using var connection = await OpenAsync(cancellationToken).ConfigureAwait(false);
        await using var command = connection.CreateCommand();
        command.CommandText = "SELECT BodyText FROM Chapters WHERE BookId = $book AND SourceUrl = $url;";
        command.Parameters.AddWithValue("$book", bookId);
        command.Parameters.AddWithValue("$url", canonicalUrl);
        var value = await command.ExecuteScalarAsync(cancellationToken).ConfigureAwait(false);
        return value is null or DBNull ? null : Convert.ToString(value, CultureInfo.InvariantCulture);
    }

    public async Task ClearChapterBodiesAsync(string bookId, CancellationToken cancellationToken = default)
    {
        await using var connection = await OpenAsync(cancellationToken).ConfigureAwait(false);
        await using var command = connection.CreateCommand();
        command.CommandText = "UPDATE Chapters SET BodyText = NULL, CachedAt = NULL WHERE BookId = $book;";
        command.Parameters.AddWithValue("$book", bookId);
        await command.ExecuteNonQueryAsync(cancellationToken).ConfigureAwait(false);
    }

    public async Task<Book?> FindBookBySourceUrlAsync(string sourceBookUrl, CancellationToken cancellationToken = default)
    {
        var key = UrlCanonicalizer.Canonicalize(sourceBookUrl).AbsoluteUri;
        return (await GetBooksAsync(cancellationToken).ConfigureAwait(false))
            .FirstOrDefault(book => string.Equals(book.SourceBookUrl, key, StringComparison.Ordinal));
    }

    public async Task<Book> UpsertImportAsync(
        NovelImportResult result,
        CancellationToken cancellationToken = default)
    {
        var sourceBookUrl = UrlCanonicalizer.Canonicalize(result.SourceBookUrl).AbsoluteUri;
        var catalogUrl = UrlCanonicalizer.Canonicalize(result.CatalogUrl).AbsoluteUri;
        var now = DateTimeOffset.UtcNow;

        await using var connection = await OpenAsync(cancellationToken).ConfigureAwait(false);
        using var transaction = connection.BeginTransaction();
        var bookId = await FindBookIdAsync(connection, transaction, sourceBookUrl, cancellationToken).ConfigureAwait(false)
            ?? Guid.NewGuid().ToString("D");
        var existingCreatedAt = await FindCreatedAtAsync(connection, transaction, bookId, cancellationToken).ConfigureAwait(false);

        await ExecuteAsync(connection, transaction, """
            INSERT INTO Books (Id, SourceBookUrl, CatalogUrl, Title, Author, SourceHost, HasCatalog, CreatedAt, UpdatedAt, CatalogFetchedAt, CurrentChapterUrl)
            VALUES ($id, $source, $catalog, $title, $author, $host, $hasCatalog, $created, $updated, $catalogFetched, $current)
            ON CONFLICT(SourceBookUrl) DO UPDATE SET
                CatalogUrl = excluded.CatalogUrl,
                Title = excluded.Title,
                Author = excluded.Author,
                SourceHost = excluded.SourceHost,
                HasCatalog = excluded.HasCatalog,
                UpdatedAt = excluded.UpdatedAt,
                CatalogFetchedAt = excluded.CatalogFetchedAt,
                CurrentChapterUrl = excluded.CurrentChapterUrl;
            """, cancellationToken,
            ("$id", bookId),
            ("$source", sourceBookUrl),
            ("$catalog", catalogUrl),
            ("$title", result.BookTitle),
            ("$author", result.Author),
            ("$host", result.SourceBookUrl.DnsSafeHost),
            ("$hasCatalog", result.HasCatalog ? 1 : 0),
            ("$created", (existingCreatedAt ?? now).ToString("O", CultureInfo.InvariantCulture)),
            ("$updated", now.ToString("O", CultureInfo.InvariantCulture)),
            ("$catalogFetched", now.ToString("O", CultureInfo.InvariantCulture)),
            ("$current", UrlCanonicalizer.CanonicalizeChapter(result.ChapterUrl).AbsoluteUri)).ConfigureAwait(false);

        foreach (var seed in result.Catalog)
        {
            var chapterUrl = UrlCanonicalizer.CanonicalizeChapter(seed.Url).AbsoluteUri;
            await ExecuteAsync(connection, transaction, """
                INSERT INTO Chapters (BookId, SourceUrl, Title, SortIndex, BodyText, PreviousUrl, NextUrl, CachedAt)
                VALUES ($book, $url, $title, $sort, NULL, NULL, NULL, NULL)
                ON CONFLICT(BookId, SourceUrl) DO UPDATE SET
                    Title = excluded.Title,
                    SortIndex = excluded.SortIndex;
                """, cancellationToken,
                ("$book", bookId), ("$url", chapterUrl), ("$title", seed.Title), ("$sort", seed.SortIndex)).ConfigureAwait(false);
        }

        var currentUrl = UrlCanonicalizer.CanonicalizeChapter(result.ChapterUrl).AbsoluteUri;
        await ExecuteAsync(connection, transaction, """
            INSERT INTO Chapters (BookId, SourceUrl, Title, SortIndex, BodyText, PreviousUrl, NextUrl, CachedAt)
            VALUES ($book, $url, $title, $sort, $body, $previous, $next, $cached)
            ON CONFLICT(BookId, SourceUrl) DO UPDATE SET
                Title = excluded.Title,
                BodyText = excluded.BodyText,
                PreviousUrl = excluded.PreviousUrl,
                NextUrl = excluded.NextUrl,
                CachedAt = excluded.CachedAt;
            """, cancellationToken,
            ("$book", bookId),
            ("$url", currentUrl),
            ("$title", result.ChapterTitle),
            ("$sort", result.Catalog.FirstOrDefault(seed => UrlCanonicalizer.CanonicalizeChapter(seed.Url).AbsoluteUri == currentUrl)?.SortIndex ?? result.Catalog.Max(seed => seed.SortIndex)),
            ("$body", ChapterText.NormalizeBodyText(result.BodyText)),
            ("$previous", DbValue(result.PreviousChapterUrl is null ? null : UrlCanonicalizer.CanonicalizeChapter(result.PreviousChapterUrl).AbsoluteUri)),
            ("$next", DbValue(result.NextChapterUrl is null ? null : UrlCanonicalizer.CanonicalizeChapter(result.NextChapterUrl).AbsoluteUri)),
            ("$cached", now.ToString("O", CultureInfo.InvariantCulture))).ConfigureAwait(false);

        transaction.Commit();
        return (await GetBooksAsync(cancellationToken).ConfigureAwait(false)).First(book => book.Id == bookId);
    }

    public async Task SaveChapterAsync(
        string bookId,
        ChapterLoadResult result,
        int sortIndex,
        CancellationToken cancellationToken = default)
    {
        var url = UrlCanonicalizer.CanonicalizeChapter(result.ChapterUrl).AbsoluteUri;
        await using var connection = await OpenAsync(cancellationToken).ConfigureAwait(false);
        await using var command = connection.CreateCommand();
        command.CommandText = """
            INSERT INTO Chapters (BookId, SourceUrl, Title, SortIndex, BodyText, PreviousUrl, NextUrl, CachedAt)
            VALUES ($book, $url, $title, $sort, $body, $previous, $next, $cached)
            ON CONFLICT(BookId, SourceUrl) DO UPDATE SET
                Title = excluded.Title,
                BodyText = excluded.BodyText,
                PreviousUrl = excluded.PreviousUrl,
                NextUrl = excluded.NextUrl,
                CachedAt = excluded.CachedAt;
            """;
        command.Parameters.AddWithValue("$book", bookId);
        command.Parameters.AddWithValue("$url", url);
        command.Parameters.AddWithValue("$title", result.Title);
        command.Parameters.AddWithValue("$sort", sortIndex);
        command.Parameters.AddWithValue("$body", ChapterText.NormalizeBodyText(result.BodyText));
        command.Parameters.AddWithValue("$previous", DbValue(result.PreviousChapterUrl is null ? null : UrlCanonicalizer.CanonicalizeChapter(result.PreviousChapterUrl).AbsoluteUri));
        command.Parameters.AddWithValue("$next", DbValue(result.NextChapterUrl is null ? null : UrlCanonicalizer.CanonicalizeChapter(result.NextChapterUrl).AbsoluteUri));
        command.Parameters.AddWithValue("$cached", DateTimeOffset.UtcNow.ToString("O", CultureInfo.InvariantCulture));
        await command.ExecuteNonQueryAsync(cancellationToken).ConfigureAwait(false);
    }

    public async Task<Book> UpsertCatalogAsync(
        string bookId,
        ParsedBookCatalog catalog,
        CancellationToken cancellationToken = default)
    {
        var now = DateTimeOffset.UtcNow;
        await using var connection = await OpenAsync(cancellationToken).ConfigureAwait(false);
        using var transaction = connection.BeginTransaction();
        await ExecuteAsync(connection, transaction, """
            UPDATE Books
            SET Title = $title, Author = $author, HasCatalog = 1,
                UpdatedAt = $updated, CatalogFetchedAt = $fetched
            WHERE Id = $book;
            """, cancellationToken,
            ("$title", catalog.Title), ("$author", catalog.Author),
            ("$updated", now.ToString("O", CultureInfo.InvariantCulture)),
            ("$fetched", now.ToString("O", CultureInfo.InvariantCulture)), ("$book", bookId)).ConfigureAwait(false);

        var visited = new HashSet<string>(StringComparer.Ordinal);
        foreach (var seed in catalog.Chapters)
        {
            var url = UrlCanonicalizer.CanonicalizeChapter(seed.Url).AbsoluteUri;
            if (!visited.Add(url)) continue;
            await ExecuteAsync(connection, transaction, """
                INSERT INTO Chapters (BookId, SourceUrl, Title, SortIndex, BodyText, PreviousUrl, NextUrl, CachedAt)
                VALUES ($book, $url, $title, $sort, NULL, NULL, NULL, NULL)
                ON CONFLICT(BookId, SourceUrl) DO UPDATE SET
                    Title = excluded.Title,
                    SortIndex = excluded.SortIndex;
                """, cancellationToken,
                ("$book", bookId), ("$url", url), ("$title", seed.Title), ("$sort", seed.SortIndex)).ConfigureAwait(false);
        }

        transaction.Commit();
        return (await GetBooksAsync(cancellationToken).ConfigureAwait(false)).Single(book => book.Id == bookId);
    }

    public async Task<Book> UpsertTransferBookAsync(
        BookshelfTransferBook transferBook,
        CancellationToken cancellationToken = default)
    {
        var sourceBookUrl = UrlCanonicalizer.Canonicalize(transferBook.SourceUrl).AbsoluteUri;
        var currentChapterUrl = transferBook.CurrentChapterUrl is null
            ? null
            : UrlCanonicalizer.CanonicalizeChapter(transferBook.CurrentChapterUrl).AbsoluteUri;
        var now = DateTimeOffset.UtcNow;

        await using var connection = await OpenAsync(cancellationToken).ConfigureAwait(false);
        using var transaction = connection.BeginTransaction();
        var bookId = await FindBookIdAsync(connection, transaction, sourceBookUrl, cancellationToken).ConfigureAwait(false)
            ?? Guid.NewGuid().ToString("D");
        var existingCreatedAt = await FindCreatedAtAsync(connection, transaction, bookId, cancellationToken).ConfigureAwait(false);
        await ExecuteAsync(connection, transaction, """
            INSERT INTO Books (Id, SourceBookUrl, CatalogUrl, Title, Author, SourceHost, HasCatalog, CreatedAt, UpdatedAt, CatalogFetchedAt, CurrentChapterUrl)
            VALUES ($id, $source, $catalog, $title, $author, $host, 0, $created, $updated, NULL, $current)
            ON CONFLICT(SourceBookUrl) DO UPDATE SET
                Title = CASE WHEN excluded.Title = '' THEN Books.Title ELSE excluded.Title END,
                Author = CASE WHEN excluded.Author = '' THEN Books.Author ELSE excluded.Author END,
                UpdatedAt = excluded.UpdatedAt,
                CurrentChapterUrl = COALESCE(excluded.CurrentChapterUrl, Books.CurrentChapterUrl);
            """, cancellationToken,
            ("$id", bookId), ("$source", sourceBookUrl), ("$catalog", sourceBookUrl),
            ("$title", transferBook.Title.Trim()), ("$author", transferBook.Author.Trim()),
            ("$host", Uri.TryCreate(transferBook.SourceUrl, UriKind.Absolute, out var sourceUri) ? sourceUri.DnsSafeHost : ""),
            ("$created", (existingCreatedAt ?? now).ToString("O", CultureInfo.InvariantCulture)),
            ("$updated", now.ToString("O", CultureInfo.InvariantCulture)), ("$current", currentChapterUrl ?? (object)DBNull.Value)).ConfigureAwait(false);

        if (currentChapterUrl is not null)
        {
            await ExecuteAsync(connection, transaction, """
                INSERT INTO Chapters (BookId, SourceUrl, Title, SortIndex, BodyText, PreviousUrl, NextUrl, CachedAt)
                VALUES ($book, $url, $title, 1, NULL, NULL, NULL, NULL)
                ON CONFLICT(BookId, SourceUrl) DO UPDATE SET
                    Title = CASE WHEN Chapters.Title = '' THEN excluded.Title ELSE Chapters.Title END;
                """, cancellationToken,
                ("$book", bookId), ("$url", currentChapterUrl), ("$title", string.IsNullOrWhiteSpace(transferBook.Title) ? "当前章节" : transferBook.Title.Trim())).ConfigureAwait(false);

            if (transferBook.ParagraphIndex is not null || transferBook.Progress is not null)
            {
                await ExecuteAsync(connection, transaction, """
                    INSERT INTO ReaderProgress (BookId, ChapterUrl, ParagraphIndex, Progress, LastReadAt)
                    VALUES ($book, $chapter, $index, $progress, $lastRead)
                    ON CONFLICT(BookId, ChapterUrl) DO UPDATE SET
                        ParagraphIndex = excluded.ParagraphIndex,
                        Progress = excluded.Progress,
                        LastReadAt = excluded.LastReadAt;
                    """, cancellationToken,
                    ("$book", bookId), ("$chapter", currentChapterUrl),
                    ("$index", Math.Max(transferBook.ParagraphIndex ?? 0, 0)),
                    ("$progress", Math.Clamp(transferBook.Progress ?? 0, 0, 1)),
                    ("$lastRead", now.ToString("O", CultureInfo.InvariantCulture))).ConfigureAwait(false);
            }
        }

        transaction.Commit();
        return (await GetBooksAsync(cancellationToken).ConfigureAwait(false)).First(book => book.Id == bookId);
    }

    public async Task SaveProgressAsync(
        string bookId,
        string chapterUrl,
        int paragraphIndex,
        double progress,
        DateTimeOffset lastReadAt,
        CancellationToken cancellationToken = default)
    {
        var canonicalChapterUrl = UrlCanonicalizer.CanonicalizeChapter(chapterUrl).AbsoluteUri;
        await using var connection = await OpenAsync(cancellationToken).ConfigureAwait(false);
        using var transaction = connection.BeginTransaction();
        await ExecuteAsync(connection, transaction, """
            INSERT INTO ReaderProgress (BookId, ChapterUrl, ParagraphIndex, Progress, LastReadAt)
            VALUES ($book, $chapter, $index, $progress, $lastRead)
            ON CONFLICT(BookId, ChapterUrl) DO UPDATE SET
                ParagraphIndex = excluded.ParagraphIndex,
                Progress = excluded.Progress,
                LastReadAt = excluded.LastReadAt;
            """, cancellationToken,
            ("$book", bookId), ("$chapter", canonicalChapterUrl), ("$index", Math.Max(paragraphIndex, 0)),
            ("$progress", Math.Clamp(progress, 0, 1)), ("$lastRead", lastReadAt.ToString("O", CultureInfo.InvariantCulture))).ConfigureAwait(false);
        await ExecuteAsync(connection, transaction,
            "UPDATE Books SET CurrentChapterUrl = $chapter, UpdatedAt = $updated WHERE Id = $book;",
            cancellationToken,
            ("$chapter", canonicalChapterUrl), ("$updated", lastReadAt.ToString("O", CultureInfo.InvariantCulture)), ("$book", bookId)).ConfigureAwait(false);
        transaction.Commit();
    }

    public async Task DeleteBookAsync(string bookId, CancellationToken cancellationToken = default)
    {
        await using var connection = await OpenAsync(cancellationToken).ConfigureAwait(false);
        await using var command = connection.CreateCommand();
        command.CommandText = "DELETE FROM Books WHERE Id = $id;";
        command.Parameters.AddWithValue("$id", bookId);
        await command.ExecuteNonQueryAsync(cancellationToken).ConfigureAwait(false);
    }

    private async Task<SqliteConnection> OpenAsync(CancellationToken cancellationToken)
    {
        var connection = new SqliteConnection(_connectionString);
        await connection.OpenAsync(cancellationToken).ConfigureAwait(false);
        return connection;
    }

    private static async Task<string?> FindBookIdAsync(
        SqliteConnection connection,
        SqliteTransaction transaction,
        string sourceBookUrl,
        CancellationToken cancellationToken)
    {
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = "SELECT Id FROM Books WHERE SourceBookUrl = $source;";
        command.Parameters.AddWithValue("$source", sourceBookUrl);
        return await command.ExecuteScalarAsync(cancellationToken).ConfigureAwait(false) as string;
    }

    private static async Task<DateTimeOffset?> FindCreatedAtAsync(
        SqliteConnection connection,
        SqliteTransaction transaction,
        string bookId,
        CancellationToken cancellationToken)
    {
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = "SELECT CreatedAt FROM Books WHERE Id = $id;";
        command.Parameters.AddWithValue("$id", bookId);
        var value = await command.ExecuteScalarAsync(cancellationToken).ConfigureAwait(false) as string;
        return value is null ? null : ParseDate(value);
    }

    private static async Task ExecuteAsync(
        SqliteConnection connection,
        SqliteTransaction transaction,
        string sql,
        CancellationToken cancellationToken,
        params (string Name, object Value)[] parameters)
    {
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = sql;
        foreach (var (name, value) in parameters)
        {
            command.Parameters.AddWithValue(name, value);
        }
        await command.ExecuteNonQueryAsync(cancellationToken).ConfigureAwait(false);
    }

    private static object DbValue(string? value) => value is null ? DBNull.Value : value;

    private static DateTimeOffset ParseDate(string value) =>
        DateTimeOffset.Parse(value, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind);

    private static DateTimeOffset? ParseNullableDate(SqliteDataReader reader, int ordinal) =>
        reader.IsDBNull(ordinal) ? null : ParseDate(reader.GetString(ordinal));
}
