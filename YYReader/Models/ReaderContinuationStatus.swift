import Foundation

enum ReaderContinuationStatus: Equatable {
    case idle
    case loading
    case ready
    case attached
    case failed
    case unavailable
}
