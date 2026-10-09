import Foundation

enum NovelParsingError: LocalizedError, Sendable {
    case unsupportedURL
    case noReadableContent
    case missingCatalog
    case catalogNeedsExpansion
    case paginationLimit
    case paginationLoop
    case catalogRefreshTimedOut

    var errorDescription: String? {
        switch self {
        case .unsupportedURL: "只支持 HTTP 或 HTTPS 小说网页。"
        case .noReadableContent: "没有识别到可阅读的章节正文。"
        case .missingCatalog: "没有识别到小说目录页。"
        case .catalogNeedsExpansion: "完整目录需要网页展开，但未能载入完整章节列表。请稍后重试或换一个目录网址。"
        case .paginationLimit: "网页分页数量异常，已停止继续加载。"
        case .paginationLoop: "网页分页出现循环，已停止继续加载。"
        case .catalogRefreshTimedOut: "目录刷新耗时过长，已自动停止。已缓存章节不受影响，请稍后重试。"
        }
    }
}
