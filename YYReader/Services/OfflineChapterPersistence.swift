import Foundation
import SwiftData

@ModelActor
actor OfflineChapterPersistence {
    func persist(_ result: ChapterLoadResult, chapterID: UUID, cachedAt: Date) throws {
        let descriptor = FetchDescriptor<Chapter>(predicate: #Predicate { $0.id == chapterID })
        guard let chapter = try modelContext.fetch(descriptor).first else { return }
        chapter.book?.resolvedContentType = result.imageURLs.isEmpty ? BookContentType.novel.rawValue : BookContentType.manga.rawValue
        chapter.title = result.title
        chapter.replaceBodyText(result.bodyText)
        chapter.replaceImages(result.imageURLs)
        chapter.imagesCachedAt = result.imageURLs.isEmpty ? nil : cachedAt
        chapter.previousURL = result.previousChapterURL?.absoluteString
        chapter.nextURL = result.nextChapterURL?.absoluteString
        chapter.cachedAt = cachedAt
        try modelContext.save()
    }

    func bodyText(chapterID: UUID) throws -> String? {
        let descriptor = FetchDescriptor<Chapter>(predicate: #Predicate { $0.id == chapterID })
        return try modelContext.fetch(descriptor).first?.bodyText
    }

    func cacheEntries() throws -> [LocalBookCacheEntry] {
        // A fresh context observes cache writes from the main context and downloads.
        let context = ModelContext(modelContainer)
        return try context.fetch(FetchDescriptor<Book>()).filter { $0.sourceKind == .web }.map { book in
            LocalBookCacheEntry(id: book.id, title: book.title, isManga: book.isManga,
                textBytes: book.chapters.reduce(0) { $0 + ($1.bodyText?.utf8.count ?? 0) },
                imageURLs: book.chapters.flatMap(\.imageSourceURLs).compactMap(URL.init(string:)))
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    func clearBodyText(chapterIDs: [UUID]) throws {
        let ids = Set(chapterIDs)
        let descriptor = FetchDescriptor<Chapter>()
        for chapter in try modelContext.fetch(descriptor) where ids.contains(chapter.id) {
            chapter.replaceBodyText(nil)
            chapter.replaceImages([])
            chapter.cachedAt = nil
        }
        try modelContext.save()
    }
}
