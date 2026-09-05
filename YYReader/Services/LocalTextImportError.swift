import Foundation

enum LocalTextImportError: LocalizedError {
    case invalidFileType
    case emptyFile
    case unsupportedEncoding
    case noReadableContent
    case persistenceFailed

    var errorDescription: String? {
        switch self {
        case .invalidFileType:
            return "请选择扩展名为 .txt 的文本文件。"
        case .emptyFile:
            return "这个 TXT 文件是空的。"
        case .unsupportedEncoding:
            return "无法使用 UTF-8、GBK 或 GB18030 解码这个文件。"
        case .noReadableContent:
            return "没有在 TXT 文件中找到可阅读的正文。"
        case .persistenceFailed:
            return "无法把 TXT 小说保存到本地书架。"
        }
    }
}
