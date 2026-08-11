import Foundation

enum URLCanonicalizer {
    static func canonicalString(_ value: String) -> String {
        guard let url = URL(string: value),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased() else {
            return value
        }

        components.scheme = scheme
        components.host = components.host?.lowercased()
        components.fragment = nil
        if (scheme == "http" && components.port == 80)
            || (scheme == "https" && components.port == 443) {
            components.port = nil
        }
        if components.path.isEmpty {
            components.path = "/"
        }
        return components.url?.absoluteString ?? value
    }

    static func canonicalChapterString(_ value: String) -> String {
        let canonical = canonicalString(value)
        guard let url = URL(string: canonical),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return canonical
        }
        components.path = components.path.replacingOccurrences(
            of: "^(.*\\/\\d+\\/\\d+)\\/\\d+\\.html$",
            with: "$1.html",
            options: .regularExpression
        )
        return components.url?.absoluteString ?? canonical
    }

    static func isValidBookSource(_ value: String) -> Bool {
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased() else { return false }
        return ["http", "https", "yyreader-book"].contains(scheme)
    }

    static func isValidChapterSource(_ value: String) -> Bool {
        guard let scheme = URL(string: value)?.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }
}
