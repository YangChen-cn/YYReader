import Foundation

enum SyncMerger {
    typealias ChapterRanksByBook = [String: [String: Int]]

    static func merge(
        _ records: [SyncBookRecord],
        chapterRanksByBook: ChapterRanksByBook = [:]
    ) -> [SyncBookRecord] {
        let grouped = Dictionary(grouping: records, by: \.canonicalSourceURL)
        return grouped.keys.sorted().compactMap { key in
            guard let candidates = grouped[key], !candidates.isEmpty else { return nil }
            return merge(
                candidates,
                canonicalSourceURL: key,
                chapterRanks: chapterRanksByBook[key] ?? [:]
            )
        }
    }

    private static func merge(
        _ records: [SyncBookRecord],
        canonicalSourceURL: String,
        chapterRanks: [String: Int]
    ) -> SyncBookRecord {
        let metadata = records.max(by: metadataPrecedes) ?? records[0]
        let reading = records.max { lhs, rhs in
            readingPrecedes(lhs, rhs, chapterRanks: chapterRanks)
        } ?? records[0]
        let newestDeletion = records.compactMap(\.deletedAt).max()
        let activeDeletion = newestDeletion.flatMap { $0 >= metadata.updatedAt ? $0 : nil }
        let canonicalChapterURL = reading.currentChapterURL.map(URLCanonicalizer.canonicalChapterString)

        return SyncBookRecord(
            sourceURL: canonicalSourceURL,
            title: metadata.title,
            author: metadata.author,
            currentChapterURL: canonicalChapterURL,
            currentChapterIndex: reading.currentChapterIndex
                ?? canonicalChapterURL.flatMap { chapterRanks[$0] },
            paragraphIndex: reading.paragraphIndex.map { max($0, 0) },
            progress: reading.progress.map { min(max($0, 0), 1) },
            // Timestamp is informational only; it must not move reading position.
            lastReadAt: records.compactMap(\.lastReadAt).max(),
            updatedAt: metadata.updatedAt,
            deletedAt: activeDeletion
        )
    }

    private static func metadataPrecedes(_ lhs: SyncBookRecord, _ rhs: SyncBookRecord) -> Bool {
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt < rhs.updatedAt }
        return metadataTieBreaker(lhs) < metadataTieBreaker(rhs)
    }

    private static func readingPrecedes(
        _ lhs: SyncBookRecord,
        _ rhs: SyncBookRecord,
        chapterRanks: [String: Int]
    ) -> Bool {
        let lhsURL = lhs.currentChapterURL.map(URLCanonicalizer.canonicalChapterString)
        let rhsURL = rhs.currentChapterURL.map(URLCanonicalizer.canonicalChapterString)

        if lhsURL == rhsURL {
            let lhsParagraph = lhs.paragraphIndex ?? -1
            let rhsParagraph = rhs.paragraphIndex ?? -1
            if lhsParagraph != rhsParagraph { return lhsParagraph < rhsParagraph }

            let lhsProgress = lhs.progress ?? -1
            let rhsProgress = rhs.progress ?? -1
            if lhsProgress != rhsProgress { return lhsProgress < rhsProgress }
        } else {
            let lhsIndex = effectiveChapterIndex(lhs, canonicalURL: lhsURL, chapterRanks: chapterRanks)
            let rhsIndex = effectiveChapterIndex(rhs, canonicalURL: rhsURL, chapterRanks: chapterRanks)
            if lhsIndex != rhsIndex { return lhsIndex < rhsIndex }
        }
        return readingTieBreaker(lhs) < readingTieBreaker(rhs)
    }

    private static func effectiveChapterIndex(
        _ record: SyncBookRecord,
        canonicalURL: String?,
        chapterRanks: [String: Int]
    ) -> Int {
        if let currentChapterIndex = record.currentChapterIndex {
            return currentChapterIndex
        }
        if let canonicalURL, let rank = chapterRanks[canonicalURL] {
            return rank
        }
        return -1
    }

    private static func metadataTieBreaker(_ record: SyncBookRecord) -> String {
        "\(record.title)\u{0}\(record.author)\u{0}\(record.sourceURL)"
    }

    private static func readingTieBreaker(_ record: SyncBookRecord) -> String {
        "\(record.currentChapterURL ?? "")\u{0}\(record.currentChapterIndex ?? -1)\u{0}\(record.paragraphIndex ?? -1)\u{0}\(record.progress ?? -1)"
    }
}
