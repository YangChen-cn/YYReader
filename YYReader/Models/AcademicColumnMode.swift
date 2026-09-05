enum AcademicColumnMode: String, CaseIterable, Identifiable {
    case single
    case double

    var id: String { rawValue }
    var title: String { self == .single ? "单栏" : "双栏" }
}
