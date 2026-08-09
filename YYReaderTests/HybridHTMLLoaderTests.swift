import Foundation
import Testing
@testable import YYReader

@MainActor
struct HybridHTMLLoaderTests {
    @Test
    func challengePromotesHostAndRoutesLaterPagesThroughBrowser() async throws {
        let first = try #require(URL(string: "https://novel.example/book/1.html"))
        let second = try #require(URL(string: "https://novel.example/book/1/2.html"))
        let staticLoader = StaticLoaderSpy(results: [
            first: .failure(.verificationRequired)
        ])
        let browserLoader = BrowserLoaderSpy()
        let loader = HybridHTMLLoader(staticLoader: staticLoader, webKitLoader: browserLoader)

        _ = try await loader.load(first)
        _ = try await loader.load(second)

        #expect(loader.isBrowserPreferred("novel.example"))
        #expect(await staticLoader.requestedURLs() == [first])
        #expect(browserLoader.urls == [first, second])
    }

    @Test
    func beginOperationKeepsHostBrowserPreferred() async throws {
        let first = try #require(URL(string: "https://novel.example/book/1.html"))
        let nextImport = try #require(URL(string: "https://novel.example/book/2.html"))
        let staticLoader = StaticLoaderSpy(results: [first: .failure(.verificationRequired)])
        let browserLoader = BrowserLoaderSpy()
        let loader = HybridHTMLLoader(staticLoader: staticLoader, webKitLoader: browserLoader)

        _ = try await loader.load(first)
        loader.beginOperation()
        _ = try await loader.load(nextImport)

        #expect(await staticLoader.requestedURLs() == [first])
        #expect(browserLoader.urls == [first, nextImport])
        #expect(browserLoader.beginOperationCount == 1)
    }

    @Test
    func webKitLoaderRetainsOneSessionPerHostAcrossOperations() throws {
        let loader = WebKitHTMLLoader(limiter: HostRateLimiter(defaultMinimumDelay: .zero))
        let first = try #require(URL(string: "https://novel.example/book/1.html"))
        let second = try #require(URL(string: "https://novel.example/book/2.html"))

        let session1 = try #require(loader.hostSession(for: first))
        loader.beginOperation()
        let session2 = try #require(loader.hostSession(for: second))

        #expect(session1 === session2)
        #expect(loader.sessionCount == 1)
    }
}

private actor StaticLoaderSpy: StaticHTMLLoading {
    private let results: [URL: Result<LoadedHTML, HTMLLoadError>]
    private var urls: [URL] = []

    init(results: [URL: Result<LoadedHTML, HTMLLoadError>]) {
        self.results = results
    }

    func load(_ url: URL) async throws -> LoadedHTML {
        urls.append(url)
        if let result = results[url] { return try result.get() }
        return LoadedHTML(requestedURL: url, finalURL: url, html: "<html></html>", retrievalKind: .urlSession)
    }

    func requestedURLs() -> [URL] { urls }
}

@MainActor
private final class BrowserLoaderSpy: BrowserHTMLLoading {
    private(set) var urls: [URL] = []
    private(set) var beginOperationCount = 0

    func beginOperation() {
        beginOperationCount += 1
    }

    func load(_ url: URL) async throws -> LoadedHTML {
        urls.append(url)
        return LoadedHTML(requestedURL: url, finalURL: url, html: "<html></html>", retrievalKind: .webKit)
    }
}
