using YYReader.Windows.Core.Models;

namespace YYReader.Windows.Core.Reading;

public enum NextChapterPreparationStatus
{
    LoadingNext,
    CheckingLatest,
    Ready,
    Attached,
    ConfirmedLatest,
    Failed
}

public sealed record NextChapterPreparationResult(
    NextChapterPreparationStatus Status,
    Chapter? Chapter = null,
    string? Message = null);
