import Foundation

/// Optional content sidecar. Progress remains in the existing device snapshots.
struct CloudTextArchive: Codable, Sendable {
    var version = 1
    let draft: LocalTextImportDraft
    let author: String
}
