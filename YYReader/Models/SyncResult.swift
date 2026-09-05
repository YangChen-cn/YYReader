import Foundation

struct SyncResult: Equatable, Sendable {
    var books: [SyncBookRecord]
    var synchronizedAt: Date
    var windowsFileSignature: SyncFileSignature?
    var remoteCapabilities: [String]
}
