import SwiftUI

enum ReaderFontFamily: String, CaseIterable, Identifiable {
    case system
    case serif
    case kaiti
    case rounded

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "系统"
        case .serif: "宋体"
        case .rounded: "圆体"
        case .kaiti: "楷体"
        }
    }

    @MainActor func font(size: Double) -> Font {
        switch self {
        case .system: .system(size: size)
        #if os(iOS)
        case .serif: Font(MobileReadingFont.resolve(.serif, size: size))
        #else
        case .serif: .system(size: size, design: .serif)
        #endif
        case .rounded: .system(size: size, design: .rounded)
        case .kaiti: .custom("Kaiti SC", fixedSize: size)
        }
    }
}
