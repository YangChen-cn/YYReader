using YYReader.Windows.Core.Models;

namespace YYReader.Windows.Core.Reading;

public enum NextChapterPreparationStatus
{
    Attached,
    EndOfCatalog,
    Failed
}

public sealed record NextChapterPreparationResult(
    NextChapterPreparationStatus Status,
    Chapter? Chapter = null);
