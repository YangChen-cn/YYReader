import Foundation

actor HostRateLimiter {
    private var lastRequest: [String: ContinuousClock.Instant] = [:]
    private let minimumDelay: Duration

    init(minimumDelay: Duration = .milliseconds(250)) {
        self.minimumDelay = minimumDelay
    }

    func wait(for url: URL) async throws {
        let host = url.host?.lowercased() ?? ""
        let clock = ContinuousClock()
        if let previous = lastRequest[host] {
            let elapsed = previous.duration(to: clock.now)
            if elapsed < minimumDelay {
                try await Task.sleep(for: minimumDelay - elapsed)
            }
        }
        lastRequest[host] = clock.now
    }
}
