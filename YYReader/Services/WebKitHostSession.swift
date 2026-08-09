import Foundation
import Observation
@preconcurrency import WebKit

@MainActor
@Observable
final class WebKitHostSession: NSObject {
    let host: String
    let webView: WKWebView
    private let loadTimeout: Duration
    private(set) var status = "等待浏览器请求…"
    private(set) var failureMessage: String?

    @ObservationIgnored
    var onVerificationRequired: (@MainActor (WebKitHostSession, URL) -> Void)?
    @ObservationIgnored
    var onVerificationCompleted: (@MainActor (WebKitHostSession) -> Void)?

    @ObservationIgnored
    private var queuedLoads: [QueuedLoad] = []
    @ObservationIgnored
    private var activeLoad: QueuedLoad?
    @ObservationIgnored
    private var activeNavigation: WKNavigation?
    @ObservationIgnored
    private var activeTimeoutTask: Task<Void, Never>?

    init(
        host: String,
        websiteDataStore: WKWebsiteDataStore = .default(),
        loadTimeout: Duration = .seconds(30),
        webView suppliedWebView: WKWebView? = nil
    ) {
        self.host = host.lowercased()
        self.loadTimeout = loadTimeout
        if let suppliedWebView {
            webView = suppliedWebView
        } else {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = websiteDataStore
            webView = WKWebView(frame: .zero, configuration: configuration)
        }
        super.init()
        webView.navigationDelegate = self
    }

    func load(_ url: URL) async throws -> LoadedHTML {
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queuedLoads.append(QueuedLoad(id: id, url: url, continuation: continuation))
                startNextLoadIfNeeded()
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelLoad(id: id)
            }
        }
    }

    func reloadForVerification() {
        failureMessage = nil
        status = "正在重新载入验证页面…"
        if let url = activeLoad?.url {
            activeNavigation = webView.load(URLRequest(url: url))
            scheduleTimeout(for: activeLoad?.id)
        }
    }

    func cancelCurrentLoad() {
        guard let activeLoad else { return }
        webView.stopLoading()
        cancelActiveTimeout()
        self.activeLoad = nil
        activeNavigation = nil
        activeLoad.continuation.resume(throwing: HTMLLoadError.cancelled)
        startNextLoadIfNeeded()
    }

    func failCurrentLoad(_ error: any Error) {
        guard let activeLoad else { return }
        webView.stopLoading()
        cancelActiveTimeout()
        self.activeLoad = nil
        activeNavigation = nil
        failureMessage = error.localizedDescription
        activeLoad.continuation.resume(throwing: error)
        startNextLoadIfNeeded()
    }

    private func startNextLoadIfNeeded() {
        guard activeLoad == nil, !queuedLoads.isEmpty else { return }
        let next = queuedLoads.removeFirst()
        activeLoad = next
        failureMessage = nil
        status = "正在通过浏览器载入网页…"
        activeNavigation = webView.load(URLRequest(url: next.url))
        scheduleTimeout(for: next.id)
    }

    private func cancelLoad(id: UUID) {
        if activeLoad?.id == id {
            cancelCurrentLoad()
            return
        }
        guard let index = queuedLoads.firstIndex(where: { $0.id == id }) else { return }
        let queued = queuedLoads.remove(at: index)
        queued.continuation.resume(throwing: HTMLLoadError.cancelled)
    }

    private func inspectFinishedPage() async {
        guard let activeLoad else { return }
        do {
            let result = try await webView.evaluateJavaScript("document.documentElement.outerHTML")
            guard let html = result as? String, !html.isEmpty, let finalURL = webView.url else {
                throw HTMLLoadError.invalidResponse
            }
            if HTMLChallengeDetector.isChallenge(html) {
                cancelActiveTimeout()
                status = "网站要求人工验证，请在验证窗口中完成操作…"
                onVerificationRequired?(self, finalURL)
                return
            }

            await synchronizeCookies(for: finalURL)
            onVerificationCompleted?(self)
            cancelActiveTimeout()
            self.activeLoad = nil
            activeNavigation = nil
            status = "网页载入完成"
            activeLoad.continuation.resume(returning: LoadedHTML(
                requestedURL: activeLoad.url,
                finalURL: finalURL,
                html: html,
                retrievalKind: .webKit
            ))
            startNextLoadIfNeeded()
        } catch {
            failCurrentLoad(error)
        }
    }

    private func synchronizeCookies(for url: URL) async {
        guard let targetHost = url.host?.lowercased() else { return }
        let cookies = await allCookies()
        for cookie in cookies where cookieMatches(cookie, host: targetHost) {
            HTTPCookieStorage.shared.setCookie(cookie)
        }
    }

    private func allCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }

    private func cookieMatches(_ cookie: HTTPCookie, host: String) -> Bool {
        let cookieDomain = cookie.domain
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
        return host == cookieDomain || host.hasSuffix(".\(cookieDomain)")
    }

    private func scheduleTimeout(for loadID: UUID?) {
        cancelActiveTimeout()
        guard let loadID else { return }
        activeTimeoutTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: loadTimeout)
            } catch {
                return
            }
            guard activeLoad?.id == loadID else { return }
            failCurrentLoad(HTMLLoadError.requestTimedOut)
        }
    }

    private func cancelActiveTimeout() {
        activeTimeoutTask?.cancel()
        activeTimeoutTask = nil
    }
}

extension WebKitHostSession: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation?) {
        guard activeLoad != nil else { return }
        activeNavigation = navigation
        failureMessage = nil
        status = "正在连接网站…"
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        guard activeLoad != nil else { return }
        Task { @MainActor [weak self] in
            await self?.inspectFinishedPage()
        }
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation?,
        withError error: any Error
    ) {
        failNavigation(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation?, withError error: any Error) {
        failNavigation(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        failCurrentLoad(HTMLLoadError.verificationFailed("浏览器内容进程已停止。"))
    }

    private func failNavigation(_ error: any Error) {
        if let urlError = error as? URLError, urlError.code == .cancelled { return }
        failCurrentLoad(error)
    }
}

private extension WebKitHostSession {
    struct QueuedLoad {
        let id: UUID
        let url: URL
        let continuation: CheckedContinuation<LoadedHTML, any Error>
    }
}
