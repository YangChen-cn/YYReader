import Foundation

@MainActor
final class AcademicPaperPlanCache {
    private struct Key: Hashable {
        let bookIdentity: String
        let chapterID: UUID
        let cachedAt: Date?
        let contentRevision: Int
        let chapterPosition: Int
    }

    private let capacity: Int
    private var values: [Key: AcademicPaperPlan] = [:]
    private var recency: [Key] = []

    init(capacity: Int = 8) {
        self.capacity = max(capacity, 1)
    }

    func plan(bookIdentity: String, chapter: Chapter, position: Int, paragraphs: [String]) -> AcademicPaperPlan {
        let key = Key(
            bookIdentity: bookIdentity,
            chapterID: chapter.id,
            cachedAt: chapter.cachedAt,
            contentRevision: chapter.contentRevision,
            chapterPosition: position
        )
        if let value = values[key], !value.paragraphs.isEmpty {
            touch(key)
            return value
        }
        let value = AcademicPaperPlanner.makePlan(
            bookIdentity: bookIdentity,
            chapterIdentity: chapter.sourceURL,
            chapterPosition: position,
            paragraphs: paragraphs
        )
        if !paragraphs.isEmpty {
            values[key] = value
            touch(key)
            while values.count > capacity, let oldest = recency.first {
                recency.removeFirst()
                values.removeValue(forKey: oldest)
            }
        }
        return value
    }

    func plan(book: Book, chapter: Chapter, position: Int, paragraphs: [String]) -> AcademicPaperPlan {
        plan(
            bookIdentity: book.sourceBookURL,
            chapter: chapter,
            position: position,
            paragraphs: paragraphs
        )
    }

    private func touch(_ key: Key) {
        recency.removeAll { $0 == key }
        recency.append(key)
    }
}
