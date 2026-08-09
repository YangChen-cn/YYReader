import SwiftUI
@preconcurrency import WebKit

struct WebVerificationWebView: NSViewRepresentable {
    let request: VerificationRequest
    let reloadToken: Int
    let onStatus: @MainActor (String) -> Void
    let onFailure: @MainActor (String) -> Void
    let onHTMLReady: @MainActor (String, URL, String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            requestID: request.id,
            reloadToken: reloadToken,
            onStatus: onStatus,
            onFailure: onFailure,
            onHTMLReady: onHTMLReady
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        context.coordinator.reportStatus("正在载入网站验证页面…")
        webView.load(URLRequest(url: request.url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.requestID != request.id
                || context.coordinator.reloadToken != reloadToken else { return }
        context.coordinator.reset(
            requestID: request.id,
            reloadToken: reloadToken,
            onStatus: onStatus,
            onFailure: onFailure,
            onHTMLReady: onHTMLReady
        )
        webView.load(URLRequest(url: request.url))
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        private(set) var requestID: UUID
        private(set) var reloadToken: Int
        private var onStatus: @MainActor (String) -> Void
        private var onFailure: @MainActor (String) -> Void
        private var onHTMLReady: @MainActor (String, URL, String) -> Void
        private var delivered = false

        init(
            requestID: UUID,
            reloadToken: Int,
            onStatus: @escaping @MainActor (String) -> Void,
            onFailure: @escaping @MainActor (String) -> Void,
            onHTMLReady: @escaping @MainActor (String, URL, String) -> Void
        ) {
            self.requestID = requestID
            self.reloadToken = reloadToken
            self.onStatus = onStatus
            self.onFailure = onFailure
            self.onHTMLReady = onHTMLReady
        }

        func reset(
            requestID: UUID,
            reloadToken: Int,
            onStatus: @escaping @MainActor (String) -> Void,
            onFailure: @escaping @MainActor (String) -> Void,
            onHTMLReady: @escaping @MainActor (String, URL, String) -> Void
        ) {
            self.requestID = requestID
            self.reloadToken = reloadToken
            self.onStatus = onStatus
            self.onFailure = onFailure
            self.onHTMLReady = onHTMLReady
            delivered = false
            onStatus("正在重新载入验证页面…")
        }

        func reportStatus(_ message: String) {
            onStatus(message)
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation?) {
            onStatus("正在连接网站…")
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
            Task { @MainActor in
                guard !delivered,
                      let url = webView.url,
                      let result = try? await webView.evaluateJavaScript("document.documentElement.outerHTML"),
                      let html = result as? String,
                      html.count > 300 else {
                    onFailure("页面没有返回可读取的内容，可以重试或取消。")
                    return
                }
                guard !isChallenge(html) else {
                    onStatus("网站仍在验证，请在页面中完成操作…")
                    return
                }
                let userAgent = (try? await webView.evaluateJavaScript("navigator.userAgent")) as? String ?? ""
                let cookies = await allCookies(from: webView.configuration.websiteDataStore.httpCookieStore)
                for cookie in cookies {
                    HTTPCookieStorage.shared.setCookie(cookie)
                }
                delivered = true
                onStatus("验证完成，正在继续导入…")
                onHTMLReady(html, url, userAgent)
            }
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation?,
            withError error: any Error
        ) {
            onFailure("无法载入验证页面：\(error.localizedDescription)")
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation?, withError error: any Error) {
            onFailure("验证页面载入失败：\(error.localizedDescription)")
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            onFailure("验证页面进程已停止，请重试。")
        }

        private func allCookies(from store: WKHTTPCookieStore) async -> [HTTPCookie] {
            await withCheckedContinuation { continuation in
                store.getAllCookies { cookies in
                    continuation.resume(returning: cookies)
                }
            }
        }

        private func isChallenge(_ html: String) -> Bool {
            let sample = html.lowercased()
            return sample.contains("cf-chl-")
                || sample.contains("<title>just a moment")
                || sample.contains("enable javascript and cookies to continue")
        }
    }
}
