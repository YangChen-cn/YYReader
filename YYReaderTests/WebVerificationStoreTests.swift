import Foundation
import Testing
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
}
