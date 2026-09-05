import Foundation

enum BookSourceKind: Equatable, Sendable {
    case web
    case localText
    case placeholder

    static func resolve(_ sourceURL: String) -> Self {
        guard let url = URL(string: sourceURL) else { return .placeholder }
        switch url.scheme?.lowercased() {
        case "http", "https":
            return .web
        case "yyreader-local" where url.host?.lowercased() == "txt":
            return .localText
        default:
            return .placeholder
        }
    }
}
