import Foundation
@testable import YYReader

@MainActor
final class NonCooperativeHTMLLoader: HTMLDocumentLoading {
    private let documents: [URL: String]
    private let delays: [URL: Duration]

    init(documents: [URL: String], delays: [URL: Duration]) {
        self.documents = documents
        self.delays = delays
    }

    func load(_ url: URL) async throws -> LoadedHTML {
        if let delay = delays[url] {
            do {
                try await Task.sleep(for: delay)
            } catch is CancellationError {
                // Simulates a network or browser boundary that finishes even
                // after its caller has cancelled the surrounding operation.
            }
        }
        guard let html = documents[url] else { throw HTMLLoadError.httpStatus(404) }
        return LoadedHTML(
            requestedURL: url,
            finalURL: url,
            html: html,
            retrievalKind: .urlSession
        )
    }
}
