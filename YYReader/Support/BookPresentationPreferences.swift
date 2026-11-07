import Foundation

enum BookPresentationPreferences {
    static func resolve(sourceURL: String?, data: Data, globalMode: String, isTavern: Bool) -> ReaderPresentationMode {
        if let sourceURL,
           let value = values(data)[sourceURL], let saved = ReaderPresentationMode(rawValue: value) {
            return saved
        }
        if sourceURL != nil, isTavern { return .sillyTavern }
        // Older versions wrote auto-detected Tavern mode into the global key.
        // That value cannot safely become the default for unrelated books.
        let fallback = ReaderPresentationMode(rawValue: globalMode) ?? .normal
        return sourceURL != nil && fallback == .sillyTavern ? .normal : fallback
    }

    static func setting(_ mode: ReaderPresentationMode, sourceURL: String, data: Data) -> Data {
        var preferences = values(data)
        preferences[sourceURL] = mode.rawValue
        return (try? JSONEncoder().encode(preferences)) ?? data
    }

    private static func values(_ data: Data) -> [String: String] {
        (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }
}
