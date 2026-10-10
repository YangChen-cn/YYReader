import Foundation
import Observation
#if os(macOS)
import AppKit
#endif

@MainActor
@Observable
final class AppUpdateController {
    static let automaticCheckKey = "updates.automaticCheck"
    let installedVersion: String
    private(set) var release: AppRelease?
    private(set) var isChecking = false
    private(set) var isDownloading = false
    private(set) var isInstalling = false
    private(set) var downloadProgress = 0.0
    private(set) var downloadedArchive: URL?
    private(set) var statusMessage: String?
    private(set) var errorMessage: String?
    private var hiddenVersion: String
    @ObservationIgnored private let service: AppUpdateService
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var downloadTask: Task<Void, Never>?
    @ObservationIgnored private var downloadID = UUID()
    @ObservationIgnored private var lastAutomaticAttempt: Date?
    @ObservationIgnored private var installationTask: Task<Void, Never>?
    #if DEBUG
    let isPreview = ProcessInfo.processInfo.arguments.contains("--preview-update")
    #endif

    var showsBanner: Bool { release != nil && (release?.version != hiddenVersion || isDownloading || downloadedArchive != nil) }
    var isBusy: Bool { isDownloading || isInstalling }
    var hasCollapsedUpdate: Bool { release != nil && !showsBanner }
    var canDismissBanner: Bool {
        #if DEBUG
        if isPreview { return true }
        #endif
        return !isBusy && downloadedArchive == nil
    }

    init(installedVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0",
         service: AppUpdateService = AppUpdateService(), defaults: UserDefaults = .standard) {
        self.installedVersion = installedVersion
        self.service = service
        self.defaults = defaults
        hiddenVersion = defaults.string(forKey: "updates.hiddenVersion") ?? ""
        #if DEBUG
        if isPreview { showPreviewAvailable() }
        #endif
    }

    func check(force: Bool = false) async {
        #if DEBUG
        if isPreview {
            if force, !isBusy { showPreviewAvailable() }
            return
        }
        #endif
        guard !isChecking, !isBusy, downloadedArchive == nil else { return }
        if !force {
            guard defaults.object(forKey: Self.automaticCheckKey) as? Bool ?? true else { return }
            guard !ProcessInfo.processInfo.arguments.contains("--ui-testing") else { return }
            if let lastAutomaticAttempt, Date().timeIntervalSince(lastAutomaticAttempt) < 6 * 3600 { return }
            lastAutomaticAttempt = .now
        }
        isChecking = true
        errorMessage = nil
        statusMessage = nil
        defer { isChecking = false }
        do {
            let releases = try await service.releases(force: force)
            try Task.checkCancellation()
            release = AppRelease.newest(in: releases, platform: .current, installed: installedVersion)
            if force { revealBanner(); statusMessage = release == nil ? "已是最新版本" : nil }
        } catch is CancellationError {
            return
        } catch {
            if (error as? URLError)?.code != .cancelled { errorMessage = error.localizedDescription }
        }
    }

    func dismissBanner() {
        #if DEBUG
        if isPreview { exitPreview(); return }
        #endif
        guard !isBusy, downloadedArchive == nil else { return }
        hiddenVersion = release?.version ?? ""
        defaults.set(hiddenVersion, forKey: "updates.hiddenVersion")
    }

    func revealBanner() {
        guard release != nil else { return }
        hiddenVersion = ""
        #if DEBUG
        if isPreview { return }
        #endif
        defaults.removeObject(forKey: "updates.hiddenVersion")
    }

    func download() {
        #if DEBUG
        if isPreview { startPreviewDownload(); return }
        #endif
        guard let release, !isBusy, downloadedArchive == nil else { return }
        isDownloading = true
        errorMessage = nil
        downloadProgress = 0
        let id = UUID()
        downloadID = id
        downloadTask = Task { [weak self, service] in
            do {
                let archive = try await service.download(release) { [weak self] progress in
                    Task { @MainActor [weak self] in
                        guard let self, self.downloadID == id, self.isDownloading else { return }
                        self.downloadProgress = max(self.downloadProgress, progress)
                    }
                }
                guard let self, !Task.isCancelled, self.downloadID == id else {
                    try await service.discard(archive)
                    return
                }
                self.downloadedArchive = archive
                self.downloadProgress = 1
            } catch {
                if let self, self.downloadID == id, !Task.isCancelled, (error as? URLError)?.code != .cancelled {
                    self.errorMessage = error.localizedDescription
                }
            }
            if let self, self.downloadID == id { self.isDownloading = false; self.downloadTask = nil }
        }
    }

    func cancelDownload() {
        downloadID = UUID()
        downloadTask?.cancel()
        downloadTask = nil
        isDownloading = false
        downloadProgress = 0
    }

    func retryDownload() async {
        #if DEBUG
        if isPreview { startPreviewDownload(); return }
        #endif
        guard !isBusy, let archive = downloadedArchive else { return }
        do {
            try await service.discard(archive)
            downloadedArchive = nil
            errorMessage = nil
            download()
        } catch { errorMessage = error.localizedDescription }
    }

