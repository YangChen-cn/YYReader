using System.Buffers.Binary;
using System.Security.Cryptography;
using System.Text;
using YYReader.Windows.Core.Models;

namespace YYReader.Windows.Core.Reading;

public sealed record AcademicParagraph(int Index, string Text, IReadOnlyList<int> Citations);
public sealed record AcademicSupplement(int Index, string Kind, int Number);
public sealed record AcademicPaperPlan(string Title, string Abstract, string Keywords, string SectionTitle,
    IReadOnlyList<AcademicParagraph> Paragraphs, IReadOnlyList<AcademicSupplement> Supplements);

public static class AcademicPaperPlanner
{
    private static readonly string[] Titles = [
            "A Structured Analysis of Sequential Narrative Systems",
            "Contextual Dynamics in Long-Form Textual Corpora",
            "An Empirical Study of Narrative State Transitions",
            "Representation and Continuity in Textual Systems"
    ];
    private static readonly string[] Abstracts = [
            "This paper examines a sequential textual corpus through a reproducible structural framework. The analysis emphasizes continuity, contextual transition, and locally observable evidence.",
            "We present a deterministic reading of a long-form corpus. The method preserves source material while organizing observations into a conventional academic structure.",
            "This study investigates narrative progression using stable textual units. Results indicate that local context and ordered evidence remain central to interpretation."
    ];
    private static readonly string[] Keywords = [
            "textual analysis; sequential systems; contextual evidence",
            "narrative structure; corpus reading; deterministic layout",
            "long-form text; continuity; representation"
    ];
    public static int StableNumber(string seed, int upperBound) => (int)(BinaryPrimitives.ReadUInt64BigEndian(SHA256.HashData(Encoding.UTF8.GetBytes(seed))) % (ulong)upperBound);

    public static AcademicPaperPlan MakePlan(string bookIdentity, string chapterIdentity, int chapterPosition, IReadOnlyList<string> paragraphs)
    {
        var seed = UrlCanonicalizer.Canonicalize(bookIdentity).AbsoluteUri + "|" + chapterIdentity;
        int Hash(string key, int count) => StableNumber(seed + "|" + key, count);
        var planned = new List<AcademicParagraph>();
        var nextCitation = 3 + Hash("citation-start", 3);
        for (var i = 0; i < paragraphs.Count; i++)
        {
            int[] citations = [];
            if (i == nextCitation)
            {
                citations = Enumerable.Range(0, 1 + Hash($"citation-count|{i}", 3)).Select(n => 1 + Hash($"citation|{i}|{n}", 18)).Order().ToArray();
                nextCitation += 3 + Hash($"citation-gap|{i}", 3);
            }
            planned.Add(new(i, paragraphs[i], citations));
        }
        var supplements = new List<AcademicSupplement>();
        var next = 10 + Hash("supplement-start", 9);
        while (next < paragraphs.Count)
        {
            supplements.Add(new(next, new[] { "equation", "table", "figure" }[Hash($"supplement-kind|{next}", 3)], supplements.Count + 1));
            next += 10 + Hash($"supplement-gap|{next}", 9);
        }
        var section = chapterPosition switch { 0 => "1. Introduction", 1 => "2. Methodology", 2 => "3. Results and Discussion", _ => $"3.{chapterPosition - 2} Extended Analysis" };
        return new(Titles[Hash("title", Titles.Length)], Abstracts[Hash("abstract", Abstracts.Length)], Keywords[Hash("keywords", Keywords.Length)], section, planned, supplements);
    }
}
