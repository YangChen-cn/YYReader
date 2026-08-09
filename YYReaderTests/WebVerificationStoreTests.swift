import Foundation
import Testing
@preconcurrency import WebKit
@testable import YYReader

@MainActor
struct WebVerificationStoreTests {
    @Test
    func sheetRequestReferencesPersistentHostSession() throws {
        let store = WebVerificationStore()
        let url = try #require(URL(string: "https://www.qidiy.com/book/1/1.html"))
        let session = WebKitHostSession(host: "www.qidiy.com")

        #expect(store.present(session: session, url: url))
        #expect(store.request?.url == url)
        #expect(store.request?.session === session)
        #expect(!store.present(session: session, url: url))

        store.complete(session: session)
        #expect(store.request == nil)
    }

    @Test
    func cancelDismissesPendingVerification() {
        let store = WebVerificationStore()
        let url = URL(string: "https://www.qidiy.com/book/1/1.html")!
        let session = WebKitHostSession(host: "www.qidiy.com")
        #expect(store.present(session: session, url: url))

        store.cancel()
        #expect(store.request == nil)
    }

    @Test
    func hostSessionStopsNavigationThatNeverFinishes() async throws {
        let webView = NeverFinishingWebView(frame: .zero, configuration: WKWebViewConfiguration())
        let session = WebKitHostSession(
            host: "www.qidiy.com",
            loadTimeout: .milliseconds(10),
            webView: webView
        )
        let url = try #require(URL(string: "https://www.qidiy.com/book/1/"))

        do {
            _ = try await session.load(url)
            Issue.record("永不完成的 WebKit 导航应自动超时")
        } catch HTMLLoadError.requestTimedOut {
            // Expected.
        } catch {
            Issue.record("收到非预期错误：\(error)")
        }
    }
}

@MainActor
private final class NeverFinishingWebView: WKWebView {
    override func load(_ request: URLRequest) -> WKNavigation? { nil }
}
