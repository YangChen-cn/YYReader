using System.Text;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using YYReader.Windows.Core.Models;
using YYReader.Windows.Core.Parsing;
using YYReader.Windows.Core.Persistence;
using YYReader.Windows.Core.Reading;
using YYReader.Windows.Core.Services;
using YYReader.Windows.Core.Sync;
using YYReader.Windows.Core.Transfer;
using YYReader.Windows.Services;

namespace YYReader.Windows.Tests;

[TestClass]
public sealed class LocalTextTests
{
    private static LocalTextImportDraft Draft(string text = "第一章 起点\n自造第一段\n自造第二段\n第二章 终点\n自造第三段\n自造第四段") =>
        LocalTextImportService.Prepare(Encoding.UTF8.GetBytes(text), "测试书");

    [TestMethod]
    public void IdentityMatchesMacGoldenVectorAndDoesNotUseFilename()
    {
        var a = LocalTextImportService.Prepare("abc"u8.ToArray(), "文件甲");
        var b = LocalTextImportService.Prepare("abc"u8.ToArray(), "文件乙");
        Assert.AreEqual("yyreader-local://txt/6b1696d3895ebe8ca5de53c421913cae72d95dbf6150df64260081c60ea4793c", a.SourceBookUrl);
        Assert.AreEqual(a.SourceBookUrl, b.SourceBookUrl);
        Assert.AreNotEqual(a.SourceBookUrl, Draft("abcd").SourceBookUrl);
        Assert.AreEqual(a.SourceBookUrl + "/chapter/000001", a.Chapters.Single().SourceUrl);
    }

