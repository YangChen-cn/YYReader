import CoreFoundation
import Foundation

actor URLSessionHTMLLoader: StaticHTMLLoading {
    private let session: URLSession
    private let limiter: HostRateLimiter

    init(session: URLSession? = nil, limiter: HostRateLimiter = HostRateLimiter()) {
        self.limiter = limiter
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
                "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.7"
            ]
            self.session = URLSession(configuration: configuration)
        }
    }

    func load(_ url: URL) async throws -> LoadedHTML {
        try await limiter.wait(for: url)
        return try await request(url)
    }

    private func request(_ url: URL) async throws -> LoadedHTML {
        var urlRequest = URLRequest(url: url)
        urlRequest.cachePolicy = .reloadRevalidatingCacheData
        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else { throw HTMLLoadError.invalidResponse }

        if http.value(forHTTPHeaderField: "cf-mitigated")?.lowercased() == "challenge" {
            throw HTMLLoadError.verificationRequired
        }
        if http.statusCode == 429 {
            throw HTMLLoadError.rateLimited(
                retryAfterSeconds: retryAfterSeconds(from: http.value(forHTTPHeaderField: "Retry-After"))
            )
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

    private func retryAfterSeconds(from value: String?) -> Int? {
        guard let value else { return nil }
        if let seconds = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return max(0, seconds)
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        for format in [
            "EEE',' dd MMM yyyy HH':'mm':'ss z",
            "EEEE',' dd-MMM-yy HH':'mm':'ss z",
            "EEE MMM d HH':'mm':'ss yyyy"
        ] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return max(0, Int(date.timeIntervalSinceNow.rounded(.up)))
            }
        }
        return nil
    }
}
