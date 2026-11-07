import Foundation

@MainActor
final class TavernReadingPlanCache {
    private struct Key: Hashable {
        let id: UUID
        let revision: Int
        let cachedAt: Date?
    }
    private var values: [Key: TavernReadingPlan] = [:]
    private var recency: [Key] = []

    func plan(chapter: Chapter, paragraphs: [String]) -> TavernReadingPlan {
        let key = Key(id: chapter.id, revision: chapter.contentRevision, cachedAt: chapter.cachedAt)
        if let cached = values[key] { return cached }
        let plan = TavernTextParser.parse(paragraphs)
        guard !paragraphs.isEmpty else { return plan }
        let obsolete = recency.filter { $0.id == chapter.id }
        for key in obsolete { values.removeValue(forKey: key) }
        recency.removeAll { $0.id == chapter.id }
        values[key] = plan
        recency.append(key)
        while recency.count > 8 { values.removeValue(forKey: recency.removeFirst()) }
        return plan
    }
}
