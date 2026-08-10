import Foundation

@MainActor
protocol HTMLDocumentLoading {
    func beginOperation()
    func load(_ url: URL) async throws -> LoadedHTML
}

/// Provides a rendered-DOM retry for pages whose server HTML does not contain readable content.
@MainActor
protocol RenderedDOMFallbackLoading: HTMLDocumentLoading {
    func loadRenderedDOM(_ url: URL) async throws -> LoadedHTML
}

extension HTMLDocumentLoading {
    func beginOperation() {}
}
