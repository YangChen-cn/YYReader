import Foundation

/// Revalidate the current DOM outside the UI actor. Bookmarks use reader indices;
/// advertising nodes inserted elsewhere in the document cannot shift them.
actor MangaBlobRegionLocator {
    struct Location: Sendable {
        let domIndex: Int
        let pageCount: Int
        let nodeID: String
        let expectedBlobURL: String
        let directURL: URL?
    }
    func locate(_ source: MangaBlobSource, in loaded: LoadedHTML) throws -> Location {
        try Task.checkCancellation()
        guard URLCanonicalizer.canonicalString(loaded.finalURL.absoluteString) == source.chapterURL.absoluteString,
              let region = try GenericMangaAdapter().recognizeChapter(loaded),
              region.imageURLs.indices.contains(source.index) else { throw NovelParsingError.noMangaImages }
        let url = region.imageURLs[source.index]
        let direct = !region.needsBrowser[source.index] && ["http", "https"].contains(url.scheme ?? "") ? url : nil
        return Location(domIndex: region.domIndices[source.index], pageCount: region.imageURLs.count, nodeID: region.domNodeIDs[source.index],
                        expectedBlobURL: url.scheme == "blob" ? url.absoluteString : "", directURL: direct)
    }
}
