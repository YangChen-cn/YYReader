struct BookshelfTransferPreviewEntry: Equatable, Sendable {
    let book: BookshelfTransferBook
    let status: BookshelfTransferEntryStatus
    let error: String?
}
