import CoreFoundation
import Foundation

actor URLSessionHTMLLoader {
    private let session: URLSession
    private let limiter = HostRateLimiter()
    private var verifiedUserAgents: [String: String] = [:]

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 30
            configuration.timeoutIntervalForResource = 60
            configuration.httpCookieAcceptPolicy = .always
            configuration.httpShouldSetCookies = true
            configuration.httpAdditionalHeaders = [
                "Accept": "text/html,application/xhtml+xml",
                "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.7",
                "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Version/18.0 Safari/605.1.15 YYReader/1.0"
            ]
            self.session = URLSession(configuration: configuration)
        }
    }

    func load(_ url: URL) async throws -> LoadedHTML {
        try await limiter.wait(for: url)
        return try await request(url, mayRetryRateLimit: true)
    }

    func useVerifiedUserAgent(_ userAgent: String, forHost host: String) {
        verifiedUserAgents[host.lowercased()] = userAgent
    }

    private func request(_ url: URL, mayRetryRateLimit: Bool) async throws -> LoadedHTML {
        var urlRequest = URLRequest(url: url)
        urlRequest.cachePolicy = .reloadRevalidatingCacheData
        if let host = url.host?.lowercased(), let userAgent = verifiedUserAgents[host] {
            urlRequest.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        }
        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else { throw HTMLLoadError.invalidResponse }

        if http.statusCode == 429 {
            guard mayRetryRateLimit else { throw HTMLLoadError.rateLimited }
            let delay = Double(http.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 2
            try await Task.sleep(for: .seconds(min(max(delay, 1), 30)))
            return try await request(url, mayRetryRateLimit: false)
        }
        if http.statusCode == 403, looksLikeChallenge(data) {
            throw HTMLLoadError.verificationRequired
        }
        guard (200..<400).contains(http.statusCode) else {
            throw HTMLLoadError.httpStatus(http.statusCode)
        }

        guard let html = decode(data, encodingName: http.textEncodingName) else {
            throw HTMLLoadError.undecodableText
        }
        if HTMLChallengeDetector.isChallenge(html) { throw HTMLLoadError.verificationRequired }
        return LoadedHTML(
            requestedURL: url,
            finalURL: http.url ?? url,
            html: html,
            retrievalKind: .urlSession
        )
    }

    private func decode(_ data: Data, encodingName: String?) -> String? {
        let normalized = encodingName?.lowercased() ?? ""
        let encoding: String.Encoding
        switch normalized {
        case "gbk", "gb2312", "gb18030":
            let raw = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(0x0632))
            encoding = String.Encoding(rawValue: raw)
        case "big5":
            let raw = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(0x0A03))
            encoding = String.Encoding(rawValue: raw)
        case "iso-8859-1", "latin1":
            encoding = .isoLatin1
        default:
            encoding = .utf8
        }
        return String(data: data, encoding: encoding)
            ?? String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
    }

    private func looksLikeChallenge(_ data: Data) -> Bool {
        HTMLChallengeDetector.isChallenge(String(decoding: data.prefix(16_384), as: UTF8.self))
    }
}
