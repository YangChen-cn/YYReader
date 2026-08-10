import Foundation

enum ReaderLineSpacingPreset: String, CaseIterable, Identifiable {
    case compact
    case comfortable
    case spacious

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact: "紧凑"
        case .comfortable: "舒适"
        case .spacious: "宽松"
        }
    }

    var value: Double {
        switch self {
        case .compact: 5
        case .comfortable: 8
        case .spacious: 12
        }
    }

    static func closest(to value: Double) -> Self {
        allCases.min { abs($0.value - value) < abs($1.value - value) } ?? .comfortable
    }
}

enum ReaderContentWidthPreset: String, CaseIterable, Identifiable {
    case narrow
    case medium
    case wide

    var id: String { rawValue }

    var title: String {
        switch self {
        case .narrow: "窄"
        case .medium: "中"
        case .wide: "宽"
        }
    }

    var value: Double {
        switch self {
        case .narrow: 720
        case .medium: 1_040
        case .wide: 1_600
        }
    }

    static func closest(to value: Double) -> Self {
        allCases.min { abs($0.value - value) < abs($1.value - value) } ?? .medium
    }
}
