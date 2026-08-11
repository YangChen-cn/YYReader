import Foundation

@MainActor
final class ChapterParagraphCache {
    private struct Key: Hashable {
        let chapterID: UUID
        let cachedAt: Date?
        let contentRevision: Int
    }

    private struct Value {
        let paragraphs: [String]
        var accessOrder: UInt64
    }

    let capacity: Int
    private var values: [Key: Value] = [:]
    private var accessOrder: UInt64 = 0

    init(capacity: Int = 8) {
        self.capacity = max(capacity, 1)
    }

    func paragraphs(for chapter: Chapter) -> [String] {
        let key = Key(
            chapterID: chapter.id,
            cachedAt: chapter.cachedAt,
            contentRevision: chapter.contentRevision
        )
        accessOrder &+= 1
        if var value = values[key] {
            value.accessOrder = accessOrder
            values[key] = value
            return value.paragraphs
        }

        values = values.filter { $0.key.chapterID != chapter.id }
        let paragraphs = chapter.paragraphs
        values[key] = Value(paragraphs: paragraphs, accessOrder: accessOrder)
        evictLeastRecentlyUsedIfNeeded()
        return paragraphs
    }

    func removeAll() {
        values.removeAll(keepingCapacity: true)
    }

    var count: Int { values.count }

    private func evictLeastRecentlyUsedIfNeeded() {
        guard values.count > capacity,
              let oldestKey = values.min(by: { $0.value.accessOrder < $1.value.accessOrder })?.key else {
            return
        }
        values.removeValue(forKey: oldestKey)
    }
}
