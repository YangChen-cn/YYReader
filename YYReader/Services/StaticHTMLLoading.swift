import Foundation

protocol StaticHTMLLoading: Sendable {
    func load(_ url: URL) async throws -> LoadedHTML
}
