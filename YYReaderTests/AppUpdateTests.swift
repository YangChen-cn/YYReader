import Foundation
import Testing
@testable import YYReader

@Suite(.serialized)
struct AppUpdateTests {
    @Test func numericVersionsRejectPrereleasesAndCompareComponents() throws {
        #expect(ReleaseVersion("1.10.0")! > ReleaseVersion("1.9.9")!)
        #expect(ReleaseVersion("2.0") == ReleaseVersion("2.0.0"))
        for invalid in ["v1.4.0", "1.4.0-beta", "1..4", "1.4.0.1", "-1.4.0", "１.４.０"] {
            #expect(ReleaseVersion(invalid) == nil)
        }
    }

    @Test func eachPlatformSelectsOnlyItsNewestStableInstaller() throws {
        let releases = try decode([
            entry("v1.9.0", asset: "YYReader-1.9.0-arm64.dmg"),
            entry("ios-v2.0.0", asset: "YYReader-iOS-2.0.0-resign.ipa"),
            entry("v1.10.0", asset: "YYReader-1.10.0-arm64.dmg"),
            entry("v3.0.0", asset: "YYReader-3.0.0-arm64.dmg", prerelease: true),
            entry("v4.0.0", asset: "YYReader-4.0.0-arm64.dmg", draft: true),
            entry("v9.0.0", asset: "YYReader-Setup-x64-9.0.0.exe")
        ])
        #expect(AppRelease.newest(in: releases, platform: .macOS, installed: "1.4.0")?.version == "1.10.0")
        #expect(AppRelease.newest(in: releases, platform: .iOS, installed: "1.4.0")?.version == "2.0.0")
        #expect(AppRelease.newest(in: releases, platform: .macOS, installed: "1.10.0") == nil)
        #expect(AppRelease.newest(in: releases, platform: .iOS, installed: "2.1.0") == nil)
    }

    @Test func foreignDownloadsAndInvalidDigestsAreNotTrusted() throws {
        var bad = entry("v2.0.0", asset: "YYReader-2.0.0-arm64.dmg")
        var asset = (bad["assets"] as! [[String: Any]])[0]
        asset["browser_download_url"] = "https://example.com/YYReader-2.0.0-arm64.dmg"
        bad["assets"] = [asset]
        #expect(AppRelease.newest(in: try decode([bad]), platform: .macOS, installed: "1.4.0") == nil)
        #expect(!AppRelease.trustedReleaseURL(URL(string: "http://github.com/YangChen-cn/YYReader/releases/tag/v2.0.0")!))
        #expect(!AppRelease.trustedReleaseURL(URL(string: "https://github.com/other/YYReader/releases/tag/v2.0.0")!))
        let invalid = GitHubRelease.Asset(name: "test", browserDownloadURL: URL(string: "https://example.com")!, size: 1, digest: "sha256:xyz")
        #expect(invalid.sha256 == nil)
    }

    @Test func checksumAndSizeRejectDamagedOrPartialPackages() throws {
        let file = URL.temporaryDirectory.appendingPathComponent("YYReader-checksum-\(UUID())")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("abc".utf8).write(to: file)
        let hash = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        try AppUpdateService.verify(file, size: 3, digest: hash)
        #expect(throws: AppUpdateError.self) { try AppUpdateService.verify(file, size: 4, digest: hash) }
        #expect(throws: AppUpdateError.self) { try AppUpdateService.verify(file, size: 3, digest: String(repeating: "0", count: 64)) }
    }

