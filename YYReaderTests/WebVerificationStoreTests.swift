import Foundation
import Testing
@testable import YYReader

@MainActor
struct WebVerificationStoreTests {
    @Test
    func completionReturnsHTMLAndRemembersBrowserUserAgent() async throws {
        let store = WebVerificationStore()
        let url = try #require(URL(string: "https://www.qidiy.com/book/1/1.html"))
        let task = Task { try await store.load(url) }
        await Task.yield()

        #expect(store.request?.url == url)
        store.complete(html: "<html><body>chapter</body></html>", finalURL: url, userAgent: "Verified WebKit")

        let document = try await task.value
        #expect(document.retrievalKind == .webKit)
        #expect(store.userAgent(for: url) == "Verified WebKit")
        #expect(store.request == nil)
    }

    @Test
    func cancelStopsPendingVerification() async {
        let store = WebVerificationStore()
        let url = URL(string: "https://www.qidiy.com/book/1/1.html")!
        let task = Task { try await store.load(url) }
        await Task.yield()

        store.cancel()

        do {
            _ = try await task.value
            Issue.record("Expected cancellation to end the pending verification")
        } catch HTMLLoadError.cancelled {
            #expect(store.request == nil)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
