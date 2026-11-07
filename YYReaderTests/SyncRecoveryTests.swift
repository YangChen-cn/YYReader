import Foundation
import SwiftData
import Testing
@testable import YYReader

private actor RecoveryMemory: SyncRecoveryPersisting {
    var value: SyncRecoveryConfiguration?
    var failing = false
    init(_ value: SyncRecoveryConfiguration? = nil, failing: Bool = false) { self.value = value; self.failing = failing }
    func load() throws -> SyncRecoveryConfiguration? { if failing { throw CocoaError(.fileReadUnknown) }; return value }
    func save(_ configuration: SyncRecoveryConfiguration) throws { if failing { throw CocoaError(.fileWriteUnknown) }; value = configuration }
    func clear() { value = nil }
}

private actor RecoveryBookmark: SyncFolderBookmarkAccessing {
    let folder: URL
    let failing: Bool
    init(folder: URL, failing: Bool = false) { self.folder = folder; self.failing = failing }
    func saveAndStartAccess(to url: URL) -> Data { Data([1]) }
    func resolveAndStartAccess(from data: Data) throws -> SyncFolderAccess {
        if failing { throw CocoaError(.fileReadUnknown) }
        return SyncFolderAccess(url: folder, refreshedBookmarkData: nil)
    }
    func stopAccessing() {}
}

@MainActor
struct SyncRecoveryTests {
    private func waitFor(_ predicate: () -> Bool) async throws {
        for _ in 0..<100 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(predicate())
    }
    private func library(_ sync: FolderSyncController) throws -> LibraryStore {
        let container = try ModelContainer(for: Book.self, Chapter.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return LibraryStore(modelContext: container.mainContext, coordinator: NovelImportCoordinator(loader: MockHTMLLoader(documents: [:])), folderSync: sync)
    }

    @Test func restoreEnabledFolderSynchronizesAndDisabledStaysDisabled() async throws {
        for enabled in [true, false] {
            let folder = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: folder) }
            let suite = "SyncRecovery-\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            let memory = RecoveryMemory(.init(bookmark: Data([1]), enabled: enabled, displayPath: folder.path))
            let sync = FolderSyncController(defaults: defaults, bookmarkStore: RecoveryBookmark(folder: folder), recoveryStore: memory)
            let store = try library(sync)
            sync.attach(to: store)
            try await waitFor { sync.hasSelectedFolder && (enabled ? sync.lastSyncAt != nil : !sync.isEnabled) }
            #expect(sync.isEnabled == enabled)
            if !enabled { #expect(sync.lastSyncAt == nil) }
            sync.isEnabled = false
        }
    }

    @Test func migratesLegacyOnlyAfterSuccessfulWriteAndUnbindClearsRecovery() async throws {
        let suite = "SyncRecovery-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data([2]), forKey: SyncPreferenceKeys.bookmark)
        defaults.set(false, forKey: SyncPreferenceKeys.enabled)
        let memory = RecoveryMemory()
        let sync = FolderSyncController(defaults: defaults, recoveryStore: memory)
        let store = try library(sync)
        sync.attach(to: store)
        try await waitFor { defaults.data(forKey: SyncPreferenceKeys.bookmark) == nil }
        #expect(try await memory.load()?.bookmark == Data([2]))
        #expect(try await memory.load()?.enabled == false)
        sync.forgetFolder()
        try await waitFor { !sync.hasSelectedFolder }
        #expect(try await memory.load() == nil)
        #expect(!sync.isEnabled)
    }

    @Test func failedMigrationAndUnavailableProviderRetainRecovery() async throws {
        let suite = "SyncRecovery-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data([3]), forKey: SyncPreferenceKeys.bookmark)
        let broken = FolderSyncController(defaults: defaults, recoveryStore: RecoveryMemory(failing: true))
        let first = try library(broken)
        broken.attach(to: first)
        try await waitFor { broken.errorMessage != nil }
        #expect(defaults.data(forKey: SyncPreferenceKeys.bookmark) == Data([3]))
        let recovery = RecoveryMemory(.init(bookmark: Data([4]), enabled: true, displayPath: "/cloud"))
        defaults.removeObject(forKey: SyncPreferenceKeys.bookmark)
        let unavailable = FolderSyncController(defaults: defaults, bookmarkStore: RecoveryBookmark(folder: URL(fileURLWithPath: "/cloud"), failing: true), recoveryStore: recovery)
        let second = try library(unavailable)
        unavailable.attach(to: second)
        try await waitFor { unavailable.errorMessage != nil }
        #expect(unavailable.hasSelectedFolder)
        #expect(try await recovery.load()?.bookmark == Data([4]))
        unavailable.isEnabled = false
    }

    #if os(iOS)
    @Test func realKeychainRoundTripAndSwitchState() async throws {
        let storage = SyncRecoveryStore(service: "com.yyreader.tests.\(UUID().uuidString)")
        let config = SyncRecoveryConfiguration(bookmark: Data([1, 2, 3]), enabled: true, displayPath: "/folder")
        try await storage.save(config)
        #expect(try await storage.load() == config)
        try await storage.save(.init(bookmark: config.bookmark, enabled: false, displayPath: config.displayPath))
        #expect(try await storage.load()?.enabled == false)
        try await storage.clear()
        #expect(try await storage.load() == nil)
    }
    #endif
}
