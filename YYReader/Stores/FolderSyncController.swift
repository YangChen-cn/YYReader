import Foundation
import Observation

@MainActor
@Observable
final class FolderSyncController {
    private var engine: SyncEngine
    private let defaults: UserDefaults
    private var bookmarkStore: any SyncFolderBookmarkAccessing
    private let monitor = SyncFolderMonitor()
    private weak var store: LibraryStore?
    private var bookmarkData: Data?
    private var selectedFolderURL: URL?
    private var persistedFolderDisplayPath: String?
    private var tombstones: [String: SyncBookRecord] = [:]
    private var debounceTask: Task<Void, Never>?
    private var syncTask: Task<Void, Never>?
    private var syncTimeoutTask: Task<Void, Never>?
    private var syncGeneration = UUID()
    private var pollingTask: Task<Void, Never>?
    private var windowsChangeCheckTask: Task<Void, Never>?
    private var windowsChangeTimeoutTask: Task<Void, Never>?
    private var windowsChangeGeneration = UUID()
    private var folderAccessTask: Task<Void, Never>?
    private var folderAccessTimeoutTask: Task<Void, Never>?
    private var folderAccessGeneration = UUID()
    private var lastWindowsFileSignature: SyncFileSignature?
    private var syncAgainAfterCurrentRun = false
    private var debounceShouldApplyMergedRecords = false
    private var queuedSyncShouldApplyMergedRecords = false

    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            defaults.set(isEnabled, forKey: SyncPreferenceKeys.enabled)
            isEnabled ? activate() : deactivate()
        }
    }
    private(set) var isSyncing = false
    private(set) var lastSyncAt: Date?
    private(set) var errorMessage: String?

    init(
        engine: SyncEngine = SyncEngine(),
        defaults: UserDefaults = .standard,
        bookmarkStore: (any SyncFolderBookmarkAccessing)? = nil
    ) {
        self.engine = engine
        self.defaults = defaults
        self.bookmarkStore = bookmarkStore ?? SyncFolderBookmarkStore()
        self.isEnabled = defaults.bool(forKey: SyncPreferenceKeys.enabled)
        self.lastSyncAt = defaults.object(forKey: SyncPreferenceKeys.lastSyncAt) as? Date
        self.tombstones = Self.loadTombstones(defaults: defaults)
        self.bookmarkData = defaults.data(forKey: SyncPreferenceKeys.bookmark)
        self.persistedFolderDisplayPath = defaults.string(forKey: SyncPreferenceKeys.folderDisplayPath)
    }

    var folderDisplayPath: String? {
        selectedFolderURL?.path(percentEncoded: false) ?? persistedFolderDisplayPath
    }

    var hasSelectedFolder: Bool {
        bookmarkData != nil
    }

    func attach(to store: LibraryStore) {
        self.store = store
        if isEnabled {
            // Defer permission restoration until the scene task has returned and
            // SwiftUI has had an opportunity to present the local library.
            Task { [weak self] in
                await Task.yield()
                self?.activate()
            }
        }
    }

    func chooseFolder() {
        guard let url = SyncFolderPicker.chooseFolder() else { return }
        folderAccessTask?.cancel()
        folderAccessTimeoutTask?.cancel()
        let generation = UUID()
        folderAccessGeneration = generation
        let bookmarkStore = SyncFolderBookmarkStore()
        beginFolderAccessTimeout(generation: generation)
        folderAccessTask = Task { [weak self] in
            guard let self else { return }
            defer { self.finishFolderAccessTask(generation: generation) }
            do {
                let data = try await bookmarkStore.saveAndStartAccess(to: url)
                guard !Task.isCancelled, self.folderAccessGeneration == generation else {
                    await bookmarkStore.stopAccessing()
                    return
                }
                let previousBookmarkStore = self.bookmarkStore
                self.bookmarkStore = bookmarkStore
                self.acceptFolderAccess(url: url, bookmarkData: data)
                Task {
                    await previousBookmarkStore.stopAccessing()
                }
                if !self.isEnabled {
                    self.isEnabled = true
                } else {
                    self.startPolling()
                    self.launchSync(applyMergedRecords: true)
                }
            } catch is CancellationError {
                return
            } catch {
                self.errorMessage = "无法保存同步文件夹权限：\(error.localizedDescription)"
            }
        }
    }

    func appBecameActive() {
        guard isEnabled, store != nil else { return }
        if selectedFolderURL != nil {
            syncNow()
        } else {
            restoreFolderAccess(shouldSynchronize: true)
        }
    }

    func scheduleLocalChange() {
        scheduleSync(after: .seconds(1.5), applyMergedRecords: false)
    }

    func progressDidPersist() {
        scheduleSync(after: .seconds(1.5), applyMergedRecords: false)
    }

    func recordDeletion(_ record: SyncBookRecord) {
        let key = record.canonicalSourceURL
        tombstones[key] = record
        persistTombstones()
    }

    func syncNow() {
        guard isEnabled else { return }
        debounceTask?.cancel()
        debounceTask = nil
        debounceShouldApplyMergedRecords = false
        if selectedFolderURL != nil {
            launchSync(applyMergedRecords: true)
        } else {
            restoreFolderAccess(shouldSynchronize: true)
        }
    }

    private func activate() {
        guard store != nil else { return }
        startPolling()
        restoreFolderAccess(shouldSynchronize: true)
    }

    private func deactivate() {
        debounceTask?.cancel()
        debounceTask = nil
        syncTask?.cancel()
        syncTask = nil
        syncTimeoutTask?.cancel()
        syncTimeoutTask = nil
        syncGeneration = UUID()
        pollingTask?.cancel()
        pollingTask = nil
        windowsChangeCheckTask?.cancel()
        windowsChangeCheckTask = nil
        windowsChangeTimeoutTask?.cancel()
        windowsChangeTimeoutTask = nil
        windowsChangeGeneration = UUID()
        folderAccessTask?.cancel()
        folderAccessTask = nil
        folderAccessTimeoutTask?.cancel()
        folderAccessTimeoutTask = nil
        folderAccessGeneration = UUID()
        Task {
            await monitor.stop()
        }
        Task {
            await bookmarkStore.stopAccessing()
        }
        selectedFolderURL = nil
        isSyncing = false
        syncAgainAfterCurrentRun = false
        debounceShouldApplyMergedRecords = false
        queuedSyncShouldApplyMergedRecords = false
    }

    private func restoreFolderAccess(shouldSynchronize: Bool) {
        guard selectedFolderURL == nil else {
            if shouldSynchronize {
                launchSync(applyMergedRecords: true)
            }
            return
        }
        guard folderAccessTask == nil else { return }
        guard let bookmarkData else {
            errorMessage = "请选择一个文件夹后再启用同步。"
            return
        }
        let generation = UUID()
        folderAccessGeneration = generation
        let bookmarkStore = self.bookmarkStore
        beginFolderAccessTimeout(generation: generation)
        folderAccessTask = Task { [weak self] in
            guard let self else { return }
            defer { self.finishFolderAccessTask(generation: generation) }
            do {
                let access = try await bookmarkStore.resolveAndStartAccess(from: bookmarkData)
                guard !Task.isCancelled,
                      self.isEnabled,
                      self.folderAccessGeneration == generation else {
                    await bookmarkStore.stopAccessing()
                    return
                }
                self.acceptFolderAccess(
                    url: access.url,
                    bookmarkData: access.refreshedBookmarkData ?? bookmarkData
                )
                if shouldSynchronize {
                    self.launchSync(applyMergedRecords: true)
                }
            } catch is CancellationError {
                return
            } catch {
                self.errorMessage = SyncError.folderUnavailable.localizedDescription
            }
        }
    }

    private func finishFolderAccessTask(generation: UUID) {
        guard folderAccessGeneration == generation else { return }
        folderAccessTimeoutTask?.cancel()
        folderAccessTimeoutTask = nil
        folderAccessTask = nil
    }

    private func beginFolderAccessTimeout(generation: UUID) {
        folderAccessTimeoutTask?.cancel()
        folderAccessTimeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(5))
            } catch {
                return
            }
            guard let self,
                  self.folderAccessGeneration == generation,
                  self.folderAccessTask != nil else { return }
            self.folderAccessGeneration = UUID()
            self.folderAccessTask?.cancel()
            self.folderAccessTask = nil
            self.folderAccessTimeoutTask = nil
            // A blocked File Provider call can keep its actor occupied forever.
            // Use a fresh worker so foreground activation and manual sync can retry.
            self.bookmarkStore = SyncFolderBookmarkStore()
            self.errorMessage = SyncError.folderUnavailable.localizedDescription
        }
    }

    private func acceptFolderAccess(url: URL, bookmarkData: Data) {
        selectedFolderURL = url
        self.bookmarkData = bookmarkData
        persistedFolderDisplayPath = url.path(percentEncoded: false)
        defaults.set(bookmarkData, forKey: SyncPreferenceKeys.bookmark)
        defaults.set(persistedFolderDisplayPath, forKey: SyncPreferenceKeys.folderDisplayPath)
        errorMessage = nil
    }

    private func scheduleSync(after delay: Duration, applyMergedRecords: Bool) {
        guard isEnabled else { return }
        debounceShouldApplyMergedRecords = debounceShouldApplyMergedRecords || applyMergedRecords
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            self.debounceTask = nil
            let shouldApplyMergedRecords = self.debounceShouldApplyMergedRecords
            self.debounceShouldApplyMergedRecords = false
            self.launchSync(applyMergedRecords: shouldApplyMergedRecords)
        }
    }

    private func launchSync(applyMergedRecords: Bool) {
        guard isEnabled, selectedFolderURL != nil, store != nil else { return }
        guard syncTask == nil else {
            syncAgainAfterCurrentRun = true
            queuedSyncShouldApplyMergedRecords = queuedSyncShouldApplyMergedRecords || applyMergedRecords
            return
        }
        isSyncing = true
        let generation = UUID()
        syncGeneration = generation
        let engine = self.engine
        beginSyncTimeout(generation: generation)
        syncTask = Task { [weak self] in
            await self?.runSyncLoop(
                applyMergedRecords: applyMergedRecords,
                engine: engine,
                generation: generation
            )
        }
    }

    private func runSyncLoop(
        applyMergedRecords: Bool,
        engine: SyncEngine,
        generation: UUID
    ) async {
        var shouldApplyMergedRecords = applyMergedRecords
        while !Task.isCancelled, syncGeneration == generation {
            syncAgainAfterCurrentRun = false
            queuedSyncShouldApplyMergedRecords = false
            await performSingleSync(
                applyMergedRecords: shouldApplyMergedRecords,
                engine: engine,
                generation: generation
            )
            guard syncGeneration == generation, syncAgainAfterCurrentRun else { break }
            shouldApplyMergedRecords = queuedSyncShouldApplyMergedRecords
        }
        guard syncGeneration == generation else { return }
        syncTimeoutTask?.cancel()
        syncTimeoutTask = nil
        isSyncing = false
        syncTask = nil
    }

    private func performSingleSync(
        applyMergedRecords: Bool,
        engine: SyncEngine,
        generation: UUID
    ) async {
        guard let selectedFolderURL, let store else { return }
        let chapterRanksByBook = store.syncChapterRanks()
        let localBooks = SyncMerger.merge(
            store.syncRecords() + Array(tombstones.values),
            chapterRanksByBook: chapterRanksByBook
        )
        do {
            if !applyMergedRecords {
                let publishedAt = try await engine.publishLocal(
                    selectedFolder: selectedFolderURL,
                    localBooks: localBooks
                )
                guard !Task.isCancelled, isEnabled, syncGeneration == generation else { return }
                tombstones = Dictionary(
                    uniqueKeysWithValues: localBooks
                        .filter(\.isDeleted)
                        .map { ($0.canonicalSourceURL, $0) }
                )
                finishSuccessfulOperation(at: publishedAt)
                return
            }

            let result = try await engine.synchronize(
                selectedFolder: selectedFolderURL,
                localBooks: localBooks,
                chapterRanksByBook: chapterRanksByBook
            )
            guard !Task.isCancelled, isEnabled, syncGeneration == generation else { return }
            try store.applySyncRecords(result.books)
            tombstones = Dictionary(
                uniqueKeysWithValues: result.books
                    .filter(\.isDeleted)
                    .map { ($0.canonicalSourceURL, $0) }
            )
            lastWindowsFileSignature = result.windowsFileSignature
            finishSuccessfulOperation(at: result.synchronizedAt)
        } catch is CancellationError {
            return
        } catch {
            guard syncGeneration == generation else { return }
            errorMessage = userFacingSyncError(error)
        }
    }

    private func beginSyncTimeout(generation: UUID) {
        syncTimeoutTask?.cancel()
        syncTimeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(10))
            } catch {
                return
            }
            guard let self,
                  self.syncGeneration == generation,
                  self.syncTask != nil else { return }
            self.syncGeneration = UUID()
            self.syncTask?.cancel()
            self.syncTask = nil
            self.syncTimeoutTask = nil
            self.isSyncing = false
            self.syncAgainAfterCurrentRun = false
            self.queuedSyncShouldApplyMergedRecords = false
            // Do not queue retries behind a File Provider call that may never return.
            self.engine = SyncEngine()
            self.errorMessage = SyncError.folderUnavailable.localizedDescription
        }
    }

    private func finishSuccessfulOperation(at date: Date) {
        persistTombstones()
        lastSyncAt = date
        defaults.set(date, forKey: SyncPreferenceKeys.lastSyncAt)
        errorMessage = nil
        startDirectoryMonitor()
    }

    private func startDirectoryMonitor() {
        guard let selectedFolderURL else { return }
        let directory = selectedFolderURL.appendingPathComponent(SyncEngine.directoryName, isDirectory: true)
        Task { [weak self] in
            await self?.monitor.start(directory: directory) { [weak self] in
                Task { @MainActor [weak self] in
                    self?.checkWindowsFileChange()
                }
            }
        }
    }

    private func startPolling() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(30))
                } catch {
                    return
                }
                guard let self else { return }
                self.checkWindowsFileChange()
            }
        }
    }

    private func checkWindowsFileChange() {
        guard windowsChangeCheckTask == nil,
              isEnabled,
              let selectedFolderURL else { return }
        let generation = UUID()
        windowsChangeGeneration = generation
        let signatureEngine = SyncEngine()
        windowsChangeTimeoutTask?.cancel()
        windowsChangeTimeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(5))
            } catch {
                return
            }
            guard let self,
                  self.windowsChangeGeneration == generation,
                  self.windowsChangeCheckTask != nil else { return }
            self.windowsChangeGeneration = UUID()
            self.windowsChangeCheckTask?.cancel()
            self.windowsChangeCheckTask = nil
            self.windowsChangeTimeoutTask = nil
            self.errorMessage = SyncError.folderUnavailable.localizedDescription
        }
        windowsChangeCheckTask = Task { [weak self] in
            guard let self else { return }
            defer { self.finishWindowsChangeCheck(generation: generation) }
            do {
                let signature = try await signatureEngine.windowsFileSignature(selectedFolder: selectedFolderURL)
                guard !Task.isCancelled, self.windowsChangeGeneration == generation else { return }
                if signature != self.lastWindowsFileSignature {
                    self.syncNow()
                }
            } catch {
                guard self.windowsChangeGeneration == generation else { return }
                self.errorMessage = self.userFacingSyncError(error)
            }
        }
    }

    private func finishWindowsChangeCheck(generation: UUID) {
        guard windowsChangeGeneration == generation else { return }
        windowsChangeTimeoutTask?.cancel()
        windowsChangeTimeoutTask = nil
        windowsChangeCheckTask = nil
    }

    private func userFacingSyncError(_ error: Error) -> String {
        if let syncError = error as? SyncError {
            return syncError.localizedDescription
        }
        return SyncError.folderUnavailable.localizedDescription
    }

    private func persistTombstones() {
        let snapshot = SyncSnapshot(device: .mac, books: Array(tombstones.values))
        if let data = try? SyncSnapshotCodec.encode(snapshot) {
            defaults.set(data, forKey: SyncPreferenceKeys.tombstones)
        }
    }

    private static func loadTombstones(defaults: UserDefaults) -> [String: SyncBookRecord] {
        guard let data = defaults.data(forKey: SyncPreferenceKeys.tombstones),
              let snapshot = try? SyncSnapshotCodec.decode(data, expectedDevice: .mac) else {
            return [:]
        }
        var records: [String: SyncBookRecord] = [:]
        for book in snapshot.books where book.isDeleted {
            records[book.canonicalSourceURL] = book
        }
        return records
    }
}
