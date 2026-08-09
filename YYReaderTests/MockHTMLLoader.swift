import Foundation
@testable import YYReader

@MainActor
final class MockHTMLLoader: HTMLDocumentLoading {
    private let documents: [URL: String]

    init(documents: [URL: String]) {
        self.documents = documents
    }

    func load(_ url: URL) async throws -> LoadedHTML {
        guard let html = documents[url] else { throw HTMLLoadError.httpStatus(404) }
        return LoadedHTML(requestedURL: url, finalURL: url, html: html, retrievalKind: .urlSession)
    }
}
