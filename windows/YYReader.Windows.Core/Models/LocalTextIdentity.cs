using System.Text.RegularExpressions;

namespace YYReader.Windows.Core.Models;

public static class LocalTextIdentity
{
    public const string Capability = "local-txt-v1";
    public static bool IsBook(string value) => Regex.IsMatch(value, @"\Ayyreader-local://txt/[0-9a-fA-F]{64}\z");
    public static bool IsChapter(string value) => Regex.IsMatch(value, @"\Ayyreader-local://txt/[0-9a-fA-F]{64}/chapter/[0-9]{6}\z");
    public static bool IsChapterOf(string chapter, string book) => IsBook(book) && IsChapter(chapter)
        && chapter.StartsWith(book + "/chapter/", StringComparison.OrdinalIgnoreCase);
}
