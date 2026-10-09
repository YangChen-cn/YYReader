enum BookContentType: String, CaseIterable, Identifiable, Sendable {
    case auto, novel, manga
    var id: Self { self }
    var title: String {
        switch self {
        case .auto: "自动识别"
        case .novel: "文字小说"
        case .manga: "漫画"
        }
    }
}
