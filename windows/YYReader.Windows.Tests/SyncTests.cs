using Microsoft.VisualStudio.TestTools.UnitTesting;
using YYReader.Windows.Core.Sync;

namespace YYReader.Windows.Tests;

[TestClass]
public sealed class SyncTests
{
    [TestMethod]
    public void MergeUsesNewerMetadataAndReadingPositionIndependently()
    {
        var local = Book("https://EXAMPLE.com/book/", "旧标题", "https://example.com/book/9.html", 2, 0.2, "2026-01-01", "2026-01-04", 9);
        var remote = Book("https://example.com/book/", "新标题", "https://example.com/book/3.html", 8, 0.8, "2026-01-03", "2026-01-05", 3);

        var merged = SyncMergePlanner.Merge([local], [remote]).Single();

        Assert.AreEqual("新标题", merged.Title);
        Assert.AreEqual("https://example.com/book/9.html", merged.CurrentChapterUrl);
        Assert.AreEqual(9, merged.CurrentChapterIndex);
        Assert.AreEqual(2, merged.ParagraphIndex);
        Assert.AreEqual(DateTimeOffset.Parse("2026-01-05"), merged.LastReadAt);
    }

    [TestMethod]
    public void TombstonePreventsStaleSnapshotFromRestoringBookAndMergeIsIdempotent()
    {
        var active = Book("https://example.com/book/", "书", "https://example.com/book/1.html", 1, 0.1, "2026-01-01", "2026-01-01", 1);
        var deleted = active with { DeletedAt = DateTimeOffset.Parse("2026-01-05Z") };

        var once = SyncMergePlanner.Merge([active], [deleted]);
        var twice = SyncMergePlanner.Merge(once, [active]);

        Assert.IsNotNull(twice.Single().DeletedAt);
        Assert.AreEqual(SyncSnapshotCodec.Encode(new SyncSnapshot { Device = "windows", UpdatedAt = DateTimeOffset.UnixEpoch, Books = once.ToList() }),
            SyncSnapshotCodec.Encode(new SyncSnapshot { Device = "windows", UpdatedAt = DateTimeOffset.UnixEpoch, Books = twice.ToList() }));
    }

    [TestMethod]
    public void SnapshotV1DecodesAndV2EncodesChapterIndex()
    {
        var v1 = SyncSnapshotCodec.Decode("""
            {"format":"yyreader-sync","version":1,"device":"mac","updatedAt":"2026-01-01T00:00:00Z","books":[
              {"sourceURL":"https://example.com/book/","title":"书","author":"作者","currentChapterURL":"https://example.com/book/9.html","paragraphIndex":2,"progress":0.2,"updatedAt":"2026-01-01T00:00:00Z"}
            ]}
            """);

        Assert.AreEqual(1, v1.Version);
        Assert.IsNull(v1.Books.Single().CurrentChapterIndex);
        var encoded = SyncSnapshotCodec.Encode(new SyncSnapshot
        {
            Device = "windows",
            UpdatedAt = DateTimeOffset.UnixEpoch,
            Books = [v1.Books.Single() with { CurrentChapterIndex = 9 }]
        });
        var v2 = SyncSnapshotCodec.Decode(encoded);
        Assert.AreEqual(2, v2.Version);
        Assert.AreEqual(9, v2.Books.Single().CurrentChapterIndex);
    }

    [TestMethod]
    public void SameChapterOnlyMovesForwardRegardlessOfTimestamp()
    {
        var behindButNewer = Book("https://example.com/book/", "书", "https://example.com/book/9.html", 4, 0.2, "2026-01-01", "2026-01-05", 9);
        var aheadButOlder = Book("https://example.com/book/", "书", "https://example.com/book/9.html", 40, 0.8, "2026-01-01", "2026-01-04", 9);

        var merged = SyncMergePlanner.Merge([behindButNewer], [aheadButOlder]).Single();

        Assert.AreEqual(40, merged.ParagraphIndex);
        Assert.AreEqual(0.8, merged.Progress);
        Assert.AreEqual(DateTimeOffset.Parse("2026-01-05"), merged.LastReadAt);
    }

