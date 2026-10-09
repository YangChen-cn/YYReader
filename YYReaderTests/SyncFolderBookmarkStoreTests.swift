import Foundation
import Synchronization
import Testing
@testable import YYReader

private final class ScopedFolderProbe: Sendable {
    private let counts = Mutex<[URL: Int]>([:])

    func start(_ url: URL) -> Bool {
        counts.withLock { $0[url, default: 0] += 1 }
        return true
    }

    func stop(_ url: URL) {
        counts.withLock { $0[url, default: 0] -= 1 }
    }

    func count(_ url: URL) -> Int { counts.withLock { $0[url, default: 0] } }

    func bookmark(_ url: URL) throws -> Data {
        // Model a File Provider which reports "missing" until access is granted.
        guard count(url) > 0, url.lastPathComponent != "missing" else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        return Data(url.lastPathComponent.utf8)
    }
}

struct SyncFolderBookmarkStoreTests {
    @Test
    func savingBookmarkActivatesProviderAccessAndBalancesRelease() async throws {
        let probe = ScopedFolderProbe()
        let url = URL(fileURLWithPath: "/provider/folder")
        let store = SyncFolderBookmarkStore(startAccess: { probe.start($0) }, stopAccess: { probe.stop($0) },
                                            bookmarkData: { try probe.bookmark($0) })
        #expect(try await store.saveAndStartAccess(to: url) == Data("folder".utf8))
        #expect(probe.count(url) == 1)
        await store.stopAccessing()
        #expect(probe.count(url) == 0)
    }

    @Test
    func failedFolderChangeReleasesNewScopeAndKeepsPreviousAccess() async throws {
        let probe = ScopedFolderProbe()
        let first = URL(fileURLWithPath: "/provider/folder")
        let missing = URL(fileURLWithPath: "/provider/missing")
        let store = SyncFolderBookmarkStore(startAccess: { probe.start($0) }, stopAccess: { probe.stop($0) },
                                            bookmarkData: { try probe.bookmark($0) })
        _ = try await store.saveAndStartAccess(to: first)
        await #expect(throws: CocoaError.self) { try await store.saveAndStartAccess(to: missing) }
        #expect(probe.count(first) == 1)
        #expect(probe.count(missing) == 0)
        await store.stopAccessing()
        #expect(probe.count(first) == 0)
    }

    @Test
    func cancelledBookmarkCreationDoesNotLeakPermission() async {
        let probe = ScopedFolderProbe()
        let url = URL(fileURLWithPath: "/provider/folder")
        let store = SyncFolderBookmarkStore(startAccess: { probe.start($0) }, stopAccess: { probe.stop($0) },
                                            bookmarkData: { _ in throw CancellationError() })
        await #expect(throws: CancellationError.self) { try await store.saveAndStartAccess(to: url) }
        #expect(probe.count(url) == 0)
    }
}
