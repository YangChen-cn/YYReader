import Foundation

@MainActor
protocol HTMLDocumentLoading {
    func beginOperation()
    func load(_ url: URL) async throws -> LoadedHTML
}

extension HTMLDocumentLoading {
    func beginOperation() {}
}
