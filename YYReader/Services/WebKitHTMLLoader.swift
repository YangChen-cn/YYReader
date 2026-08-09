import Foundation

@MainActor
final class WebKitHTMLLoader: BrowserHTMLLoading {
    typealias VerificationPresenter = @MainActor (WebKitHostSession, URL) -> Bool

    private let limiter: HostRateLimiter
    private let maximumVerificationPresentationsPerHost: Int
    private var sessions: [String: WebKitHostSession] = [:]
    private var verificationPresentations: [String: Int] = [:]
    private var verificationPresenter: VerificationPresenter?
    private var verificationCompletion: (@MainActor (WebKitHostSession) -> Void)?

    init(
        limiter: HostRateLimiter = HostRateLimiter(),
        maximumVerificationPresentationsPerHost: Int = 2
    ) {
        self.limiter = limiter
        self.maximumVerificationPresentationsPerHost = maximumVerificationPresentationsPerHost
    }

    var sessionCount: Int { sessions.count }

    func configureVerification(
        presenter: @escaping VerificationPresenter,
        completion: @escaping @MainActor (WebKitHostSession) -> Void
    ) {
        verificationPresenter = presenter
        verificationCompletion = completion
    }

    func beginOperation() {
        verificationPresentations.removeAll()
    }

    func load(_ url: URL) async throws -> LoadedHTML {
        guard let host = normalizedHost(for: url) else { throw NovelParsingError.unsupportedURL }
        try await limiter.wait(for: url)
        return try await session(for: host).load(url)
    }

    func hostSession(for url: URL) -> WebKitHostSession? {
        guard let host = normalizedHost(for: url) else { return nil }
        return session(for: host)
    }

    private func session(for host: String) -> WebKitHostSession {
        if let existing = sessions[host] { return existing }
        let created = WebKitHostSession(host: host)
        created.onVerificationRequired = { [weak self] session, url in
            self?.handleVerificationRequired(session: session, url: url)
        }
        created.onVerificationCompleted = { [weak self] session in
            self?.verificationCompletion?(session)
        }
        sessions[host] = created
        return created
    }

    private func handleVerificationRequired(session: WebKitHostSession, url: URL) {
        let count = verificationPresentations[session.host, default: 0]
        guard count < maximumVerificationPresentationsPerHost else {
            session.failCurrentLoad(HTMLLoadError.verificationFailed(
                "同一次操作中网站重复要求人工验证，已停止以避免验证循环。"
            ))
            return
        }
        guard let verificationPresenter else {
            session.failCurrentLoad(HTMLLoadError.verificationRequired)
            return
        }
        if verificationPresenter(session, url) {
            verificationPresentations[session.host] = count + 1
        }
    }

    private func normalizedHost(for url: URL) -> String? {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host?.lowercased(), !host.isEmpty else {
            return nil
        }
        return host
    }
}
