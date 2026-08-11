struct BookshelfTransferImportSummary: Equatable, Sendable {
    let succeeded: Int
    let skipped: Int
    let failed: Int
    let failures: [String]
}