    [TestMethod]
    public async Task EngineReadsOnlyMacAndAtomicallyWritesWindowsSnapshot()
    {
        var root = Path.Combine(Path.GetTempPath(), $"yyreader-sync-{Guid.NewGuid():N}");
        Directory.CreateDirectory(root);
        try
        {
            var syncDirectory = SyncEngine.ResolveSyncDirectory(root);
            Directory.CreateDirectory(syncDirectory);
            await File.WriteAllTextAsync(Path.Combine(syncDirectory, SyncEngine.MacFileName), SyncSnapshotCodec.Encode(
                new SyncSnapshot { Device = "mac", UpdatedAt = DateTimeOffset.UtcNow, Books = [Book("https://example.com/book/", "书", "https://example.com/book/1.html", 1, 0.1, "2026-01-01", "2026-01-01")] }));
            SyncSnapshot? received = null;
            var engine = new SyncEngine(
                _ => Task.FromResult(new SyncSnapshot { Device = "windows", UpdatedAt = DateTimeOffset.UtcNow }),
                (snapshot, _) => { received = snapshot; return Task.FromResult(SyncApplicationResult.None); });

            await engine.SynchronizeAsync(root);

            Assert.AreEqual("mac", received!.Device);
            Assert.IsTrue(File.Exists(Path.Combine(syncDirectory, SyncEngine.WindowsFileName)));
            Assert.AreEqual(0, Directory.GetFiles(syncDirectory, "*.tmp").Length);
        }
        finally
        {
            if (Directory.Exists(root)) Directory.Delete(root, recursive: true);
        }
    }

    [TestMethod]
    public async Task EngineDoesNotRewriteEquivalentWindowsSnapshot()
    {
        var root = Path.Combine(Path.GetTempPath(), $"yyreader-sync-noop-{Guid.NewGuid():N}");
        Directory.CreateDirectory(root);
        try
        {
            var book = Book("https://example.com/book/", "书", "https://example.com/book/9.html", 3, 0.4, "2026-01-01", "2026-01-02");
            var call = 0;
            var engine = new SyncEngine(
                _ => Task.FromResult(new SyncSnapshot
                {
                    Device = "windows",
                    UpdatedAt = DateTimeOffset.Parse($"2026-01-0{++call + 2}Z"),
                    Books = [book]
                }),
                (_, _) => Task.FromResult(SyncApplicationResult.None));

            var first = await engine.SynchronizeAsync(root);
            var path = Path.Combine(SyncEngine.ResolveSyncDirectory(root), SyncEngine.WindowsFileName);
            var original = await File.ReadAllTextAsync(path);
            var second = await engine.SynchronizeAsync(root);

            Assert.IsTrue(first.WindowsFileWritten);
            Assert.IsFalse(second.WindowsFileWritten);
            Assert.AreEqual(original, await File.ReadAllTextAsync(path));
        }
        finally
        {
            if (Directory.Exists(root)) Directory.Delete(root, recursive: true);
        }
    }

    [TestMethod]
    public async Task EngineUpgradesOwnedV1SnapshotToV2()
    {
        var root = Path.Combine(Path.GetTempPath(), $"yyreader-sync-upgrade-{Guid.NewGuid():N}");
        var directory = SyncEngine.ResolveSyncDirectory(root);
        Directory.CreateDirectory(directory);
        try
        {
            var book = Book("https://example.com/book/", "书", "https://example.com/book/9.html", 3, 0.4, "2026-01-01", "2026-01-02", 9);
            var v1Json = SyncSnapshotCodec.Encode(new SyncSnapshot
            {
                Version = 1,
                Device = "windows",
                UpdatedAt = DateTimeOffset.UnixEpoch,
                Books = [book with { CurrentChapterIndex = null }]
            });
            var path = Path.Combine(directory, SyncEngine.WindowsFileName);
            await File.WriteAllTextAsync(path, v1Json);
            var engine = new SyncEngine(
                _ => Task.FromResult(new SyncSnapshot { Device = "windows", UpdatedAt = DateTimeOffset.UtcNow, Books = [book] }),
                (_, _) => Task.FromResult(SyncApplicationResult.None));

            var result = await engine.SynchronizeAsync(root);

            Assert.IsTrue(result.WindowsFileWritten);
            var upgraded = SyncSnapshotCodec.Decode(await File.ReadAllTextAsync(path));
            Assert.AreEqual(2, upgraded.Version);
            Assert.AreEqual(9, upgraded.Books.Single().CurrentChapterIndex);
        }
        finally
        {
            if (Directory.Exists(root)) Directory.Delete(root, recursive: true);
        }
    }

    private static SyncSnapshotBook Book(
        string source,
        string title,
        string chapter,
        int index,
        double progress,
        string updated,
        string read,
        int? chapterIndex = null) => new()
    {
        SourceUrl = source,
        Title = title,
        Author = "作者",
        CurrentChapterUrl = chapter,
        CurrentChapterIndex = chapterIndex,
        ParagraphIndex = index,
        Progress = progress,
        UpdatedAt = DateTimeOffset.Parse(updated),
        LastReadAt = DateTimeOffset.Parse(read)
    };
}
