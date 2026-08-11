struct BookshelfTransferPreview: Equatable, Sendable {
    let entries: [BookshelfTransferPreviewEntry]
    let newCount: Int
    let existingCount: Int
    let invalidCount: Int
    let duplicateCount: Int

    var totalCount: Int { entries.count }
}
