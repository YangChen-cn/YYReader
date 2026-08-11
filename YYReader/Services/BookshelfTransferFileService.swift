import Foundation

actor BookshelfTransferFileService {
    func readDocument(from url: URL) throws -> BookshelfTransferDocument {
        try BookshelfTransferCodec.decode(Data(contentsOf: url))
    }

    func writeDocument(_ document: BookshelfTransferDocument, to url: URL) throws {
        try BookshelfTransferCodec.encode(document).write(to: url, options: .atomic)
    }
}
