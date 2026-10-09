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
    private let startAccess: @Sendable (URL) -> Bool
    private let stopAccess: @Sendable (URL) -> Void
    private let bookmarkData: @Sendable (URL) throws -> Data

    init(
        startAccess: @escaping @Sendable (URL) -> Bool = { $0.startAccessingSecurityScopedResource() },
        stopAccess: @escaping @Sendable (URL) -> Void = { $0.stopAccessingSecurityScopedResource() },
        bookmarkData: (@Sendable (URL) throws -> Data)? = nil
    ) {
        self.startAccess = startAccess
        self.stopAccess = stopAccess
        self.bookmarkData = bookmarkData ?? { url in
            try url.bookmarkData(options: Self.creationOptions, includingResourceValuesForKeys: nil, relativeTo: nil)
        }
    }

    func saveAndStartAccess(to url: URL) async throws -> Data {
        try Task.checkCancellation()
        // A document picker's URL must be activated before even creating its
        // bookmark. Otherwise File Providers can report an existing folder as missing.
        let started = startAccess(url)
        do {
            let data = try bookmarkData(url)
            try Task.checkCancellation()
            replaceAccess(with: url, started: started)
            return data
        } catch {
            if started { stopAccess(url) }
            throw error
        }
    }

    func resolveAndStartAccess(from data: Data) async throws -> SyncFolderAccess {
        try Task.checkCancellation()
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: Self.resolutionOptions,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        let started = startAccess(url)
        do {
            let refreshedBookmarkData = isStale ? try bookmarkData(url) : nil
            try Task.checkCancellation()
            replaceAccess(with: url, started: started)
            return SyncFolderAccess(url: url, refreshedBookmarkData: refreshedBookmarkData)
        } catch {
            if started { stopAccess(url) }
            throw error
        }
    }

    func stopAccessing() async {
        if isAccessing {
            if let accessedURL { stopAccess(accessedURL) }
        }
        accessedURL = nil
        isAccessing = false
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

    private func replaceAccess(with url: URL, started: Bool) {
        if isAccessing {
            if let accessedURL { stopAccess(accessedURL) }
        }
        accessedURL = url
        isAccessing = started
    }
}
