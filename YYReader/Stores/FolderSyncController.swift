import Foundation
import Observation

@MainActor
@Observable
final class FolderSyncController {
    private let engine: SyncEngine
    private let defaults: UserDefaults
    private let bookmarkStore: SyncFolderBookmarkStore
    private let monitor = SyncFolderMonitor()
    private weak var store: LibraryStore?
    private var selectedFolderURL: URL?
    private var didStartSecurityScopedAccess = false
    private var tombstones: [String: SyncBookRecord] = [:]
    private var debounceTask: Task<Void, Never>?
    private var syncTask: Task<Void, Never>?
    private var pollingTask: Task<Void, Never>?
    private var windowsChangeCheckTask: Task<Void, Never>?
    private var lastWindowsFileSignature: SyncFileSignature?
    private var syncAgainAfterCurrentRun = false

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
        defaults: UserDefaults = .standard
    ) {
        self.engine = engine
        self.defaults = defaults
        self.bookmarkStore = SyncFolderBookmarkStore(defaults: defaults)
        self.isEnabled = defaults.bool(forKey: SyncPreferenceKeys.enabled)
        self.lastSyncAt = defaults.object(forKey: SyncPreferenceKeys.lastSyncAt) as? Date
        self.tombstones = Self.loadTombstones(defaults: defaults)
        self.selectedFolderURL = try? self.bookmarkStore.resolve()
    }

    var folderDisplayPath: String? {
        selectedFolderURL?.path(percentEncoded: false)
    }

    var hasSelectedFolder: Bool {
        selectedFolderURL != nil
    }

    func attach(to store: LibraryStore) {
        self.store = store
        if isEnabled {
            activate()
        }
    }

    func chooseFolder() {
        guard let url = SyncFolderPicker.chooseFolder() else { return }
        do {
            try bookmarkStore.save(url)
            stopSecurityScopedAccess()
            selectedFolderURL = url
            startSecurityScopedAccess()
            errorMessage = nil
            if !isEnabled {
                isEnabled = true
            } else {
                startPolling()
                syncNow()
            }
        } catch {
            errorMessage = "无法保存同步文件夹权限：\(error.localizedDescription)"
        }
    }

    func appBecameActive() {
        guard isEnabled else { return }
        if selectedFolderURL == nil {
            restoreFolderAccess()
        } else if !didStartSecurityScopedAccess {
            startSecurityScopedAccess()
        }
        syncNow()
    }

    func scheduleLocalChange() {
        scheduleSync(after: .seconds(1.5))
    }

    func progressDidPersist() {
        scheduleSync(after: .seconds(1.5))
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
        launchSync()
    }

    private func activate() {
        restoreFolderAccess()
        startPolling()
        guard store != nil, selectedFolderURL != nil else { return }
        scheduleSync(after: .zero)
    }

    private func deactivate() {
        debounceTask?.cancel()
        debounceTask = nil
        syncTask?.cancel()
        syncTask = nil
        pollingTask?.cancel()
        pollingTask = nil
        windowsChangeCheckTask?.cancel()
        windowsChangeCheckTask = nil
        monitor.stop()
        isSyncing = false
        syncAgainAfterCurrentRun = false
        stopSecurityScopedAccess()
    }

    private func restoreFolderAccess() {
        guard selectedFolderURL == nil else {
            startSecurityScopedAccess()
            return
        }
        do {
            selectedFolderURL = try bookmarkStore.resolve()
            guard selectedFolderURL != nil else {
                errorMessage = "请选择一个文件夹后再启用同步。"
                return
            }
            startSecurityScopedAccess()
            errorMessage = nil
        } catch {
            errorMessage = "无法恢复同步文件夹权限：\(error.localizedDescription)"
        }
    }

    private func startSecurityScopedAccess() {
        guard !didStartSecurityScopedAccess, let selectedFolderURL else { return }
        didStartSecurityScopedAccess = selectedFolderURL.startAccessingSecurityScopedResource()
    }

    private func stopSecurityScopedAccess() {
        if didStartSecurityScopedAccess {
            selectedFolderURL?.stopAccessingSecurityScopedResource()
        }
        didStartSecurityScopedAccess = false
    }

    private func scheduleSync(after delay: Duration) {
        guard isEnabled else { return }
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            self.debounceTask = nil
            self.launchSync()
        }
    }

    private func launchSync() {
        guard isEnabled, selectedFolderURL != nil, store != nil else { return }
        guard syncTask == nil else {
            syncAgainAfterCurrentRun = true
            return
        }
        isSyncing = true
        syncTask = Task { [weak self] in
            await self?.runSyncLoop()
        }
    }

    private func runSyncLoop() async {
        repeat {
            syncAgainAfterCurrentRun = false
            await performSingleSync()
        } while syncAgainAfterCurrentRun && !Task.isCancelled
        isSyncing = false
        syncTask = nil
    }

    private func performSingleSync() async {
        guard let selectedFolderURL, let store else { return }
        let localBooks = SyncMerger.merge(store.syncRecords() + Array(tombstones.values))
        do {
            let result = try await engine.synchronize(
                selectedFolder: selectedFolderURL,
                localBooks: localBooks
            )
            guard !Task.isCancelled, isEnabled else { return }
            try store.applySyncRecords(result.books)
            tombstones = Dictionary(
                uniqueKeysWithValues: result.books
                    .filter(\.isDeleted)
                    .map { ($0.canonicalSourceURL, $0) }
            )
            persistTombstones()
            lastSyncAt = result.synchronizedAt
            defaults.set(result.synchronizedAt, forKey: SyncPreferenceKeys.lastSyncAt)
            lastWindowsFileSignature = result.windowsFileSignature
            errorMessage = nil
            startDirectoryMonitor()
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startDirectoryMonitor() {
        guard let selectedFolderURL else { return }
        let directory = selectedFolderURL.appendingPathComponent(SyncEngine.directoryName, isDirectory: true)
        monitor.start(directory: directory) { [weak self] in
            Task { @MainActor [weak self] in
                self?.checkWindowsFileChange()
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
        windowsChangeCheckTask = Task { [weak self] in
            guard let self else { return }
            defer { self.windowsChangeCheckTask = nil }
            do {
                let signature = try await self.engine.windowsFileSignature(selectedFolder: selectedFolderURL)
                if signature != self.lastWindowsFileSignature {
                    self.lastWindowsFileSignature = signature
                    self.syncNow()
                } else if self.errorMessage != nil {
                    self.syncNow()
                }
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
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
