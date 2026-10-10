import Foundation

struct GitHubRelease: Decodable, Sendable {
    let tagName: String
    let body: String?
    let htmlURL: URL
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]

    struct Asset: Decodable, Sendable {
        let name: String
        let browserDownloadURL: URL
        let size: Int64
        let digest: String?

        var sha256: String? {
            guard let digest, digest.hasPrefix("sha256:") else { return nil }
            let hash = String(digest.dropFirst(7)).lowercased()
            guard hash.count == 64, hash.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return nil }
            return hash
        }

        enum CodingKeys: String, CodingKey {
            case name, size, digest
            case browserDownloadURL = "browser_download_url"
        }
    }

    enum CodingKeys: String, CodingKey {
        case body, draft, prerelease, assets
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}

struct AppRelease: Sendable, Identifiable {
    enum Platform: String, Sendable {
        case macOS, iOS
        static var current: Self {
            #if os(macOS)
            .macOS
            #else
            .iOS
            #endif
        }
    }

    let version: String
    let notes: String
    let pageURL: URL
    let asset: GitHubRelease.Asset
    var id: String { version }

    static func newest(in releases: [GitHubRelease], platform: Platform, installed: String) -> Self? {
        guard let current = ReleaseVersion(installed) else { return nil }
        let prefix = platform == .macOS ? "v" : "ios-v"
        return releases.compactMap { release -> Self? in
            guard !release.draft, !release.prerelease, release.tagName.hasPrefix(prefix) else { return nil }
            let version = String(release.tagName.dropFirst(prefix.count))
            guard let parsed = ReleaseVersion(version), parsed > current,
                  trustedReleaseURL(release.htmlURL) else { return nil }
            let name = platform == .macOS ? "YYReader-\(version)-arm64.dmg" : "YYReader-iOS-\(version)-resign.ipa"
            guard let asset = release.assets.first(where: { $0.name == name && $0.size > 0 && trustedReleaseURL($0.browserDownloadURL) }) else { return nil }
            return Self(version: version, notes: release.body ?? "", pageURL: release.htmlURL, asset: asset)
        }.max { ReleaseVersion($0.version)! < ReleaseVersion($1.version)! }
    }

    static func trustedReleaseURL(_ url: URL) -> Bool {
        url.scheme == "https" && url.host == "github.com" && url.user == nil && url.password == nil
            && url.port == nil && url.path.hasPrefix("/YangChen-cn/YYReader/releases/")
    }
}
