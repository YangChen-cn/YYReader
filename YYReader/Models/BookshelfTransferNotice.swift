import Foundation

struct BookshelfTransferNotice: Identifiable, Sendable {
    let id = UUID()
    let title: String
    let message: String
}
