import Foundation
import Testing
@testable import YYReader

struct URLSessionHTMLLoaderTests {
    @Test
    func cfMitigatedHeaderRequiresVerificationBeforeBodyHeuristics() async throws {
        let url = try #require(URL(string: "https://novel.example/chapter"))
        StubURLProtocol.reset { request in
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 403,
                httpVersion: "HTTP/1.1",
                headerFields: ["cf-mitigated": "challenge"]
            ))
            return (response, Data("ordinary response body".utf8))
        }
        let loader = makeLoader()

        do {
            _ = try await loader.load(url)
            Issue.record("Expected Cloudflare challenge header to require verification")
        } catch HTMLLoadError.verificationRequired {
            #expect(StubURLProtocol.requestCount == 1)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func rateLimitDoesNotRetryAndPreservesRetryAfterHint() async throws {
        let url = try #require(URL(string: "https://novel.example/chapter"))
        StubURLProtocol.reset { request in
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 429,
                httpVersion: "HTTP/1.1",
                headerFields: ["Retry-After": "120"]
            ))
            return (response, Data())
        }
        let loader = makeLoader()

        do {
            _ = try await loader.load(url)
            Issue.record("Expected rate limit error")
        } catch let HTMLLoadError.rateLimited(retryAfterSeconds) {
            #expect(retryAfterSeconds == 120)
            #expect(StubURLProtocol.requestCount == 1)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    private func makeLoader() -> URLSessionHTMLLoader {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSessionHTMLLoader(
            session: URLSession(configuration: configuration),
            limiter: HostRateLimiter(defaultMinimumDelay: .zero)
        )
    }
}

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    private static let state = StubURLProtocolState()

    static var requestCount: Int { state.requestCount }

    static func reset(
        handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) {
        state.reset(handler: handler)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let (response, data) = try Self.state.response(for: request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class StubURLProtocolState: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    var requestCount: Int {
        lock.withLock { count }
    }

    func reset(handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)) {
        lock.withLock {
            count = 0
            self.handler = handler
        }
    }

    func response(for request: URLRequest) throws -> (HTTPURLResponse, Data) {
        let storedHandler = lock.withLock {
            count += 1
            return self.handler
        }
        guard let storedHandler else { throw URLError(.badServerResponse) }
        return try storedHandler(request)
    }
}
