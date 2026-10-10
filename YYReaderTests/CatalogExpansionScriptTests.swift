import Foundation
import Testing
@preconcurrency import WebKit
@testable import YYReader

@MainActor
struct CatalogExpansionScriptTests {
    @Test
    func expandsExplicitCatalogControlAndCapturesFullDOM() async throws {
        let webView = try await loadedWebView(html: """
            <div id="chapters"><a href="1.html">第1章 开始</a><a href="9.html">第9章 最新</a></div>
            <a id="expand" href="javascript:void(0)" onclick="expandList()">[展开完整列表]</a>
            <script>
            function expandList() {
                document.getElementById('chapters').innerHTML =
                    '<a href="1.html">第1章 开始</a><a href="2.html">第2章 中途</a><a href="3.html">第3章 结束</a>';
                document.getElementById('expand').remove();
            }
            </script>
            """)
        let expanded = try await webView.callAsyncJavaScript(CatalogExpansionScripts.expand,
                                                             arguments: [:], in: nil, contentWorld: .page)
        #expect(expanded as? Bool == true)
        let html = try #require(try await webView.evaluateJavaScript("document.documentElement.outerHTML") as? String)
        let url = try #require(URL(string: "https://example.com/book/"))
        let catalog = try GenericNovelAdapter().parseCatalogPage(
            LoadedHTML(requestedURL: url, finalURL: url, html: html, retrievalKind: .webKit)
        )
        #expect(catalog.chapters.map(\.title) == ["第1章 开始", "第2章 中途", "第3章 结束"])
    }

    @Test
    func expandsUntypedMangaButtonOutsideForms() async throws {
        let webView = try await loadedWebView(html: """
            <form><input name="search"></form>
            <div class="chapters-grid"><a href="/read/a/1.html">001</a><a href="/read/a/2.html">002</a></div>
            <button class="load-more-btn" id="loadMoreBtn" onclick="expandList()">加载更多章节</button>
            <script>
            function expandList() {
                document.querySelector('.chapters-grid').insertAdjacentHTML('beforeend', '<a href="/read/a/3.html">003</a>');
            }
            </script>
            """)
        let expanded = try await webView.callAsyncJavaScript(CatalogExpansionScripts.expand,
                                                             arguments: [:], in: nil, contentWorld: .page)
        #expect(expanded as? Bool == true)
        let html = try #require(try await webView.evaluateJavaScript("document.documentElement.outerHTML") as? String)
        let url = try #require(URL(string: "https://example.com/comic/a/"))
        let catalog = try GenericMangaAdapter().parseCatalogPage(
            LoadedHTML(requestedURL: url, finalURL: url, html: html, retrievalKind: .webKit))
        #expect(catalog.chapters.map(\.title) == ["001", "002", "003"])
    }

    @Test
    func doesNotClickLoginOrSubmitControls() async throws {
        let webView = try await loadedWebView(html: """
            <a href="1.html">第1章 开始</a><a href="2.html">第2章 中途</a>
            <button type="button" onclick="window.clicked=true">登录后阅读全文</button>
            <button type="submit" onclick="window.clicked=true">展开完整列表</button>
            <form id="submitForm"><button onclick="window.clicked=true">加载更多章节</button></form>
            <button form="submitForm" onclick="window.clicked=true">加载更多章节</button>
            <script>window.clicked=false;</script>
            """)
        let expanded = try await webView.callAsyncJavaScript(CatalogExpansionScripts.expand,
                                                             arguments: [:], in: nil, contentWorld: .page)
        #expect(expanded as? Bool == false)
        let clicked = try await webView.evaluateJavaScript("window.clicked")
        #expect(clicked as? Bool == false)
    }

    private func loadedWebView(html: String) async throws -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 600, height: 800), configuration: configuration)
        webView.loadHTMLString(html, baseURL: URL(string: "https://example.com/book/"))
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        while webView.isLoading {
            guard clock.now < deadline else { throw HTMLLoadError.requestTimedOut }
            try await Task.sleep(for: .milliseconds(25))
        }
        return webView
    }
}