    #if os(macOS)
    func install(store: LibraryStore?) async {
        #if DEBUG
        if isPreview { statusMessage = "UI 预览：不会安装或重启。"; return }
        #endif
        guard let archive = downloadedArchive, let release, let digest = release.asset.sha256, !isInstalling else { return }
        guard store?.isLoading != true, store?.offlineDownloads.isDownloading != true else {
            errorMessage = "请先完成导入或离线下载，再安装更新。"
            return
        }
        guard store?.flushPendingProgress() != false else { errorMessage = AppUpdateError.saveFailed.localizedDescription; return }
        let target = Bundle.main.bundleURL.resolvingSymlinksInPath()
        guard !target.path.contains("/AppTranslocation/"), !target.path.hasPrefix("/Volumes/"),
              !target.path.hasPrefix("/private/tmp/"), !target.path.hasPrefix("/tmp/") else {
            errorMessage = AppUpdateError.unsupportedLocation.localizedDescription
            return
        }
        let helper = target.appendingPathComponent("Contents/Helpers/YYReaderUpdater.app")
        guard FileManager.default.fileExists(atPath: helper.path) else {
            errorMessage = AppUpdateError.helperMissing.localizedDescription
            return
        }
        errorMessage = nil
        isInstalling = true
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.arguments = ["--install", archive.path, target.path, release.version, digest,
                                   String(ProcessInfo.processInfo.processIdentifier)]
        do {
            try await service.resetInstallationStatus(archive)
            let application = try await NSWorkspace.shared.openApplication(at: helper, configuration: configuration)
            // The helper stages and verifies before requesting a normal app quit.
            // AppTerminationDelegate flushes the most recent reading progress then.
            installationTask = Task { [weak self, service] in
                // A helper that never reports back must not leave isInstalling set forever.
                // Bound the wait so the failure path can reset the state and allow a retry.
                let deadline = Date.now.addingTimeInterval(300)
                while !Task.isCancelled {
                    do {
                        try await Task.sleep(for: .seconds(1))
                        if Date.now >= deadline {
                            self?.errorMessage = "安装助手长时间未响应，请重试或从发布页面下载安装。"
                            self?.isInstalling = false
                            return
                        }
                        if let message = try await service.installationError(archive) {
                            self?.errorMessage = message
                            self?.isInstalling = false
                            return
                        }
                        if application.isTerminated {
                            self?.errorMessage = "安装助手已退出，请重试或从发布页面下载安装。"
                            self?.isInstalling = false
                            return
                        }
                    } catch {
                        if !Task.isCancelled { self?.errorMessage = error.localizedDescription; self?.isInstalling = false }
                        return
                    }
                }
            }
        } catch {
            isInstalling = false
            errorMessage = error.localizedDescription
        }
    }
    #endif

    #if DEBUG
    func exitPreview() {
        cancelDownload()
        downloadedArchive = nil
        hiddenVersion = release?.version ?? ""
        errorMessage = nil
        statusMessage = nil
    }

    func showPreviewAvailable() {
        cancelDownload()
        hiddenVersion = ""
        downloadedArchive = nil
        errorMessage = nil
        statusMessage = nil
        release = AppRelease(version: "1.5.0", notes: """
        ## 阅读体验
        - 漫画支持自动双页、快速跳页和图片放大。
        - 接续上次阅读位置，切换阅读方式更顺畅。

        ## 应用更新
        - 书架直接查看更新内容，下载时显示进度。
        - Mac 下载后安装并重启，保留书架和进度。
        - iOS 提供 IPA 链接，方便通过侧载工具安装。
        """, pageURL: URL(string: "https://github.com/YangChen-cn/YYReader/releases/tag/v1.4.0")!,
        asset: GitHubRelease.Asset(name: "preview", browserDownloadURL: URL(string: "https://github.com/YangChen-cn/YYReader/releases/tag/v1.4.0")!,
                                  size: 8_000_000, digest: "sha256:" + String(repeating: "a", count: 64)))
    }

    func showPreviewReady() {
        showPreviewAvailable()
        downloadProgress = 1
        downloadedArchive = URL.temporaryDirectory.appendingPathComponent("UI-preview-only.dmg")
    }

    func showPreviewFailure() {
        showPreviewAvailable()
        errorMessage = "下载暂时中断，请重试。"
    }

    func previewIPALink() { statusMessage = "UI 预览：不会打开实际下载地址。" }

    private func startPreviewDownload() {
        showPreviewAvailable()
        isDownloading = true
        let id = UUID()
        downloadID = id
        downloadTask = Task { [weak self] in
            for tick in 1...100 {
                do { try await Task.sleep(for: .milliseconds(80)) }
                catch { return }
                guard let self, self.downloadID == id else { return }
                self.downloadProgress = Double(tick) / 100
            }
            guard let self, self.downloadID == id else { return }
            self.isDownloading = false
            self.downloadedArchive = URL.temporaryDirectory.appendingPathComponent("UI-preview-only.dmg")
            self.downloadTask = nil
        }
    }
    #endif
}
