import Foundation

enum ReaderContinuationStatus: Equatable {
    case idle
    case loading
    case checkingLatest
    case ready
    case attached
    case confirmedLatest
    case failed
    case unavailable
}
