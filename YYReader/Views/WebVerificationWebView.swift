import SwiftUI
@preconcurrency import WebKit

#if os(macOS)
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
#else
struct WebVerificationWebView: UIViewRepresentable {
    let session: WebKitHostSession

    func makeUIView(context: Context) -> WKWebView {
        session.webView.removeFromSuperview()
        return session.webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}
#endif
