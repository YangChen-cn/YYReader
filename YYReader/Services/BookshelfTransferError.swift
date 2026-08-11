import Foundation

enum BookshelfTransferError: LocalizedError, Equatable {
    case malformedJSON(String)
    case invalidDocument(String)
    case unsupportedVersion(Int)
    case clipboardUnavailable

    var errorDescription: String? {
        switch self {
        case .malformedJSON(let detail):
            "JSON 无法解析：\(detail)"
        case .invalidDocument(let detail):
            detail
        case .unsupportedVersion(let version):
            "暂不支持 BookshelfTransfer v\(version)，当前支持 v\(BookshelfTransferCodec.currentVersion)。未知的可选字段会被忽略。"
        case .clipboardUnavailable:
            "剪贴板中没有可识别的 YYReader 书架 JSON。"
        }
    }
}
