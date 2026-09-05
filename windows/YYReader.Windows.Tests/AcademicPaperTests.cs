using Microsoft.VisualStudio.TestTools.UnitTesting;
using YYReader.Windows.Core.Reading;
using YYReader.Windows.Core.Models;
using YYReader.Windows.Views;

namespace YYReader.Windows.Tests;

[TestClass]
public sealed class AcademicPaperTests
{
    [TestMethod]
    public void PresentationChangesAndAppendKeepEveryOriginalAnchorExactlyOnce()
    {
        var session = new ContinuousReaderSession();
        var chapter = new Chapter("https://example.com/book/3.html", "第三章", 3,
            string.Join('\n', Enumerable.Range(0, 60).Select(i => $"正文 {i}")));
        session.Reset(chapter);
        var normal = ReaderItemBuilder.Build(session.Entries);
        var paper = ReaderItemBuilder.Build(session.Entries, "https://example.com/book/");
        foreach (var paragraph in normal.Where(p => p.IsParagraph))
        {
            var matching = paper.Where(p => p.ContainsParagraph(paragraph.ParagraphIndex)).ToArray();
            Assert.AreEqual(1, matching.Length);
            Assert.AreEqual(paragraph.Text, matching[0].PaperPlan!.Paragraphs[paragraph.ParagraphIndex].Text);
            var anchor = new ReaderAnchor(paragraph.ChapterUrl, paragraph.ParagraphIndex).Normalized(60);
            Assert.AreEqual(paragraph.ParagraphIndex, anchor.ParagraphIndex);
        }
        foreach (var block in paper.Where(p => p.Kind == ReaderItemKind.AcademicBlock))
        {
            var indices = Enumerable.Range(block.ParagraphIndex, block.EndParagraphIndex - block.ParagraphIndex).ToArray();
            var columns = indices.GroupBy(i => block.ColumnForParagraph(i, true, 900)).OrderBy(g => g.Key).SelectMany(g => g).ToArray();
            CollectionAssert.AreEqual(indices, columns, "每块完整左栏后完整右栏，保持段落序");
            Assert.IsTrue(indices.All(i => block.ColumnForParagraph(i, true, 759) == 0));
            Assert.IsTrue(indices.All(i => block.ColumnForParagraph(i, false, 900) == 0));
        }
        Assert.IsTrue(paper.Where(p => p.Supplement is not null).All(p => !p.IsParagraph && !p.ContainsParagraph(0)));
        Assert.IsTrue(session.AttachNext(new Chapter("https://example.com/book/4.html", "第四章", 4, "续章甲\n续章乙")));
        var appended = paper.Concat(ReaderItemBuilder.BuildEntry(session.Entries[^1], "https://example.com/book/")).ToArray();
        var rebuilt = ReaderItemBuilder.Build(session.Entries, "https://example.com/book/");
        CollectionAssert.AreEqual(rebuilt.Select(p => (p.ChapterUrl, p.Kind, p.ParagraphIndex)).ToArray(), appended.Select(p => (p.ChapterUrl, p.Kind, p.ParagraphIndex)).ToArray());
    }

    [TestMethod]
    public void PlanMatchesMacGoldenVectorAndPreservesOriginalParagraphs()
    {
        var paragraphs = Enumerable.Range(0, 60).Select(i => $"自造测试段落 {i}。").ToArray();
        var plan = AcademicPaperPlanner.MakePlan("https://example.com/book/", "https://example.com/book/3.html", 2, paragraphs);
        Assert.AreEqual("Contextual Dynamics in Long-Form Textual Corpora", plan.Title);
        Assert.AreEqual("3. Results and Discussion", plan.SectionTitle);
        CollectionAssert.AreEqual(new[] { 5, 10, 15, 20, 23, 28, 31, 36, 39, 44, 47, 50, 55, 59 }, plan.Paragraphs.Where(p => p.Citations.Count > 0).Select(p => p.Index).ToArray());
        CollectionAssert.AreEqual(new[] { "10 figure", "21 equation", "38 figure", "55 table" }, plan.Supplements.Select(s => $"{s.Index} {s.Kind}").ToArray());
        CollectionAssert.AreEqual(paragraphs, plan.Paragraphs.Select(p => p.Text).ToArray());
        var repeat = AcademicPaperPlanner.MakePlan("https://example.com/book/", "https://example.com/book/3.html", 2, paragraphs);
        Assert.AreEqual(System.Text.Json.JsonSerializer.Serialize(plan), System.Text.Json.JsonSerializer.Serialize(repeat));
    }

    [TestMethod]
    public void AllPlansRespectIntervalsAndSectionMapping()
    {
        for (var position = 0; position < 10; position++)
        {
            var plan = AcademicPaperPlanner.MakePlan("https://example.com/book/", $"https://example.com/book/{position}.html", position, Enumerable.Repeat("正文", 100).ToArray());
            var citations = plan.Paragraphs.Where(p => p.Citations.Count > 0).Select(p => p.Index).ToArray();
            Assert.IsTrue(citations.Zip(citations.Skip(1)).All(p => p.Second - p.First is >= 3 and <= 5));
            Assert.IsTrue(plan.Supplements.Zip(plan.Supplements.Skip(1)).All(p => p.Second.Index - p.First.Index is >= 10 and <= 18));
            Assert.IsTrue(plan.Paragraphs.SelectMany(p => p.Citations).All(c => c is >= 1 and <= 18));
            if (position > 2) Assert.AreEqual($"3.{position - 2} Extended Analysis", plan.SectionTitle);
        }
    }
}
