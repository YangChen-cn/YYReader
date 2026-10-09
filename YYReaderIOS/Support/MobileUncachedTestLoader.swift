#if DEBUG
import Foundation

// Only used by the explicit offline UI-test launch argument.
@MainActor
final class MobileUncachedTestLoader: HTMLDocumentLoading {
    func load(_ url: URL) async throws -> LoadedHTML {
        guard url.lastPathComponent == "2.html" else { throw HTMLLoadError.httpStatus(404) }
        try await Task.sleep(for: .milliseconds(800))
        let paragraphs = (1...40).map { "<p>下载段落\($0)：山间的风穿过木窗，树影落在书页上。她收起笔，走向溪边的石桥。</p>" }.joined()
        let html = "<h1>第2章 石桥</h1><div id='content'>\(paragraphs)</div><a rel='prev' href='1.html'>上一章</a><a rel='next' href='3.html'>下一章</a>"
        return LoadedHTML(requestedURL: url, finalURL: url, html: html, retrievalKind: .urlSession)
    }
}
#endif