    [TestMethod]
    public void StrictEncodingsAndWhitespacePreserveText()
    {
        const string text = "甲：全角Ａ。\r\n\r\n\r\n乙！\r丙？";
        var utf8 = LocalTextImportService.Prepare(Encoding.UTF8.GetBytes(text), "书");
        var bom = LocalTextImportService.Prepare(new byte[] { 0xef, 0xbb, 0xbf }.Concat(Encoding.UTF8.GetBytes(text)).ToArray(), "书");
        Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);
        var gb = LocalTextImportService.Prepare(Encoding.GetEncoding(54936).GetBytes(text), "书");
        Assert.AreEqual("UTF-8 BOM", bom.Encoding);
        Assert.AreEqual("GB18030 / GBK", gb.Encoding);
        Assert.AreEqual(utf8.Chapters[0].BodyText, gb.Chapters[0].BodyText);
        CollectionAssert.AreEqual(new[] { "甲：全角Ａ。", "乙！", "丙？" }, bom.Chapters[0].Paragraphs.ToArray());
        Assert.ThrowsException<InvalidDataException>(() => LocalTextImportService.Prepare([], "空"));
        Assert.ThrowsException<InvalidDataException>(() => LocalTextImportService.Prepare([0xff], "坏编码"));
        Assert.ThrowsException<InvalidDataException>(() => Draft(" \n \ufeff "));
        Assert.ThrowsException<OperationCanceledException>(() => LocalTextImportService.Prepare("abc"u8.ToArray(), "书", new CancellationToken(true)));
    }

    [DataTestMethod]
    [DataRow("第 １２ 章：起点")]
    [DataRow("第一回")]
    [DataRow("第两百节·续篇")]
    [DataRow("第一卷")]
    [DataRow("序章")]
    [DataRow("序言")]
    [DataRow("楔子")]
    [DataRow("引子")]
    [DataRow("尾声")]
    [DataRow("后记")]
    [DataRow("番外")]
    [DataRow("番外１２")]
    [DataRow("卷二—标题")]
    public void RecognizesWholeLineHeadings(string title) => Assert.IsTrue(LocalTextImportService.IsTitle(title));

    [TestMethod]
    public void SplittingUsesFileOrderAndReliabilityThreshold()
    {
        Assert.IsFalse(LocalTextImportService.IsTitle("正文提到第一章，继续叙述。"));
        Assert.IsFalse(LocalTextImportService.IsTitle("第一章 标题。"));
        Assert.AreEqual("正文", Draft("第一章\n一行正文").Chapters.Single().Title);
        Assert.AreEqual("第一章", Draft("第一章\n第一段\n第二段").Chapters.Single().Title);
        Assert.AreEqual("第一章", Draft("第一章\n" + new string('字', 200)).Chapters.Single().Title);
        Assert.AreEqual("正文", Draft(string.Join('\n', Enumerable.Repeat("前置行", 20)) + "\n第一章\n甲\n乙").Chapters.Single().Title);
        var split = Draft("前言甲\n前言乙\n第十章\n正文甲\n第一章\n正文乙\n尾声");
        CollectionAssert.AreEqual(new[] { "前言", "第十章", "第一章" }, split.Chapters.Select(c => c.Title).ToArray());
        Assert.AreEqual("短前置", Draft("短前置\n第一章\n甲\n第二章\n乙").Chapters[0].Paragraphs[0]);
        Assert.IsNull(split.Chapters[^1].NextUrl);
        Assert.AreEqual(split.Chapters[0].SourceUrl, split.Chapters[1].PreviousUrl);
    }

    [TestMethod]
    public async Task FileImportSurvivesSourceRemovalAndReimportPreservesPosition()
    {
        var folder = NewFolder();
        try
        {
            var path = Path.Combine(folder, "测试.txt");
            await File.WriteAllTextAsync(path, "第一章\n甲\n乙\n第二章\n丙\n丁");
            var draft = await LocalTextImportService.PrepareAsync(path);
            File.Delete(path);
            await Assert.ThrowsExceptionAsync<InvalidDataException>(() => LocalTextImportService.PrepareAsync(Path.Combine(folder, "book.pdf")));
            var repo = new SqliteLibraryRepository(Path.Combine(folder, "library.db"));
            await repo.InitializeAsync();
            var book = await repo.ImportLocalTextAsync(draft, "书名", "作者");
            await repo.SaveProgressAsync(book.Id, draft.Chapters[1].SourceUrl, 1, .7, DateTimeOffset.UtcNow);
            var repeated = await repo.ImportLocalTextAsync(draft, "修改书名", "作者");
            Assert.AreEqual(book.Id, repeated.Id);
            Assert.AreEqual(draft.Chapters[1].SourceUrl, repeated.CurrentChapterUrl);
            Assert.AreEqual(1, repeated.CurrentChapter!.ParagraphIndex);
            Assert.AreEqual(.7, repeated.CurrentChapter.Progress);
            await repo.ClearChapterBodiesAsync(book.Id);
            Assert.AreEqual(draft.Chapters[1].BodyText, await repo.LoadChapterBodyAsync(book.Id, draft.Chapters[1].SourceUrl));
            Assert.IsTrue(repeated.HasCatalog);
            await repo.DeleteBookAsync(book.Id);
            Assert.IsNotNull((await repo.BuildSyncSnapshotAsync("windows")).Books.Single().DeletedAt);
            await repo.ImportLocalTextAsync(draft, "复活", "作者");
            Assert.IsNull((await repo.BuildSyncSnapshotAsync("windows")).Books.Single().DeletedAt);
        }
        finally { DeleteFolder(folder); }
    }

    [TestMethod]
    public async Task LocalPlaceholderHydratesInPlaceAndNeverLoadsNetwork()
    {
        var folder = NewFolder();
        try
        {
            var repo = new SqliteLibraryRepository(Path.Combine(folder, "library.db"));
            await repo.InitializeAsync();
            var draft = Draft();
            await repo.ApplySyncSnapshotAsync(new SyncSnapshot { Device = "mac", Books = [new SyncSnapshotBook {
                SourceUrl = draft.SourceBookUrl, Title = draft.Title, CurrentChapterUrl = draft.Chapters[1].SourceUrl,
                CurrentChapterIndex = 2, ParagraphIndex = 99, Progress = .8, LastReadAt = DateTimeOffset.UtcNow, UpdatedAt = DateTimeOffset.UtcNow }] });
            var loader = new RejectNetworkLoader();
            var coordinator = new NovelImportCoordinator(loader);
            await using var store = new LibraryStore(repo, coordinator);
            await store.InitializeAsync();
            var placeholder = store.Books.Single();
            Assert.IsFalse(placeholder.HasCatalog);
            store.SelectBook(placeholder);
            Assert.IsFalse(await store.EnsureSelectedChapterLoadedAsync());
            Assert.AreEqual("请在此设备导入同一 TXT", store.ErrorMessage);
            Assert.IsFalse(await store.RefreshCatalogAsync(placeholder));
            Assert.IsFalse(await store.PrepareOfflineDownloadAsync(placeholder, OfflineDownloadScope.AllChapters));
            var manager = new OfflineDownloadManager(repo, coordinator);
            await Assert.ThrowsExceptionAsync<InvalidOperationException>(() => manager.DownloadAsync(placeholder, placeholder.CurrentChapter!, OfflineDownloadScope.AllChapters));
            await Assert.ThrowsExceptionAsync<InvalidOperationException>(() => manager.ClearOfflineCacheAsync(placeholder));
            await store.ImportLocalTextAsync(draft, draft.Title, "作者");
            Assert.AreEqual(placeholder.Id, store.SelectedBook!.Id);
            Assert.AreEqual(1, store.SelectedChapter!.ParagraphIndex);
            Assert.IsTrue(await store.EnsureSelectedChapterLoadedAsync());
            Assert.AreEqual(NextChapterPreparationStatus.ConfirmedLatest, (await store.PrepareNextChapterAsync()).Status);
            await store.SelectChapterAsync(store.SelectedBook.Chapters[0]);
            var next = await store.PrepareNextChapterAsync();
            Assert.AreEqual(NextChapterPreparationStatus.Ready, next.Status);
            Assert.IsTrue(store.AttachPreparedNextChapter(draft.Chapters[0].SourceUrl, next.Chapter!));
            Assert.AreEqual(0, loader.Calls);
        }
        finally { DeleteFolder(folder); }
    }

    [TestMethod]
    public async Task PlaceholderCanAlignByOneBasedSortIndex()
    {
        var folder = NewFolder();
        try
        {
            var repo = new SqliteLibraryRepository(Path.Combine(folder, "library.db"));
            await repo.InitializeAsync();
            var draft = Draft();
            await repo.ApplySyncSnapshotAsync(new SyncSnapshot { Books = [new SyncSnapshotBook {
                SourceUrl = draft.SourceBookUrl, CurrentChapterUrl = draft.SourceBookUrl + "/chapter/000099",
                CurrentChapterIndex = 2, ParagraphIndex = 1, Progress = .5, LastReadAt = DateTimeOffset.UtcNow, UpdatedAt = DateTimeOffset.UtcNow }] });
            var imported = await repo.ImportLocalTextAsync(draft, "书", "作者");
            Assert.AreEqual(2, imported.Chapters.Count);
            Assert.AreEqual(draft.Chapters[1].SourceUrl, imported.CurrentChapterUrl);
            Assert.AreEqual(1, imported.CurrentChapter!.ParagraphIndex);
            Assert.AreEqual(.5, imported.CurrentChapter.Progress);
        }
        finally { DeleteFolder(folder); }
    }

    [TestMethod]
    public void StrictLocalUrlsAreAcceptedOnlyForTheirOwnBook()
    {
        var draft = Draft();
        var entry = new SyncSnapshotBook { SourceUrl = draft.SourceBookUrl, CurrentChapterUrl = draft.Chapters[0].SourceUrl };
        var json = SyncSnapshotCodec.Encode(new SyncSnapshot { Books = [entry] });
        Assert.AreEqual(1, SyncSnapshotCodec.Decode(json).Books.Count);
        Assert.IsNull(BookshelfTransferCodec.ValidateBook(new BookshelfTransferBook { SourceUrl = entry.SourceUrl, CurrentChapterUrl = entry.CurrentChapterUrl }));
        foreach (var bad in new[] { draft.SourceBookUrl + "/", draft.SourceBookUrl + "?x=1", "yyreader-local://txt/abc" })
            Assert.ThrowsException<SyncSnapshotException>(() => SyncSnapshotCodec.Decode(SyncSnapshotCodec.Encode(new SyncSnapshot { Books = [entry with { SourceUrl = bad }] })));
        foreach (var bad in new[] { "https://example.com/1", Draft("other").Chapters[0].SourceUrl, draft.SourceBookUrl + "/chapter/1" })
            Assert.ThrowsException<SyncSnapshotException>(() => SyncSnapshotCodec.Decode(SyncSnapshotCodec.Encode(new SyncSnapshot { Books = [entry with { CurrentChapterUrl = bad }] })));
    }

    [TestMethod]
    public async Task CapabilityNegotiationFiltersBothActiveRecordsAndTombstones()
    {
        var folder = NewFolder();
        try
        {
            var draft = Draft();
            var snapshot = new SyncSnapshot { Books = [new SyncSnapshotBook { SourceUrl = draft.SourceBookUrl },
                new SyncSnapshotBook { SourceUrl = Draft("deleted").SourceBookUrl, DeletedAt = DateTimeOffset.UtcNow },
                new SyncSnapshotBook { SourceUrl = "https://example.com/book/" }] };
            var engine = new SyncEngine(_ => Task.FromResult(snapshot), (_, _) => Task.FromResult(SyncApplicationResult.None));
            var first = await engine.PublishLocalAsync(folder);
            Assert.AreEqual(1, first.Snapshot.Books.Count);
            CollectionAssert.Contains(first.Snapshot.Capabilities, LocalTextIdentity.Capability);
            var macPath = Path.Combine(folder, "YYReaderSync", "mac.json");
            await File.WriteAllTextAsync(macPath, SyncSnapshotCodec.Encode(new SyncSnapshot { Device = "mac" }));
            Assert.AreEqual(1, (await engine.SynchronizeAsync(folder)).Snapshot.Books.Count);
            await File.WriteAllTextAsync(macPath, SyncSnapshotCodec.Encode(new SyncSnapshot { Device = "mac", Capabilities = [LocalTextIdentity.Capability, "future-v3"] }));
            Assert.AreEqual(3, (await engine.SynchronizeAsync(folder)).Snapshot.Books.Count);
            Assert.IsFalse((await engine.PublishLocalAsync(folder)).WindowsFileWritten);
            var json = await File.ReadAllTextAsync(Path.Combine(folder, "YYReaderSync", "windows.json"));
            Assert.IsFalse(json.Contains("BodyText", StringComparison.OrdinalIgnoreCase));
            await File.WriteAllTextAsync(macPath, "invalid");
            await Assert.ThrowsExceptionAsync<SyncSnapshotException>(() => engine.SynchronizeAsync(folder));
            Assert.AreEqual(1, (await engine.PublishLocalAsync(folder)).Snapshot.Books.Count);
        }
        finally { DeleteFolder(folder); }
    }

    private sealed class RejectNetworkLoader : IHtmlDocumentLoader
    {
        public int Calls { get; private set; }
        public void BeginOperation() { Calls++; }
        public Task<LoadedHtml> LoadAsync(Uri url, CancellationToken cancellationToken = default) { Calls++; throw new InvalidOperationException("本地书禁止联网"); }
    }

    private static string NewFolder() { var path = Path.Combine(Path.GetTempPath(), "yyreader-local-tests-" + Guid.NewGuid().ToString("N")); Directory.CreateDirectory(path); return path; }
    private static void DeleteFolder(string path) { Microsoft.Data.Sqlite.SqliteConnection.ClearAllPools(); Directory.Delete(path, true); }
}
