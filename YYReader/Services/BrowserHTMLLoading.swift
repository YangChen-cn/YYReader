import Foundation

@MainActor
protocol BrowserHTMLLoading: AnyObject {
    func beginOperation()
    func load(_ url: URL) async throws -> LoadedHTML
}
