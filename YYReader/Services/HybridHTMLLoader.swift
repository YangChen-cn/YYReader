import Foundation

@MainActor
final class HybridHTMLLoader: HTMLDocumentLoading {
    private let staticLoader: URLSessionHTMLLoader
    private let verificationStore: WebVerificationStore
    private var verifiedHostsThisOperation: Set<String> = []

    init(staticLoader: URLSessionHTMLLoader, verificationStore: WebVerificationStore) {
        self.staticLoader = staticLoader
        self.verificationStore = verificationStore
    }

    func beginOperation() {
        verifiedHostsThisOperation.removeAll()
    }

    func load(_ url: URL) async throws -> LoadedHTML {
        do {
            return try await staticLoader.load(url)
        } catch HTMLLoadError.verificationRequired {
            let host = url.host?.lowercased() ?? ""
            guard !verifiedHostsThisOperation.contains(host) else {
                throw HTMLLoadError.verificationFailed("验证信息未被网站接受，本次导入已停止，请稍后重试。")
            }
            let document = try await verificationStore.load(url)
            verifiedHostsThisOperation.insert(host)
            if let host = document.finalURL.host,
               let userAgent = verificationStore.userAgent(for: document.finalURL) {
                await staticLoader.useVerifiedUserAgent(userAgent, forHost: host)
            }
            return document
        }
    }
}
