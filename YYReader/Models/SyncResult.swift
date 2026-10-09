import Foundation

struct SyncResult: Equatable, Sendable {
    var books: [SyncBookRecord]
    var synchronizedAt: Date
    var remoteFileSignatures: [SyncDevice: SyncFileSignature]
    var windowsFileSignature: SyncFileSignature? { remoteFileSignatures[.windows] }
    var remoteCapabilities: [String]
}
