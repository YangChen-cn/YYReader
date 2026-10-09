import Foundation

actor BookshelfTransferFileService {
    func readDocument(from url: URL) throws -> BookshelfTransferDocument {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        try Task.checkCancellation()
        let document = try BookshelfTransferCodec.decode(Data(contentsOf: url))
        try Task.checkCancellation()
        return document
    }

    func writeDocument(_ document: BookshelfTransferDocument, to url: URL) throws {
        try BookshelfTransferCodec.encode(document).write(to: url, options: .atomic)
    }
}
