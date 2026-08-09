import Foundation

struct LoadedHTML: Sendable {
    enum RetrievalKind: String, Sendable {
        case urlSession
        case webKit
    }

    let requestedURL: URL
    let finalURL: URL
    let html: String
    let retrievalKind: RetrievalKind
}
