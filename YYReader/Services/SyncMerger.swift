import Foundation

enum SyncMerger {
    static func merge(_ records: [SyncBookRecord]) -> [SyncBookRecord] {
        let grouped = Dictionary(grouping: records, by: \.canonicalSourceURL)
        return grouped.keys.sorted().compactMap { key in
            guard let candidates = grouped[key], !candidates.isEmpty else { return nil }
            return merge(candidates, canonicalSourceURL: key)
        }
    }

    private static func merge(
        _ records: [SyncBookRecord],
        canonicalSourceURL: String
    ) -> SyncBookRecord {
        let metadata = records.max(by: metadataPrecedes) ?? records[0]
        let reading = records.max(by: readingPrecedes) ?? records[0]
        let newestDeletion = records.compactMap(\.deletedAt).max()
        let activeDeletion = newestDeletion.flatMap { $0 >= metadata.updatedAt ? $0 : nil }

        return SyncBookRecord(
            sourceURL: canonicalSourceURL,
            title: metadata.title,
            author: metadata.author,
            currentChapterURL: reading.currentChapterURL.map(URLCanonicalizer.canonicalChapterString),
            paragraphIndex: reading.paragraphIndex.map { max($0, 0) },
            progress: reading.progress.map { min(max($0, 0), 1) },
            lastReadAt: reading.lastReadAt,
            updatedAt: metadata.updatedAt,
            deletedAt: activeDeletion
        )
    }

    private static func metadataPrecedes(_ lhs: SyncBookRecord, _ rhs: SyncBookRecord) -> Bool {
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt < rhs.updatedAt }
        return metadataTieBreaker(lhs) < metadataTieBreaker(rhs)
    }

    private static func readingPrecedes(_ lhs: SyncBookRecord, _ rhs: SyncBookRecord) -> Bool {
        let lhsDate = lhs.lastReadAt ?? .distantPast
        let rhsDate = rhs.lastReadAt ?? .distantPast
        if lhsDate != rhsDate { return lhsDate < rhsDate }
        return readingTieBreaker(lhs) < readingTieBreaker(rhs)
    }

    private static func metadataTieBreaker(_ record: SyncBookRecord) -> String {
        "\(record.title)\u{0}\(record.author)\u{0}\(record.sourceURL)"
    }

    private static func readingTieBreaker(_ record: SyncBookRecord) -> String {
        "\(record.currentChapterURL ?? "")\u{0}\(record.paragraphIndex ?? -1)\u{0}\(record.progress ?? -1)"
    }
}
