import Foundation

@MainActor
final class HybridHTMLLoader: HTMLDocumentLoading {
    private let staticLoader: any StaticHTMLLoading
    private let webKitLoader: any BrowserHTMLLoading
    private(set) var browserPreferredHosts: Set<String> = []

    init(staticLoader: any StaticHTMLLoading, webKitLoader: any BrowserHTMLLoading) {
        self.staticLoader = staticLoader
        self.webKitLoader = webKitLoader
    }

    func beginOperation() {
        webKitLoader.beginOperation()
    }

    func load(_ url: URL) async throws -> LoadedHTML {
        guard let host = url.host?.lowercased(), !host.isEmpty else {
            throw NovelParsingError.unsupportedURL
        }
        if browserPreferredHosts.contains(host) {
            return try await webKitLoader.load(url)
        }
        do {
            return try await staticLoader.load(url)
        } catch HTMLLoadError.verificationRequired {
            browserPreferredHosts.insert(host)
            return try await webKitLoader.load(url)
        }
    }

    func isBrowserPreferred(_ host: String) -> Bool {
        browserPreferredHosts.contains(host.lowercased())
    }
}
