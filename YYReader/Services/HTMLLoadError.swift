import Foundation

enum HTMLLoadError: LocalizedError, Sendable {
    case invalidResponse
    case httpStatus(Int)
    case rateLimited
    case verificationRequired
    case verificationFailed(String)
    case verificationTimedOut
    case undecodableText
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "网站返回了无法识别的响应。"
        case let .httpStatus(code): "网页请求失败（HTTP \(code)）。"
        case .rateLimited: "网站请求过于频繁，请稍后重试。"
        case .verificationRequired: "网站要求完成浏览器验证。"
        case let .verificationFailed(message): "网站验证失败：\(message)"
        case .verificationTimedOut: "网站验证等待超时，导入已停止。请稍后重试。"
        case .undecodableText: "无法识别网页的文字编码。"
        case .cancelled: "已取消网页验证。"
        }
    }
}
