import Foundation

struct SyncFileSignature: Equatable, Sendable {
    var modificationDate: Date
    var fileSize: Int64
}
