enum BookshelfTransferPlanner {
    static func preview(
        document: BookshelfTransferDocument,
        existingSourceURLs: Set<String>
    ) -> BookshelfTransferPreview {
        let existing = Set(existingSourceURLs.map(URLCanonicalizer.canonicalString))
        var seen: Set<String> = []
        var entries: [BookshelfTransferPreviewEntry] = []

        for book in document.books {
            if let error = BookshelfTransferCodec.validationError(for: book) {
                entries.append(.init(book: book, status: .invalid, error: error))
                continue
            }

            let key = URLCanonicalizer.canonicalString(book.sourceURL)
            if !seen.insert(key).inserted {
                entries.append(.init(
                    book: book,
                    status: .duplicateInFile,
                    error: "同一个文件中已经出现过相同 sourceURL。"
                ))
            } else if existing.contains(key) {
                entries.append(.init(book: book, status: .existing, error: nil))
            } else {
                entries.append(.init(book: book, status: .new, error: nil))
            }
        }

        return BookshelfTransferPreview(
            entries: entries,
            newCount: entries.count { $0.status == .new },
            existingCount: entries.count { $0.status == .existing },
            invalidCount: entries.count { $0.status == .invalid },
            duplicateCount: entries.count { $0.status == .duplicateInFile }
        )
    }
}
