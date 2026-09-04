enum ReaderPresentationMode: String, CaseIterable, Identifiable {
    case normal
    case academicPaper

    var id: String { rawValue }
    var title: String { self == .normal ? "普通阅读" : "论文伪装" }
}
