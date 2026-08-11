import Foundation

struct BookshelfTransferPendingImport: Identifiable, Sendable {
    let id = UUID()
    let document: BookshelfTransferDocument
    let preview: BookshelfTransferPreview
}
