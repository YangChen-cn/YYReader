import Foundation

enum ContinuousReaderTailProbeState: Equatable {
    case checking
    case confirmedLatest(expiresAt: Date)
    case failed
}
