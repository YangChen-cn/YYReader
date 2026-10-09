import SwiftUI
import UniformTypeIdentifiers

struct BookshelfFileDocument: FileDocument {
    static let contentType = UTType(exportedAs: "com.yyreader.bookshelf", conformingTo: .json)
    static var readableContentTypes: [UTType] { [contentType, .json] }
    var document: BookshelfTransferDocument

    init(document: BookshelfTransferDocument) { self.document = document }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw BookshelfTransferError.invalidDocument("文件没有可读内容。")
        }
        document = try BookshelfTransferCodec.decode(data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try BookshelfTransferCodec.encode(document))
    }
}
