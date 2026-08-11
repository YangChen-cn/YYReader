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
        case .compact: 0.30
        case .comfortable: 0.40
        case .spacious: 0.50
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
        case .narrow: 38
        case .medium: 48
        case .wide: 58
        }
    }

    static func closest(to value: Double) -> Self {
        allCases.min { abs($0.value - value) < abs($1.value - value) } ?? .medium
    }
}
