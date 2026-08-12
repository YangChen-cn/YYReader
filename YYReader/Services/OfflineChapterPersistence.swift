import Foundation
import SwiftData

@ModelActor
actor OfflineChapterPersistence {
    func persist(_ result: ChapterLoadResult, chapterID: UUID, cachedAt: Date) throws {
        let descriptor = FetchDescriptor<Chapter>(predicate: #Predicate { $0.id == chapterID })
        guard let chapter = try modelContext.fetch(descriptor).first else { return }
        chapter.title = result.title
        chapter.replaceBodyText(result.bodyText)
        chapter.previousURL = result.previousChapterURL?.absoluteString
        chapter.nextURL = result.nextChapterURL?.absoluteString
        chapter.cachedAt = cachedAt
        try modelContext.save()
    }

    func bodyText(chapterID: UUID) throws -> String? {
        let descriptor = FetchDescriptor<Chapter>(predicate: #Predicate { $0.id == chapterID })
        return try modelContext.fetch(descriptor).first?.bodyText
    }

    func clearBodyText(chapterIDs: [UUID]) throws {
        let ids = Set(chapterIDs)
        let descriptor = FetchDescriptor<Chapter>()
        for chapter in try modelContext.fetch(descriptor) where ids.contains(chapter.id) {
            chapter.replaceBodyText(nil)
            chapter.cachedAt = nil
        }
        try modelContext.save()
    }
}
