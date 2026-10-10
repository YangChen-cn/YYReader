import Foundation

/// App-local identity. Never persist the webpage's temporary blob UUID.
struct MangaBlobSource: Sendable {
    let chapterURL: URL
    let index: Int

    init(chapterURL: URL, index: Int) {
        self.chapterURL = URL(string: URLCanonicalizer.canonicalString(chapterURL.absoluteString)) ?? chapterURL
        self.index = index
    }

    init?(url: URL) {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "yyreader-blob", parts.host == "image", parts.path.isEmpty,
              let items = parts.queryItems, items.count == 2,
              let chapter = items.first(where: { $0.name == "chapter" })?.value.flatMap(URL.init(string:)),
              ["http", "https"].contains(chapter.scheme?.lowercased() ?? ""), chapter.host != nil,
              let value = items.first(where: { $0.name == "index" })?.value,
              let index = Int(value), index >= 0 else { return nil }
        self.init(chapterURL: chapter, index: index)
    }

    var url: URL {
        var parts = URLComponents()
        parts.scheme = "yyreader-blob"; parts.host = "image"
        parts.queryItems = [URLQueryItem(name: "chapter", value: chapterURL.absoluteString),
                            URLQueryItem(name: "index", value: String(index))]
        return parts.url!
    }
}

enum MangaImageReadResult: Sendable {
    case encoded(String)
    case address(URL)
}
