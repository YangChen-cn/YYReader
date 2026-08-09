import Foundation
@testable import YYReader

@MainActor
final class MockHTMLLoader: HTMLDocumentLoading {
    private let documents: [URL: String]
    private let delay: Duration?
    private(set) var requestedURLs: [URL] = []

    init(documents: [URL: String], delay: Duration? = nil) {
        self.documents = documents
        self.delay = delay
    }

    func load(_ url: URL) async throws -> LoadedHTML {
        requestedURLs.append(url)
        if let delay { try await Task.sleep(for: delay) }
        guard let html = documents[url] else { throw HTMLLoadError.httpStatus(404) }
        return LoadedHTML(requestedURL: url, finalURL: url, html: html, retrievalKind: .urlSession)
    }
}
