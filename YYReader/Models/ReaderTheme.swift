import SwiftUI

enum ReaderTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case sepia
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .sepia: "米色"
        case .dark: "深色"
        }
    }

    var background: Color {
        switch self {
        case .system: Color(nsColor: .textBackgroundColor)
        case .light: Color(red: 0.97, green: 0.97, blue: 0.95)
        case .sepia: Color(red: 0.93, green: 0.88, blue: 0.76)
        case .dark: Color(red: 0.10, green: 0.11, blue: 0.12)
        }
    }

    var foreground: Color {
        switch self {
        case .system: .primary
        case .light: Color(red: 0.12, green: 0.12, blue: 0.11)
        case .sepia: Color(red: 0.20, green: 0.16, blue: 0.10)
        case .dark: Color(red: 0.88, green: 0.88, blue: 0.86)
        }
    }
}
