import SwiftUI

enum ReaderFontFamily: String, CaseIterable, Identifiable {
    case system
    case serif
    case rounded
    case kaiti

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "系统"
        case .serif: "宋体"
        case .rounded: "圆体"
        case .kaiti: "楷体"
        }
    }

    func font(size: Double) -> Font {
        switch self {
        case .system: .system(size: size)
        case .serif: .system(size: size, design: .serif)
        case .rounded: .system(size: size, design: .rounded)
        case .kaiti: .custom("Kaiti SC", size: size, relativeTo: .body)
        }
    }
}