    @Test func automaticChecksUseCacheAndManualChecksUseETag() async throws {
        let directory = URL.temporaryDirectory.appendingPathComponent("YYReader-update-cache-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        UpdateTestProtocol.requests.withLock { $0 = [] }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [UpdateTestProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let service = AppUpdateService(session: session, directory: directory)
        #expect(try await service.releases(force: false).count == 1)
        #expect(try await service.releases(force: false).count == 1)
        #expect(UpdateTestProtocol.requests.withLock { $0.count } == 1)
        #expect(try await service.releases(force: true).count == 1)
        #expect(UpdateTestProtocol.requests.withLock { $0.last?.value(forHTTPHeaderField: "If-None-Match") } == "fixture-etag")
        // Persisted metadata is reused after reopening, without another request.
        let reopened = AppUpdateService(session: session, directory: directory)
        #expect(try await reopened.releases(force: false).count == 1)
        #expect(UpdateTestProtocol.requests.withLock { $0.count } == 2)
    }

    @Test @MainActor func ignoredUpdateKeepsEntryAndManualCheckRestoresNotice() async throws {
        let directory = URL.temporaryDirectory.appendingPathComponent("YYReader-ignore-\(UUID())")
        let suite = "YYReader-ignore-test-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [UpdateTestProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let service = AppUpdateService(session: session, directory: directory)
        let updates = AppUpdateController(installedVersion: "1.4.0", service: service, defaults: defaults)
        await updates.check(force: true)
        #expect(updates.showsBanner)
        updates.dismissBanner()
        #expect(!updates.showsBanner)
        #expect(updates.hasCollapsedUpdate)
        #expect(updates.release?.version == "2.0.0")
        let reopened = AppUpdateController(installedVersion: "1.4.0", service: service, defaults: defaults)
        await reopened.check()
        #expect(reopened.hasCollapsedUpdate && !reopened.showsBanner)
        reopened.revealBanner()
        #expect(reopened.showsBanner)
        reopened.dismissBanner()
        await reopened.check(force: true)
        #expect(reopened.showsBanner && !reopened.hasCollapsedUpdate)
        #expect(defaults.string(forKey: "updates.hiddenVersion") == nil)
    }

    #if os(macOS)
    @Test func failedReplacementRestoresOriginalAndKeepsNewStaging() throws {
        let directory = URL.temporaryDirectory.appendingPathComponent("YYReader-replacement-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let prepared = MacUpdateInstaller.Prepared(target: directory.appendingPathComponent("old.app"),
            staging: directory.appendingPathComponent("new.app"), backup: directory.appendingPathComponent("backup.app"))
        try Data("old".utf8).write(to: prepared.target)
        try Data("new".utf8).write(to: prepared.staging)
        #expect(throws: CocoaError.self) {
            try MacUpdateInstaller.replace(prepared) { from, to in
                if from == prepared.staging { throw CocoaError(.fileWriteNoPermission) }
                try FileManager.default.moveItem(at: from, to: to)
            }
        }
        #expect(try String(contentsOf: prepared.target, encoding: .utf8) == "old")
        #expect(try String(contentsOf: prepared.staging, encoding: .utf8) == "new")
        #expect(!FileManager.default.fileExists(atPath: prepared.backup.path))
    }

    @Test func successfulReplacementKeepsBackupUntilLaunchAndCanRollback() async throws {
        let directory = URL.temporaryDirectory.appendingPathComponent("YYReader-success-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let prepared = MacUpdateInstaller.Prepared(target: directory.appendingPathComponent("old.app"),
            staging: directory.appendingPathComponent("new.app"), backup: directory.appendingPathComponent("backup.app"))
        try Data("old".utf8).write(to: prepared.target)
        try Data("new".utf8).write(to: prepared.staging)
        let worker = MacUpdateInstaller()
        try await worker.replace(prepared)
        #expect(try String(contentsOf: prepared.target, encoding: .utf8) == "new")
        #expect(try String(contentsOf: prepared.backup, encoding: .utf8) == "old")
        try await worker.rollback(prepared)
        #expect(try String(contentsOf: prepared.target, encoding: .utf8) == "old")
    }
    #endif

    private func entry(_ tag: String, asset: String, draft: Bool = false, prerelease: Bool = false) -> [String: Any] {
        ["tag_name": tag, "body": "## 更新\n- 更顺滑", "html_url": "https://github.com/YangChen-cn/YYReader/releases/tag/\(tag)",
         "draft": draft, "prerelease": prerelease, "assets": [["name": asset, "size": 3,
         "browser_download_url": "https://github.com/YangChen-cn/YYReader/releases/download/\(tag)/\(asset)",
         "digest": "sha256:" + String(repeating: "a", count: 64)]]]
    }

    private func decode(_ entries: [[String: Any]]) throws -> [GitHubRelease] {
        try JSONDecoder().decode([GitHubRelease].self, from: JSONSerialization.data(withJSONObject: entries))
    }
}

import Synchronization

/// Foundation requires an unchecked URLProtocol subclass. Its only mutable
/// cross-request state is held under a Mutex; these are invented local responses.
private final class UpdateTestProtocol: URLProtocol, @unchecked Sendable {
    static let requests = Mutex<[URLRequest]>([])
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.withLock { $0.append(request) }
        let cached = request.value(forHTTPHeaderField: "If-None-Match") != nil
        let response = HTTPURLResponse(url: request.url!, statusCode: cached ? 304 : 200, httpVersion: nil,
                                       headerFields: ["ETag": "fixture-etag"])!
        let prefix = AppRelease.Platform.current == .macOS ? "v" : "ios-v"
        let name = AppRelease.Platform.current == .macOS ? "YYReader-2.0.0-arm64.dmg" : "YYReader-iOS-2.0.0-resign.ipa"
        let data = Data("""
        [{"tag_name":"\(prefix)2.0.0","body":"fixture","html_url":"https://github.com/YangChen-cn/YYReader/releases/tag/\(prefix)2.0.0",
        "draft":false,"prerelease":false,"assets":[{"name":"\(name)","size":3,
        "browser_download_url":"https://github.com/YangChen-cn/YYReader/releases/download/\(prefix)2.0.0/\(name)"}]}]
        """.utf8)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !cached { client?.urlProtocol(self, didLoad: data) }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
