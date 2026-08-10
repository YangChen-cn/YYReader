import Foundation

enum ReaderContinuationStatus: Equatable {
    case idle
    case loading
    case ready
    case failed
    case unavailable
}
