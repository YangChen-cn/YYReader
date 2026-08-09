import Foundation
import Testing
@testable import YYReader

struct HostRateLimiterTests {
    @Test
    func concurrentSameHostRequestsReceiveSerialTimeSlots() async throws {
        let limiter = HostRateLimiter(defaultMinimumDelay: .milliseconds(50))
        let url = try #require(URL(string: "https://novel.example/chapter"))
        let clock = ContinuousClock()
        let start = clock.now

        async let first: Void = limiter.wait(for: url)
        async let second: Void = limiter.wait(for: url)
        async let third: Void = limiter.wait(for: url)
        _ = try await (first, second, third)

        #expect(start.duration(to: clock.now) >= .milliseconds(90))
    }
}
