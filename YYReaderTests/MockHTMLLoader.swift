import Foundation
@testable import YYReader

@MainActor
final class MockHTMLLoader: HTMLDocumentLoading {
    private let documents: [URL: String]
    private let delay: Duration?
    private var remainingFailures: [URL: Int]
    private(set) var requestedURLs: [URL] = []
    private(set) var requestedPriorities: [TaskPriority] = []
    private(set) var maximumConcurrentLoadCount = 0
    private var activeLoadCount = 0

    init(
        documents: [URL: String],
        delay: Duration? = nil,
        failuresBeforeSuccess: [URL: Int] = [:]
    ) {
        self.documents = documents
        self.delay = delay
        self.remainingFailures = failuresBeforeSuccess
    }

    func load(_ url: URL) async throws -> LoadedHTML {
        requestedURLs.append(url)
        requestedPriorities.append(Task.currentPriority)
        activeLoadCount += 1
        maximumConcurrentLoadCount = max(maximumConcurrentLoadCount, activeLoadCount)
        defer { activeLoadCount -= 1 }
        if let delay { try await Task.sleep(for: delay) }
        if let failures = remainingFailures[url], failures > 0 {
            remainingFailures[url] = failures - 1
            throw HTMLLoadError.httpStatus(503)
        }
        guard let html = documents[url] else { throw HTMLLoadError.httpStatus(404) }
        return LoadedHTML(requestedURL: url, finalURL: url, html: html, retrievalKind: .urlSession)
    }
}
