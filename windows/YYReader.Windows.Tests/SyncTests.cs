using Microsoft.VisualStudio.TestTools.UnitTesting;
using YYReader.Windows.Core.Sync;

namespace YYReader.Windows.Tests;

[TestClass]
public sealed class SyncTests
{
    [TestMethod]
    public void MergeUsesNewerMetadataAndReadingPositionIndependently()
    {
        var local = Book("https://EXAMPLE.com/book/", "旧标题", "第一章", 2, 0.2, "2026-01-01", "2026-01-04");
        var remote = Book("https://example.com/book/", "新标题", "第二章", 8, 0.8, "2026-01-03", "2026-01-02");

        var merged = SyncMergePlanner.Merge([local], [remote]).Single();

        Assert.AreEqual("新标题", merged.Title);
        Assert.AreEqual("第一章", merged.CurrentChapterUrl);
        Assert.AreEqual(2, merged.ParagraphIndex);
    }

    [TestMethod]
    public void TombstonePreventsStaleSnapshotFromRestoringBookAndMergeIsIdempotent()
    {
        var active = Book("https://example.com/book/", "书", "章", 1, 0.1, "2026-01-01", "2026-01-01");
        var deleted = active with { DeletedAt = DateTimeOffset.Parse("2026-01-05Z") };

        var once = SyncMergePlanner.Merge([active], [deleted]);
        var twice = SyncMergePlanner.Merge(once, [active]);

        Assert.IsNotNull(twice.Single().DeletedAt);
        Assert.AreEqual(SyncSnapshotCodec.Encode(new SyncSnapshot { Device = "windows", UpdatedAt = DateTimeOffset.UnixEpoch, Books = once.ToList() }),
            SyncSnapshotCodec.Encode(new SyncSnapshot { Device = "windows", UpdatedAt = DateTimeOffset.UnixEpoch, Books = twice.ToList() }));
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
                new SyncSnapshot { Device = "mac", UpdatedAt = DateTimeOffset.UtcNow, Books = [Book("https://example.com/book/", "书", "章", 1, 0.1, "2026-01-01", "2026-01-01")] }));
            SyncSnapshot? received = null;
            var engine = new SyncEngine(
                _ => Task.FromResult(new SyncSnapshot { Device = "windows", UpdatedAt = DateTimeOffset.UtcNow }),
                (snapshot, _) => { received = snapshot; return Task.CompletedTask; });

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

    private static SyncSnapshotBook Book(string source, string title, string chapter, int index, double progress, string updated, string read) => new()
    {
        SourceUrl = source,
        Title = title,
        Author = "作者",
        CurrentChapterUrl = chapter,
        ParagraphIndex = index,
        Progress = progress,
        UpdatedAt = DateTimeOffset.Parse(updated),
        LastReadAt = DateTimeOffset.Parse(read)
    };
}
