import SwiftUI
@preconcurrency import WebKit

struct WebVerificationWebView: NSViewRepresentable {
    let session: WebKitHostSession

    func makeNSView(context: Context) -> WKWebView {
        session.webView.removeFromSuperview()
        return session.webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard webView !== session.webView else { return }
        webView.removeFromSuperview()
    }
}
