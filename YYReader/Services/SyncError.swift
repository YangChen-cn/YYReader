import Foundation

enum SyncError: LocalizedError, Sendable {
    case malformedSnapshot(String)
    case invalidFormat(String)
    case unsupportedVersion(Int)
    case unexpectedDevice(expected: SyncDevice, actual: SyncDevice)
    case invalidBook(String)
    case folderUnavailable

    var errorDescription: String? {
        switch self {
        case .malformedSnapshot(let message):
            "同步文件 JSON 无法读取：\(message)"
        case .invalidFormat(let format):
            "无法识别同步格式：\(format)"
        case .unsupportedVersion(let version):
            "暂不支持 SyncSnapshot v\(version)"
        case .unexpectedDevice(let expected, let actual):
            "同步文件设备类型错误：预期 \(expected.rawValue)，实际为 \(actual.rawValue)"
        case .invalidBook(let message):
            "同步书籍数据无效：\(message)"
        case .folderUnavailable:
            "同步文件夹暂时不可访问"
        }
    }
}
