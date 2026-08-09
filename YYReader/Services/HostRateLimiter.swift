import Foundation

actor HostRateLimiter {
    private var nextAvailable: [String: ContinuousClock.Instant] = [:]
    private let defaultMinimumDelay: Duration
    private var hostMinimumDelays: [String: Duration]

    init(
        defaultMinimumDelay: Duration = .seconds(1),
        hostMinimumDelays: [String: Duration] = [:]
    ) {
        self.defaultMinimumDelay = defaultMinimumDelay
        self.hostMinimumDelays = Dictionary(
            uniqueKeysWithValues: hostMinimumDelays.map { ($0.key.lowercased(), $0.value) }
        )
    }

    func setMinimumDelay(_ delay: Duration, forHost host: String) {
        hostMinimumDelays[host.lowercased()] = delay
    }

    func wait(for url: URL) async throws {
        let host = url.host?.lowercased() ?? ""
        let clock = ContinuousClock()
        let now = clock.now
        let delay = hostMinimumDelays[host] ?? defaultMinimumDelay
        let scheduled = max(now, nextAvailable[host] ?? now)
        nextAvailable[host] = scheduled.advanced(by: delay)

        if scheduled > now {
            try await clock.sleep(until: scheduled)
        }
    }
}
