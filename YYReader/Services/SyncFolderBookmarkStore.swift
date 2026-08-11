import Foundation

@MainActor
struct SyncFolderBookmarkStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func save(_ url: URL) throws {
        let data = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        defaults.set(data, forKey: SyncPreferenceKeys.bookmark)
    }

    func resolve() throws -> URL? {
        guard let data = defaults.data(forKey: SyncPreferenceKeys.bookmark) else { return nil }
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        if isStale {
            try save(url)
        }
        return url
    }
}
