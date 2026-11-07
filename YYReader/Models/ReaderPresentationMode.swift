enum ReaderPresentationMode: String, CaseIterable, Identifiable {
    case normal
    case academicPaper
    case sillyTavern

    var id: String { rawValue }
    var title: String {
        switch self {
        case .normal: "普通阅读"
        case .academicPaper: "论文伪装"
        case .sillyTavern: "SillyTavern"
        }
    }
}
