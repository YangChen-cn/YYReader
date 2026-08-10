import Foundation

enum ReaderSelectionRestoration {
    static func selection(
        persistedBookID: String,
        persistedChapterID: String,
        sceneBookID: String,
        sceneChapterID: String
    ) -> (bookID: UUID?, chapterID: UUID?) {
        if let bookID = UUID(uuidString: persistedBookID) {
            return (bookID, UUID(uuidString: persistedChapterID))
        }
        return (UUID(uuidString: sceneBookID), UUID(uuidString: sceneChapterID))
    }
}
