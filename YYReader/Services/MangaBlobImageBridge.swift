import Foundation

/// A narrow main-actor bridge to the existing browser session. Image bytes are
/// decoded and cached by MangaImageCache, outside the UI actor.
@MainActor
final class MangaBlobImageBridge {
    static let shared = MangaBlobImageBridge()
    weak var loader: WebKitHTMLLoader?

    func readImage(_ imageURL: URL, chapterURL: URL) async throws -> MangaImageReadResult {
        try Task.checkCancellation()
        guard let loader else { throw HTMLLoadError.invalidResponse }
        let source = MangaBlobSource(url: imageURL)
        guard source != nil || DuokanMangaAdapter.supports(chapterURL) else { throw HTMLLoadError.invalidResponse }
        if let source, !Self.isSameSite(source.chapterURL, chapterURL) {
            throw HTMLLoadError.invalidResponse
        }
        return try await loader.readMangaImage(imageURL, chapterURL: source?.chapterURL ?? chapterURL)
    }

    /// The blob reference stores the address the page was parsed at, while the
    /// chapter keeps the address it was imported from. An http→https upgrade, a
    /// `www.`/`m.` prefix or a redirect in between must not reject every page of
    /// the chapter, so hosts are compared after dropping that prefix.
    private static func isSameSite(_ lhs: URL, _ rhs: URL) -> Bool {
        func host(_ url: URL) -> String {
            var value = url.host?.lowercased() ?? ""
            for prefix in ["www.", "m."] where value.hasPrefix(prefix) {
                value = String(value.dropFirst(prefix.count))
            }
            return value
        }
        let left = host(lhs)
        let right = host(rhs)
        guard !left.isEmpty, !right.isEmpty else { return false }
        return left == right || left.hasSuffix("." + right) || right.hasSuffix("." + left)
    }
}
