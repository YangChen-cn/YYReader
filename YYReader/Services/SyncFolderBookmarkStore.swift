import Foundation

struct SyncFolderAccess: Sendable {
    let url: URL
    let refreshedBookmarkData: Data?
}

protocol SyncFolderBookmarkAccessing: Actor {
    func saveAndStartAccess(to url: URL) async throws -> Data
    func resolveAndStartAccess(from data: Data) async throws -> SyncFolderAccess
    func stopAccessing() async
}

actor SyncFolderBookmarkStore: SyncFolderBookmarkAccessing {
    private var accessedURL: URL?
    private var isAccessing = false

    func saveAndStartAccess(to url: URL) async throws -> Data {
        let data = try makeBookmark(for: url)
        replaceAccess(with: url)
        return data
    }

    func resolveAndStartAccess(from data: Data) async throws -> SyncFolderAccess {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: Self.resolutionOptions,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        let refreshedBookmarkData = isStale ? try makeBookmark(for: url) : nil
        replaceAccess(with: url)
        return SyncFolderAccess(url: url, refreshedBookmarkData: refreshedBookmarkData)
    }

    func stopAccessing() async {
        if isAccessing {
            accessedURL?.stopAccessingSecurityScopedResource()
        }
        accessedURL = nil
        isAccessing = false
    }

    private func makeBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: Self.creationOptions,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    private static var resolutionOptions: URL.BookmarkResolutionOptions {
        #if os(macOS)
        .withSecurityScope
        #else
        []
        #endif
    }

    private static var creationOptions: URL.BookmarkCreationOptions {
        #if os(macOS)
        .withSecurityScope
        #else
        .minimalBookmark
        #endif
    }

    private func replaceAccess(with url: URL) {
        if isAccessing {
            accessedURL?.stopAccessingSecurityScopedResource()
        }
        accessedURL = url
        isAccessing = url.startAccessingSecurityScopedResource()
    }
}
