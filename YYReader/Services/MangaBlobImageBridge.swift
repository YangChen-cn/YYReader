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
        if let source, !HTMLParsingSupport.isSameOrigin(source.chapterURL, as: chapterURL) {
            throw HTMLLoadError.invalidResponse
        }
        return try await loader.readMangaImage(imageURL, chapterURL: source?.chapterURL ?? chapterURL)
    }
}
