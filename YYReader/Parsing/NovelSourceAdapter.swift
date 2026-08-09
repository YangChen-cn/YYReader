import Foundation

protocol NovelSourceAdapter: Sendable {
    func canHandle(_ document: LoadedHTML) -> Bool
    func parseChapterPage(_ document: LoadedHTML) throws -> ParsedChapterPage
    func parseCatalogPage(_ document: LoadedHTML) throws -> ParsedBookCatalog
}
