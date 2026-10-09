enum ReaderPageTurnMode: String, CaseIterable, Identifiable {
    case verticalScroll
    case horizontalPages

    var id: String { rawValue }

    var title: String {
        switch self {
        case .verticalScroll: "上下滚动"
        case .horizontalPages: "左右翻页"
        }
    }
}
