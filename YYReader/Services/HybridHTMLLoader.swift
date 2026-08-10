import Foundation

@MainActor
final class HybridHTMLLoader: RenderedDOMFallbackLoading {
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

    func loadRenderedDOM(_ url: URL) async throws -> LoadedHTML {
        guard url.host?.isEmpty == false else {
            throw NovelParsingError.unsupportedURL
        }
        return try await webKitLoader.load(url)
    }

    func promoteRenderedDOMHost(for url: URL) {
        guard let host = url.host?.lowercased(), !host.isEmpty else { return }
        browserPreferredHosts.insert(host)
    }
}
